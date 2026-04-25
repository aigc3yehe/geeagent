use std::{
    collections::HashMap,
    env, fs,
    path::{Path, PathBuf},
    time::Duration,
};

use agent_kernel::AgentProfile;
use execution_runtime::{
    capture_host_runtime_facts, ControlledTerminalPlanKind, ControlledTerminalRequest,
    ControlledTerminalStep, ControlledTerminalStepCondition,
};
use model_router::{RouteClass, RoutingConfig};
use reqwest::Client;
use serde::{de::DeserializeOwned, Deserialize, Serialize};

const MAIN_PROFILE_NAME: &str = "main";
const WORKSPACE_SYSTEM_PROMPT: &str = "You are GeeAgent, a rational and calm macOS desktop companion. Reply clearly and concisely. Stay action-oriented. If an action would require review or external publishing, mention that boundary instead of pretending it already happened.";
const QUICK_INPUT_SYSTEM_PROMPT: &str = "You are GeeAgent in quick input mode. Reply in at most two concise sentences. Confirm the request, mention the next likely action, and call out any review boundary if relevant.";
const WORKSPACE_PLANNER_SYSTEM_PROMPT: &str = r#"You are GeeAgent's local turn planner for the main workspace.

You are operating inside a bounded agent loop. Your job is to decide the next step, not to stop after one generic sentence.

Use the injected runtime facts directly. If the current local time is already present in runtime facts, do not ask for another time lookup.

When the user needs local inspection or execution, prefer a controlled terminal plan. A controlled terminal plan can run 1-4 shell steps inside the shared GeeAgent terminal lane, with approval handled by the host when needed.

Terminal planning rules:
- each step must be one command token plus an args array
- never use shell chaining such as &&, ;, |, or inline cd
- use cwd for directory changes instead of cd
- keep steps grounded and minimal
- prefer read-first diagnostics before mutating commands
- prefer simple guarded read-only commands when possible: pwd, ls, cat, grep, rg, find, git status, ps, lsof, docker ps -a
- avoid multiline shell args; every arg must fit on one line
- avoid python -c / node -e unless no simpler guarded read-only command can do the job
- if the task is obviously ambiguous, ask a clarification instead of inventing details

Return JSON only. No markdown. No prose outside JSON.

Schema:
{
  "decision": "reply" | "clarify" | "controlled_terminal",
  "assistant_reply": "string, required for reply/clarify",
  "quick_reply": "string, optional but preferred for reply/clarify",
  "terminal_plan": {
    "goal": "string",
    "plan_summary": "string",
    "kind": "docker_containers" | "git_status" | "directory_listing" | "host_diagnostics" | "generic_shell",
    "subject": "required for generic_shell",
    "only_startable": false,
    "include_current_time": false,
    "steps": [
      {
        "title": "string",
        "command": "single-token command",
        "args": ["arg1", "arg2"],
        "cwd": "/absolute/or/repo/path/or-null",
        "condition": "always" | "if_previous_python_inspection_empty"
      }
    ]
  }
}"#;
const QUICK_PLANNER_SYSTEM_PROMPT: &str = r#"You are GeeAgent's quick-input turn planner.

Decide whether this should be answered directly, clarified, or turned into a controlled terminal plan for the shared local agent loop.

Use injected runtime facts directly. Do not ask for a separate time lookup when local time is already present.

If local shell work is needed, emit a controlled terminal plan with 1-4 grounded steps. Each step must be a single command token plus args. Never use &&, ;, |, or inline cd. Use cwd instead.
Prefer simple guarded read-only commands such as pwd, ls, cat, grep, rg, find, git status, ps, lsof, and docker ps -a before resorting to python -c or node -e.
Avoid multiline args entirely.

Return JSON only. No markdown. No prose outside JSON.

Schema:
{
  "decision": "reply" | "clarify" | "controlled_terminal",
  "assistant_reply": "string, required for reply/clarify",
  "quick_reply": "string, optional but preferred for reply/clarify",
  "terminal_plan": {
    "goal": "string",
    "plan_summary": "string",
    "kind": "docker_containers" | "git_status" | "directory_listing" | "host_diagnostics" | "generic_shell",
    "subject": "required for generic_shell",
    "only_startable": false,
    "include_current_time": false,
    "steps": [
      {
        "title": "string",
        "command": "single-token command",
        "args": ["arg1", "arg2"],
        "cwd": "/absolute/or/repo/path/or-null",
        "condition": "always" | "if_previous_python_inspection_empty"
      }
    ]
  }
}"#;
const DEFAULT_MODEL_ROUTING_TOML: &str = include_str!("../../../../config/model-routing.toml");
const DEFAULT_CHAT_RUNTIME_TOML: &str = include_str!("../../../../config/chat-runtime.toml");
const MODEL_ROUTING_FILE_NAME: &str = "model-routing.toml";
const CHAT_RUNTIME_SECRETS_FILE_NAME: &str = "chat-runtime-secrets.toml";

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RuntimeFacts {
    pub local_time: String,
    pub time_zone: String,
    pub cwd: String,
    pub surface: String,
}

impl RuntimeFacts {
    pub fn capture(surface: &str) -> Self {
        let host_facts = capture_host_runtime_facts();
        Self {
            local_time: host_facts.local_time,
            time_zone: if host_facts.time_zone.trim().is_empty() {
                env::var("TZ").unwrap_or_else(|_| "local".to_string())
            } else {
                host_facts.time_zone
            },
            cwd: host_facts.cwd,
            surface: surface.to_string(),
        }
    }
}

fn sanitize_prompt_value(value: &str) -> String {
    value.trim().replace('"', "'")
}

fn system_prompt_for_active_agent(
    base_prompt: &str,
    profile: &AgentProfile,
    runtime_facts: &RuntimeFacts,
) -> String {
    format!(
        "{base_prompt}\n\n[RUNTIME_FACTS]\nlocal_time = \"{}\"\ntime_zone = \"{}\"\ncwd = \"{}\"\nsurface = \"{}\"\n\n[ACTIVE_AGENT]\nname = \"{}\"\nid = \"{}\"\ntagline = \"{}\"\n\n[AGENT_DEFINITION]\n{}",
        sanitize_prompt_value(&runtime_facts.local_time),
        sanitize_prompt_value(&runtime_facts.time_zone),
        sanitize_prompt_value(&runtime_facts.cwd),
        sanitize_prompt_value(&runtime_facts.surface),
        sanitize_prompt_value(&profile.name),
        sanitize_prompt_value(&profile.id),
        sanitize_prompt_value(&profile.tagline),
        profile.personality_prompt.trim()
    )
}

#[derive(Clone, Debug, PartialEq, Deserialize)]
pub struct ChatProviderConfig {
    pub enabled: bool,
    pub api_key_env: String,
    pub chat_completions_url: String,
    pub model_discovery_url: String,
    pub model_override_env: String,
    pub default_model: String,
}

#[derive(Clone, Debug, PartialEq, Deserialize)]
pub struct ChatRuntimeConfig {
    pub version: u8,
    pub request_timeout_seconds: u64,
    pub temperature: f32,
    pub max_completion_tokens: u32,
    #[serde(default)]
    pub fallback_provider_order: Vec<String>,
    #[serde(default)]
    pub providers: HashMap<String, ChatProviderConfig>,
}

#[derive(Clone, Debug, Default, PartialEq, Deserialize, Serialize)]
pub struct ChatProviderSecrets {
    #[serde(default)]
    pub api_key: Option<String>,
    #[serde(default)]
    pub model_override: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
pub struct ChatRuntimeSecretsConfig {
    #[serde(default = "default_secrets_version")]
    pub version: u8,
    #[serde(default)]
    pub providers: HashMap<String, ChatProviderSecrets>,
}

#[derive(Clone, Debug, Default, PartialEq, Deserialize, Serialize)]
pub struct ChatRuntimeSetupInput {
    #[serde(default)]
    pub openai_api_key: Option<String>,
    #[serde(default)]
    pub xenodia_api_key: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RouteClassSetting {
    pub name: String,
    pub provider: String,
    pub model: String,
    pub reasoning_effort: String,
    pub fallback_model: String,
}

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProfileRouteSetting {
    pub name: String,
    pub default_route_class: String,
}

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatRoutingSettings {
    pub default_route_class: String,
    pub allow_user_overrides: bool,
    #[serde(default)]
    pub provider_choices: Vec<String>,
    pub route_classes: Vec<RouteClassSetting>,
    pub profiles: Vec<ProfileRouteSetting>,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct WorkspaceChatReply {
    pub provider_name: String,
    pub model: String,
    pub content: String,
}

#[derive(Clone, Debug, PartialEq)]
pub struct TurnPlannerReply {
    pub provider_name: String,
    pub model: String,
    pub decision: PlannedTurnDecision,
}

#[derive(Clone, Debug, PartialEq)]
pub enum PlannedTurnDecision {
    Reply {
        assistant_reply: String,
        quick_reply: String,
    },
    Clarify {
        assistant_reply: String,
        quick_reply: String,
    },
    ControlledTerminal {
        request: ControlledTerminalRequest,
    },
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct ChatReadiness {
    pub status: String,
    pub active_provider: Option<String>,
    pub detail: String,
}

#[derive(Clone, Debug, PartialEq)]
pub struct WorkspaceChatMessage {
    pub role: String,
    pub content: String,
}

#[derive(Clone, Debug, PartialEq)]
struct ResolvedProvider {
    name: String,
    api_key: String,
    chat_completions_url: String,
    model: String,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ClaudeSdkGatewayBackend {
    pub api_key: String,
    pub chat_completions_url: String,
    pub model: String,
}

#[derive(Clone)]
pub struct ChatRuntime {
    client: Client,
    routing: RoutingConfig,
    config: ChatRuntimeConfig,
    secrets: ChatRuntimeSecretsConfig,
}

#[derive(Debug, Deserialize)]
struct ChatCompletionResponse {
    choices: Vec<ChatCompletionChoice>,
}

#[derive(Debug, Deserialize)]
struct ChatCompletionChoice {
    message: ChatCompletionMessage,
}

#[derive(Debug, Deserialize)]
struct ChatCompletionMessage {
    content: String,
}

#[derive(Debug, Deserialize)]
struct ChatCompletionErrorEnvelope {
    error: Option<ChatCompletionErrorBody>,
}

#[derive(Debug, Deserialize)]
struct ChatCompletionErrorBody {
    message: Option<String>,
}

#[derive(Debug, Serialize)]
struct ChatCompletionRequest<'a> {
    model: &'a str,
    messages: Vec<ChatCompletionRequestMessage<'a>>,
    temperature: f32,
    max_completion_tokens: u32,
}

#[derive(Debug, Serialize)]
struct ChatCompletionRequestMessage<'a> {
    role: &'a str,
    content: &'a str,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "snake_case")]
enum PlannerDecisionKind {
    Reply,
    Clarify,
    ControlledTerminal,
}

#[derive(Debug, Deserialize)]
struct PlannerEnvelope {
    decision: PlannerDecisionKind,
    #[serde(default)]
    assistant_reply: Option<String>,
    #[serde(default)]
    quick_reply: Option<String>,
    #[serde(default)]
    terminal_plan: Option<PlannerTerminalPlan>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "snake_case")]
enum PlannerTerminalKind {
    DockerContainers,
    GitStatus,
    DirectoryListing,
    HostDiagnostics,
    GenericShell,
}

#[derive(Debug, Deserialize)]
struct PlannerTerminalPlan {
    goal: String,
    plan_summary: String,
    kind: PlannerTerminalKind,
    #[serde(default)]
    subject: Option<String>,
    #[serde(default)]
    only_startable: bool,
    #[serde(default)]
    include_current_time: bool,
    #[serde(default)]
    steps: Vec<PlannerTerminalStep>,
}

#[derive(Debug, Deserialize)]
struct PlannerTerminalStep {
    title: String,
    command: String,
    #[serde(default)]
    args: Vec<String>,
    #[serde(default)]
    cwd: Option<String>,
    #[serde(default)]
    condition: PlannerTerminalStepCondition,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "snake_case")]
enum PlannerTerminalStepCondition {
    #[default]
    Always,
    IfPreviousPythonInspectionEmpty,
}

impl ChatRuntimeConfig {
    pub fn from_toml_str(input: &str) -> Result<Self, String> {
        toml::from_str(input).map_err(|error| error.to_string())
    }
}

fn default_secrets_version() -> u8 {
    1
}

impl Default for ChatRuntimeSecretsConfig {
    fn default() -> Self {
        Self {
            version: default_secrets_version(),
            providers: HashMap::new(),
        }
    }
}

fn load_config_text(
    override_dir: Option<&Path>,
    file_name: &str,
    embedded_default: &str,
) -> Result<String, String> {
    if let Ok(env_override) = env::var("GEEAGENT_CONFIG_DIR") {
        let path = PathBuf::from(env_override).join(file_name);
        if path.exists() {
            return fs::read_to_string(path).map_err(|error| error.to_string());
        }
    }

    if let Some(override_dir) = override_dir {
        let path = override_dir.join(file_name);
        if path.exists() {
            return fs::read_to_string(path).map_err(|error| error.to_string());
        }
    }

    let repo_path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../..")
        .join("config")
        .join(file_name);
    if repo_path.exists() {
        return fs::read_to_string(repo_path).map_err(|error| error.to_string());
    }

    Ok(embedded_default.to_string())
}

pub fn load_chat_routing_settings(
    config_dir: Option<&Path>,
) -> Result<ChatRoutingSettings, String> {
    let routing_raw = load_config_text(
        config_dir,
        MODEL_ROUTING_FILE_NAME,
        DEFAULT_MODEL_ROUTING_TOML,
    )?;
    let chat_runtime_raw =
        load_config_text(config_dir, "chat-runtime.toml", DEFAULT_CHAT_RUNTIME_TOML)?;
    let routing = RoutingConfig::from_toml_str(&routing_raw).map_err(|error| error.to_string())?;
    let chat_runtime = ChatRuntimeConfig::from_toml_str(&chat_runtime_raw)?;

    Ok(ChatRoutingSettings {
        default_route_class: routing.default_route_class.clone(),
        allow_user_overrides: routing.allow_user_overrides,
        provider_choices: sorted_provider_choices(&chat_runtime),
        route_classes: sorted_route_class_settings(&routing),
        profiles: sorted_profile_route_settings(&routing),
    })
}

pub fn persist_chat_routing_settings(
    config_dir: &Path,
    settings: &ChatRoutingSettings,
) -> Result<(), String> {
    fs::create_dir_all(config_dir).map_err(|error| error.to_string())?;

    let existing_raw = load_config_text(
        Some(config_dir),
        MODEL_ROUTING_FILE_NAME,
        DEFAULT_MODEL_ROUTING_TOML,
    )?;
    let chat_runtime_raw = load_config_text(
        Some(config_dir),
        "chat-runtime.toml",
        DEFAULT_CHAT_RUNTIME_TOML,
    )?;
    let mut routing =
        RoutingConfig::from_toml_str(&existing_raw).map_err(|error| error.to_string())?;
    let chat_runtime = ChatRuntimeConfig::from_toml_str(&chat_runtime_raw)?;

    validate_chat_routing_settings(settings, &chat_runtime)?;

    routing.default_route_class = settings.default_route_class.clone();
    routing.allow_user_overrides = settings.allow_user_overrides;
    routing.route_classes = settings
        .route_classes
        .iter()
        .map(|route_class| {
            (
                route_class.name.clone(),
                RouteClass {
                    provider: route_class.provider.clone(),
                    model: route_class.model.clone(),
                    reasoning_effort: route_class.reasoning_effort.clone(),
                    fallback_model: route_class.fallback_model.clone(),
                },
            )
        })
        .collect();

    for profile in &settings.profiles {
        let Some(existing_profile) = routing.profiles.get_mut(&profile.name) else {
            return Err(format!(
                "profile `{}` is not defined in the current routing config",
                profile.name
            ));
        };
        existing_profile.default_route_class = profile.default_route_class.clone();
    }

    let serialized = toml::to_string_pretty(&routing).map_err(|error| error.to_string())?;
    fs::write(config_dir.join(MODEL_ROUTING_FILE_NAME), serialized)
        .map_err(|error| error.to_string())
}

impl ChatRuntime {
    pub fn from_config_dir(config_dir: Option<&Path>) -> Result<Self, String> {
        let routing_raw =
            load_config_text(config_dir, "model-routing.toml", DEFAULT_MODEL_ROUTING_TOML)?;
        let chat_runtime_raw =
            load_config_text(config_dir, "chat-runtime.toml", DEFAULT_CHAT_RUNTIME_TOML)?;
        let routing =
            RoutingConfig::from_toml_str(&routing_raw).map_err(|error| error.to_string())?;
        let config = ChatRuntimeConfig::from_toml_str(&chat_runtime_raw)?;
        let secrets = load_chat_runtime_secrets(config_dir)?;
        let client = Client::builder()
            .timeout(Duration::from_secs(config.request_timeout_seconds))
            .build()
            .map_err(|error| error.to_string())?;

        Ok(Self {
            client,
            routing,
            config,
            secrets,
        })
    }

    pub async fn generate_workspace_reply_for_profile(
        &self,
        profile: &AgentProfile,
        runtime_facts: &RuntimeFacts,
        conversation_messages: &[WorkspaceChatMessage],
        next_user_message: &str,
    ) -> Result<WorkspaceChatReply, String> {
        let route_class = self.resolve_route_class(MAIN_PROFILE_NAME)?;
        let provider = self.resolve_provider(&route_class)?;
        self.call_chat_completions(
            &provider,
            &system_prompt_for_active_agent(WORKSPACE_SYSTEM_PROMPT, profile, runtime_facts),
            conversation_messages,
            next_user_message,
        )
        .await
    }

    pub async fn generate_quick_reply_for_profile(
        &self,
        profile: &AgentProfile,
        runtime_facts: &RuntimeFacts,
        prompt: &str,
    ) -> Result<WorkspaceChatReply, String> {
        let route_class = self.resolve_route_class(MAIN_PROFILE_NAME)?;
        let provider = self.resolve_provider(&route_class)?;
        self.call_chat_completions(
            &provider,
            &system_prompt_for_active_agent(QUICK_INPUT_SYSTEM_PROMPT, profile, runtime_facts),
            &[],
            prompt,
        )
        .await
    }

    pub async fn plan_workspace_turn_for_profile(
        &self,
        profile: &AgentProfile,
        runtime_facts: &RuntimeFacts,
        conversation_messages: &[WorkspaceChatMessage],
        next_user_message: &str,
    ) -> Result<TurnPlannerReply, String> {
        let route_class = self.resolve_route_class(MAIN_PROFILE_NAME)?;
        let provider = self.resolve_provider(&route_class)?;
        let reply = self
            .call_chat_completions(
                &provider,
                &system_prompt_for_active_agent(
                    WORKSPACE_PLANNER_SYSTEM_PROMPT,
                    profile,
                    runtime_facts,
                ),
                conversation_messages,
                next_user_message,
            )
            .await?;
        let decision = parse_turn_planner_response(&reply.content)?;

        Ok(TurnPlannerReply {
            provider_name: reply.provider_name,
            model: reply.model,
            decision,
        })
    }

    pub async fn plan_quick_turn_for_profile(
        &self,
        profile: &AgentProfile,
        runtime_facts: &RuntimeFacts,
        prompt: &str,
    ) -> Result<TurnPlannerReply, String> {
        let route_class = self.resolve_route_class(MAIN_PROFILE_NAME)?;
        let provider = self.resolve_provider(&route_class)?;
        let reply = self
            .call_chat_completions(
                &provider,
                &system_prompt_for_active_agent(
                    QUICK_PLANNER_SYSTEM_PROMPT,
                    profile,
                    runtime_facts,
                ),
                &[],
                prompt,
            )
            .await?;
        let decision = parse_turn_planner_response(&reply.content)?;

        Ok(TurnPlannerReply {
            provider_name: reply.provider_name,
            model: reply.model,
            decision,
        })
    }

    pub fn readiness(&self) -> ChatReadiness {
        match self.resolve_route_class(MAIN_PROFILE_NAME) {
            Ok(route_class) => match self.resolve_provider(&route_class) {
                Ok(provider) => ChatReadiness {
                    status: "live".to_string(),
                    active_provider: Some(provider.name.clone()),
                    detail: format!(
                        "Live chat via {}. Ready for workspace chat and quick replies.",
                        provider.name
                    ),
                },
                Err(error) if error.contains("API key") || error.contains("not configured") => {
                    ChatReadiness {
                        status: "needs_setup".to_string(),
                        active_provider: None,
                        detail: "Live chat is waiting for provider configuration.".to_string(),
                    }
                }
                Err(error) => ChatReadiness {
                    status: "degraded".to_string(),
                    active_provider: None,
                    detail: format!("Chat runtime is degraded. {}", error),
                },
            },
            Err(error) => ChatReadiness {
                status: "degraded".to_string(),
                active_provider: None,
                detail: format!("Chat routing is degraded. {}", error),
            },
        }
    }

    pub fn xenodia_gateway_backend(&self) -> Result<ClaudeSdkGatewayBackend, String> {
        let provider_name = "xenodia";
        let provider_config =
            self.config.providers.get(provider_name).ok_or_else(|| {
                "xenodia provider is not defined in chat runtime config".to_string()
            })?;

        if !provider_config.enabled {
            return Err("xenodia provider is disabled in chat runtime config".to_string());
        }

        let environment = env::vars().collect::<HashMap<_, _>>();
        let provider_secrets = self.secrets.providers.get(provider_name);

        let api_key = environment
            .get(&provider_config.api_key_env)
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
            .or_else(|| {
                provider_secrets
                    .and_then(|secrets| secrets.api_key.clone())
                    .map(|value| value.trim().to_string())
                    .filter(|value| !value.is_empty())
            })
            .ok_or_else(|| {
                format!(
                    "xenodia provider is missing an API key. Expected {} or a saved xenodia key",
                    provider_config.api_key_env
                )
            })?;

        let routed_model = self
            .resolve_route_class(MAIN_PROFILE_NAME)
            .ok()
            .filter(|route_class| route_class.provider.eq_ignore_ascii_case(provider_name))
            .map(|route_class| route_class.model);

        let model = environment
            .get(&provider_config.model_override_env)
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
            .or_else(|| {
                provider_secrets
                    .and_then(|secrets| secrets.model_override.clone())
                    .map(|value| value.trim().to_string())
                    .filter(|value| !value.is_empty())
            })
            .or(routed_model)
            .unwrap_or_else(|| provider_config.default_model.clone());

        Ok(ClaudeSdkGatewayBackend {
            api_key,
            chat_completions_url: provider_config.chat_completions_url.clone(),
            model,
        })
    }

    fn resolve_route_class(&self, profile_name: &str) -> Result<RouteClass, String> {
        let profile =
            self.routing.profiles.get(profile_name).ok_or_else(|| {
                format!("profile `{profile_name}` is not defined in model routing")
            })?;

        self.routing
            .route_classes
            .get(&profile.default_route_class)
            .cloned()
            .ok_or_else(|| {
                format!(
                    "route class `{}` is not defined in model routing",
                    profile.default_route_class
                )
            })
    }

    fn resolve_provider(&self, route_class: &RouteClass) -> Result<ResolvedProvider, String> {
        let environment = env::vars().collect::<HashMap<_, _>>();
        self.resolve_provider_with_environment(route_class, &environment)
    }

    fn resolve_provider_with_environment(
        &self,
        route_class: &RouteClass,
        environment: &HashMap<String, String>,
    ) -> Result<ResolvedProvider, String> {
        let mut provider_order = vec![route_class.provider.to_lowercase()];
        for provider_name in &self.config.fallback_provider_order {
            if !provider_order.contains(provider_name) {
                provider_order.push(provider_name.clone());
            }
        }

        let mut missing_key_providers = Vec::new();
        for provider_name in provider_order {
            let Some(provider_config) = self.config.providers.get(&provider_name) else {
                continue;
            };

            if !provider_config.enabled {
                continue;
            }

            let provider_secrets = self.secrets.providers.get(&provider_name);
            let api_key = environment
                .get(&provider_config.api_key_env)
                .map(|value| value.trim().to_string())
                .filter(|value| !value.is_empty())
                .or_else(|| {
                    provider_secrets
                        .and_then(|secrets| secrets.api_key.clone())
                        .map(|value| value.trim().to_string())
                        .filter(|value| !value.is_empty())
                });

            let Some(api_key) = api_key else {
                missing_key_providers.push(provider_name);
                continue;
            };

            let model = if provider_name == route_class.provider {
                environment
                    .get(&provider_config.model_override_env)
                    .map(|value| value.trim().to_string())
                    .filter(|value| !value.is_empty())
                    .or_else(|| {
                        provider_secrets
                            .and_then(|secrets| secrets.model_override.clone())
                            .map(|value| value.trim().to_string())
                            .filter(|value| !value.is_empty())
                    })
                    .unwrap_or_else(|| route_class.model.clone())
            } else {
                environment
                    .get(&provider_config.model_override_env)
                    .map(|value| value.trim().to_string())
                    .filter(|value| !value.is_empty())
                    .or_else(|| {
                        provider_secrets
                            .and_then(|secrets| secrets.model_override.clone())
                            .map(|value| value.trim().to_string())
                            .filter(|value| !value.is_empty())
                    })
                    .unwrap_or_else(|| provider_config.default_model.clone())
            };

            return Ok(ResolvedProvider {
                name: provider_name,
                api_key,
                chat_completions_url: provider_config.chat_completions_url.clone(),
                model,
            });
        }

        if missing_key_providers.is_empty() {
            return Err("no enabled chat providers are defined".to_string());
        }

        Err(format!(
            "no chat provider API key is configured. Expected one of: {}",
            missing_key_providers
                .iter()
                .filter_map(|provider_name| self.config.providers.get(provider_name))
                .map(|provider_config| provider_config.api_key_env.as_str())
                .collect::<Vec<_>>()
                .join(", ")
        ))
    }

    async fn call_chat_completions(
        &self,
        provider: &ResolvedProvider,
        system_prompt: &str,
        conversation_messages: &[WorkspaceChatMessage],
        next_user_message: &str,
    ) -> Result<WorkspaceChatReply, String> {
        let mut messages = vec![ChatCompletionRequestMessage {
            role: "system",
            content: system_prompt,
        }];

        for message in conversation_messages {
            if message.content.trim().is_empty() {
                continue;
            }

            messages.push(ChatCompletionRequestMessage {
                role: message.role.as_str(),
                content: message.content.as_str(),
            });
        }

        messages.push(ChatCompletionRequestMessage {
            role: "user",
            content: next_user_message,
        });

        let request_body = ChatCompletionRequest {
            model: provider.model.as_str(),
            messages,
            temperature: self.config.temperature,
            max_completion_tokens: self.config.max_completion_tokens,
        };

        let response = self
            .client
            .post(provider.chat_completions_url.as_str())
            .header("Authorization", format!("Bearer {}", provider.api_key))
            .header("Content-Type", "application/json")
            .json(&request_body)
            .send()
            .await
            .map_err(|error| error.to_string())?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.map_err(|error| error.to_string())?;
            let parsed_error = serde_json::from_str::<ChatCompletionErrorEnvelope>(&body)
                .ok()
                .and_then(|payload| payload.error)
                .and_then(|payload| payload.message);

            return Err(parsed_error
                .unwrap_or_else(|| format!("provider request failed with status {status}")));
        }

        let payload = response
            .json::<ChatCompletionResponse>()
            .await
            .map_err(|error| error.to_string())?;
        let content = payload
            .choices
            .first()
            .map(|choice| choice.message.content.trim().to_string())
            .filter(|content| !content.is_empty())
            .ok_or_else(|| "provider response did not contain assistant text".to_string())?;

        Ok(WorkspaceChatReply {
            provider_name: provider.name.clone(),
            model: provider.model.clone(),
            content,
        })
    }
}

fn parse_turn_planner_response(raw: &str) -> Result<PlannedTurnDecision, String> {
    let envelope = parse_json_payload::<PlannerEnvelope>(raw)
        .map_err(|error| format!("turn planner response was not valid structured JSON: {error}"))?;
    envelope.into_planned_turn()
}

fn parse_json_payload<T: DeserializeOwned>(raw: &str) -> Result<T, String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Err("response was empty".to_string());
    }

    if let Ok(payload) = serde_json::from_str::<T>(trimmed) {
        return Ok(payload);
    }

    if let Some(fenced) = strip_json_code_fence(trimmed) {
        if let Ok(payload) = serde_json::from_str::<T>(fenced) {
            return Ok(payload);
        }
    }

    if let Some(object_candidate) = extract_json_object_candidate(trimmed) {
        serde_json::from_str::<T>(object_candidate).map_err(|error| error.to_string())
    } else {
        Err("no JSON object could be extracted".to_string())
    }
}

fn strip_json_code_fence(raw: &str) -> Option<&str> {
    let trimmed = raw.trim();
    if !(trimmed.starts_with("```") && trimmed.ends_with("```")) {
        return None;
    }

    let inner = trimmed
        .trim_start_matches("```json")
        .trim_start_matches("```JSON")
        .trim_start_matches("```")
        .trim_end_matches("```")
        .trim();
    (!inner.is_empty()).then_some(inner)
}

fn extract_json_object_candidate(raw: &str) -> Option<&str> {
    let start = raw.find('{')?;
    let end = raw.rfind('}')?;
    (start < end).then_some(raw.get(start..=end)?)
}

fn summarize_inline_text(text: &str, max_chars: usize) -> String {
    let compact = text.split_whitespace().collect::<Vec<_>>().join(" ");
    let compact = compact.trim();
    if compact.chars().count() <= max_chars {
        return compact.to_string();
    }

    compact
        .chars()
        .take(max_chars.saturating_sub(1))
        .collect::<String>()
        + "…"
}

fn normalize_shell_arg(arg: String) -> String {
    arg.lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .collect::<Vec<_>>()
        .join("; ")
}

fn required_text_field(value: Option<String>, field_name: &str) -> Result<String, String> {
    value
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .ok_or_else(|| format!("missing required field `{field_name}`"))
}

impl PlannerEnvelope {
    fn into_planned_turn(self) -> Result<PlannedTurnDecision, String> {
        match self.decision {
            PlannerDecisionKind::Reply => {
                let assistant_reply = required_text_field(self.assistant_reply, "assistant_reply")?;
                let quick_reply = self
                    .quick_reply
                    .map(|value| value.trim().to_string())
                    .filter(|value| !value.is_empty())
                    .unwrap_or_else(|| summarize_inline_text(&assistant_reply, 120));
                Ok(PlannedTurnDecision::Reply {
                    assistant_reply,
                    quick_reply,
                })
            }
            PlannerDecisionKind::Clarify => {
                let assistant_reply = required_text_field(self.assistant_reply, "assistant_reply")?;
                let quick_reply = self
                    .quick_reply
                    .map(|value| value.trim().to_string())
                    .filter(|value| !value.is_empty())
                    .unwrap_or_else(|| summarize_inline_text(&assistant_reply, 120));
                Ok(PlannedTurnDecision::Clarify {
                    assistant_reply,
                    quick_reply,
                })
            }
            PlannerDecisionKind::ControlledTerminal => {
                let terminal_plan = self
                    .terminal_plan
                    .ok_or_else(|| "missing required field `terminal_plan`".to_string())?;
                Ok(PlannedTurnDecision::ControlledTerminal {
                    request: terminal_plan.into_controlled_terminal_request()?,
                })
            }
        }
    }
}

impl PlannerTerminalPlan {
    fn into_controlled_terminal_request(self) -> Result<ControlledTerminalRequest, String> {
        let goal = self.goal.trim().to_string();
        if goal.is_empty() {
            return Err("terminal_plan.goal must not be empty".to_string());
        }

        let plan_summary = self.plan_summary.trim().to_string();
        if plan_summary.is_empty() {
            return Err("terminal_plan.plan_summary must not be empty".to_string());
        }

        if self.steps.is_empty() {
            return Err("terminal_plan.steps must contain at least one step".to_string());
        }

        let steps = self
            .steps
            .into_iter()
            .map(PlannerTerminalStep::into_controlled_terminal_step)
            .collect::<Result<Vec<_>, _>>()?;

        let kind = match self.kind {
            PlannerTerminalKind::DockerContainers => ControlledTerminalPlanKind::DockerContainers {
                only_startable: self.only_startable,
            },
            PlannerTerminalKind::GitStatus => ControlledTerminalPlanKind::GitStatus,
            PlannerTerminalKind::DirectoryListing => ControlledTerminalPlanKind::DirectoryListing,
            PlannerTerminalKind::HostDiagnostics => ControlledTerminalPlanKind::HostDiagnostics {
                include_current_time: self.include_current_time,
            },
            PlannerTerminalKind::GenericShell => ControlledTerminalPlanKind::GenericShell {
                subject: self
                    .subject
                    .map(|value| value.trim().to_string())
                    .filter(|value| !value.is_empty())
                    .unwrap_or_else(|| summarize_inline_text(&plan_summary, 80)),
            },
        };

        Ok(ControlledTerminalRequest {
            goal,
            plan_summary,
            kind,
            steps,
        })
    }
}

impl PlannerTerminalStep {
    fn into_controlled_terminal_step(self) -> Result<ControlledTerminalStep, String> {
        let title = self.title.trim().to_string();
        if title.is_empty() {
            return Err("terminal_plan.steps[].title must not be empty".to_string());
        }

        let command = self.command.trim().to_string();
        if command.is_empty() {
            return Err("terminal_plan.steps[].command must not be empty".to_string());
        }
        if command.split_whitespace().count() != 1 {
            return Err(format!(
                "terminal_plan.steps[].command must be a single token, got `{command}`"
            ));
        }

        Ok(ControlledTerminalStep {
            title,
            command,
            args: self
                .args
                .into_iter()
                .map(normalize_shell_arg)
                .filter(|value| !value.is_empty())
                .collect(),
            cwd: self
                .cwd
                .map(|value| value.trim().to_string())
                .filter(|value| !value.is_empty()),
            condition: match self.condition {
                PlannerTerminalStepCondition::Always => ControlledTerminalStepCondition::Always,
                PlannerTerminalStepCondition::IfPreviousPythonInspectionEmpty => {
                    ControlledTerminalStepCondition::IfPreviousPythonInspectionEmpty
                }
            },
        })
    }
}

fn sorted_provider_choices(config: &ChatRuntimeConfig) -> Vec<String> {
    let mut providers = config.providers.keys().cloned().collect::<Vec<_>>();
    providers.sort();
    providers
}

fn sorted_route_class_settings(routing: &RoutingConfig) -> Vec<RouteClassSetting> {
    let mut route_classes = routing
        .route_classes
        .iter()
        .map(|(name, route_class)| RouteClassSetting {
            name: name.clone(),
            provider: route_class.provider.clone(),
            model: route_class.model.clone(),
            reasoning_effort: route_class.reasoning_effort.clone(),
            fallback_model: route_class.fallback_model.clone(),
        })
        .collect::<Vec<_>>();
    route_classes.sort_by(|left, right| left.name.cmp(&right.name));
    route_classes
}

fn sorted_profile_route_settings(routing: &RoutingConfig) -> Vec<ProfileRouteSetting> {
    let mut profiles = routing
        .profiles
        .iter()
        .map(|(name, profile)| ProfileRouteSetting {
            name: name.clone(),
            default_route_class: profile.default_route_class.clone(),
        })
        .collect::<Vec<_>>();
    profiles.sort_by(|left, right| left.name.cmp(&right.name));
    profiles
}

fn validate_chat_routing_settings(
    settings: &ChatRoutingSettings,
    chat_runtime: &ChatRuntimeConfig,
) -> Result<(), String> {
    if settings.route_classes.is_empty() {
        return Err("at least one route class is required".to_string());
    }

    let provider_choices = sorted_provider_choices(chat_runtime);
    let mut route_class_names = Vec::new();
    for route_class in &settings.route_classes {
        if route_class.name.trim().is_empty() {
            return Err("route class names cannot be empty".to_string());
        }
        if route_class.model.trim().is_empty() {
            return Err(format!(
                "route class `{}` requires a model",
                route_class.name
            ));
        }
        if route_class.fallback_model.trim().is_empty() {
            return Err(format!(
                "route class `{}` requires a fallback model",
                route_class.name
            ));
        }
        if !provider_choices
            .iter()
            .any(|provider| provider == &route_class.provider)
        {
            return Err(format!(
                "route class `{}` references unknown provider `{}`",
                route_class.name, route_class.provider
            ));
        }
        route_class_names.push(route_class.name.clone());
    }

    route_class_names.sort();
    route_class_names.dedup();
    if route_class_names.len() != settings.route_classes.len() {
        return Err("route class names must be unique".to_string());
    }

    if !route_class_names
        .iter()
        .any(|route_class_name| route_class_name == &settings.default_route_class)
    {
        return Err("default route class must reference a defined route class".to_string());
    }

    let mut profile_names = Vec::new();
    for profile in &settings.profiles {
        if profile.name.trim().is_empty() {
            return Err("profile names cannot be empty".to_string());
        }
        if !route_class_names
            .iter()
            .any(|route_class_name| route_class_name == &profile.default_route_class)
        {
            return Err(format!(
                "profile `{}` references unknown route class `{}`",
                profile.name, profile.default_route_class
            ));
        }
        profile_names.push(profile.name.clone());
    }
    profile_names.sort();
    profile_names.dedup();
    if profile_names.len() != settings.profiles.len() {
        return Err("profile names must be unique".to_string());
    }

    Ok(())
}

fn secrets_file_path(config_dir: &Path) -> PathBuf {
    config_dir.join(CHAT_RUNTIME_SECRETS_FILE_NAME)
}

fn load_chat_runtime_secrets(
    config_dir: Option<&Path>,
) -> Result<ChatRuntimeSecretsConfig, String> {
    let candidate_path = if let Ok(env_override) = env::var("GEEAGENT_CONFIG_DIR") {
        let path = PathBuf::from(env_override).join(CHAT_RUNTIME_SECRETS_FILE_NAME);
        if path.exists() {
            Some(path)
        } else {
            None
        }
    } else {
        None
    }
    .or_else(|| {
        config_dir
            .map(secrets_file_path)
            .filter(|path| path.exists())
    });

    let Some(path) = candidate_path else {
        return Ok(ChatRuntimeSecretsConfig::default());
    };

    let raw = fs::read_to_string(path).map_err(|error| error.to_string())?;
    toml::from_str(&raw).map_err(|error| error.to_string())
}

pub fn persist_chat_runtime_setup(
    config_dir: &Path,
    setup: &ChatRuntimeSetupInput,
) -> Result<(), String> {
    fs::create_dir_all(config_dir).map_err(|error| error.to_string())?;
    let path = secrets_file_path(config_dir);
    let mut secrets = if path.exists() {
        let raw = fs::read_to_string(&path).map_err(|error| error.to_string())?;
        toml::from_str::<ChatRuntimeSecretsConfig>(&raw).map_err(|error| error.to_string())?
    } else {
        ChatRuntimeSecretsConfig::default()
    };

    merge_provider_api_key(&mut secrets, "openai", setup.openai_api_key.as_deref());
    merge_provider_api_key(&mut secrets, "xenodia", setup.xenodia_api_key.as_deref());

    let raw = toml::to_string_pretty(&secrets).map_err(|error| error.to_string())?;
    fs::write(path, raw).map_err(|error| error.to_string())
}

pub fn clear_chat_runtime_provider(config_dir: &Path, provider_name: &str) -> Result<(), String> {
    fs::create_dir_all(config_dir).map_err(|error| error.to_string())?;
    let path = secrets_file_path(config_dir);
    let mut secrets = if path.exists() {
        let raw = fs::read_to_string(&path).map_err(|error| error.to_string())?;
        toml::from_str::<ChatRuntimeSecretsConfig>(&raw).map_err(|error| error.to_string())?
    } else {
        ChatRuntimeSecretsConfig::default()
    };

    if let Some(entry) = secrets.providers.get_mut(provider_name) {
        entry.api_key = None;
        let clear_model_override = entry
            .model_override
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .is_none();
        if clear_model_override {
            secrets.providers.remove(provider_name);
        }
    }

    let raw = toml::to_string_pretty(&secrets).map_err(|error| error.to_string())?;
    fs::write(path, raw).map_err(|error| error.to_string())
}

fn merge_provider_api_key(
    secrets: &mut ChatRuntimeSecretsConfig,
    provider_name: &str,
    next_value: Option<&str>,
) {
    let Some(next_value) = next_value.map(str::trim).filter(|value| !value.is_empty()) else {
        return;
    };

    let entry = secrets
        .providers
        .entry(provider_name.to_string())
        .or_default();
    entry.api_key = Some(next_value.to_string());
}

#[cfg(test)]
mod tests {
    use std::{
        collections::HashMap,
        fs,
        path::PathBuf,
        time::{Duration, SystemTime, UNIX_EPOCH},
    };

    use super::{
        clear_chat_runtime_provider, load_chat_routing_settings, parse_turn_planner_response,
        persist_chat_routing_settings, persist_chat_runtime_setup, system_prompt_for_active_agent,
        ChatRuntime, ChatRuntimeConfig, ChatRuntimeSecretsConfig, ChatRuntimeSetupInput,
        PlannedTurnDecision, RuntimeFacts, MAIN_PROFILE_NAME, WORKSPACE_SYSTEM_PROMPT,
    };
    use agent_kernel::AgentProfile;
    use model_router::RouteClass;

    fn sample_runtime_config() -> ChatRuntimeConfig {
        toml::from_str(
            r#"
version = 1
request_timeout_seconds = 30
temperature = 0.3
max_completion_tokens = 600
fallback_provider_order = ["xenodia", "openai"]

[providers.openai]
enabled = true
api_key_env = "OPENAI_API_KEY"
chat_completions_url = "https://api.openai.com/v1/chat/completions"
model_discovery_url = "https://api.openai.com/v1/models"
model_override_env = "GEEAGENT_OPENAI_MODEL"
default_model = "gpt-5"

[providers.xenodia]
enabled = true
api_key_env = "XENODIA_API_KEY"
chat_completions_url = "https://api.xenodia.xyz/v1/chat/completions"
model_discovery_url = "https://api.xenodia.xyz/v1/models"
model_override_env = "GEEAGENT_XENODIA_MODEL"
default_model = "gpt-5.4"
"#,
        )
        .expect("runtime config should parse")
    }

    fn sample_runtime() -> ChatRuntime {
        let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
        let routing =
            model_router::RoutingConfig::from_path(repo_root.join("config/model-routing.toml"))
                .expect("routing config should parse");
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(10))
            .build()
            .expect("client should build");

        ChatRuntime {
            client,
            routing,
            config: sample_runtime_config(),
            secrets: ChatRuntimeSecretsConfig::default(),
        }
    }

    fn unique_temp_config_dir() -> PathBuf {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock should move forward")
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "geeagent-chat-runtime-test-{}-{}",
            std::process::id(),
            stamp
        ));
        fs::create_dir_all(&path).expect("temp config dir should create");
        path
    }

    #[test]
    fn resolves_primary_provider_when_key_is_present() {
        let runtime = sample_runtime();
        let route_class = RouteClass {
            provider: "openai".to_string(),
            model: "gpt-5".to_string(),
            reasoning_effort: "medium".to_string(),
            fallback_model: "gpt-4.1-mini".to_string(),
        };
        let environment = HashMap::from([("OPENAI_API_KEY".to_string(), "openai-key".to_string())]);

        let provider = runtime
            .resolve_provider_with_environment(&route_class, &environment)
            .expect("provider should resolve");

        assert_eq!(provider.name, "openai");
        assert_eq!(provider.model, "gpt-5");
    }

    #[test]
    fn falls_back_to_xenodia_when_primary_provider_has_no_key() {
        let runtime = sample_runtime();
        let route_class = RouteClass {
            provider: "openai".to_string(),
            model: "gpt-5".to_string(),
            reasoning_effort: "medium".to_string(),
            fallback_model: "gpt-4.1-mini".to_string(),
        };
        let environment =
            HashMap::from([("XENODIA_API_KEY".to_string(), "xenodia-key".to_string())]);

        let provider = runtime
            .resolve_provider_with_environment(&route_class, &environment)
            .expect("provider should resolve");

        assert_eq!(provider.name, "xenodia");
        assert_eq!(provider.model, "gpt-5.4");
    }

    #[test]
    fn returns_a_clear_error_when_no_provider_key_is_available() {
        let runtime = sample_runtime();
        let route_class = RouteClass {
            provider: "openai".to_string(),
            model: "gpt-5".to_string(),
            reasoning_effort: "medium".to_string(),
            fallback_model: "gpt-4.1-mini".to_string(),
        };
        let environment = HashMap::new();

        let error = runtime
            .resolve_provider_with_environment(&route_class, &environment)
            .expect_err("missing keys should fail");

        assert!(error.contains("OPENAI_API_KEY"));
        assert!(error.contains("XENODIA_API_KEY"));
    }

    #[test]
    fn loads_provider_keys_from_saved_chat_setup_file() {
        let config_dir = unique_temp_config_dir();
        fs::write(
            config_dir.join("model-routing.toml"),
            r#"
version = 1
default_route_class = "balanced"
allow_user_overrides = true

[continuation]
min_confidence_to_resume = 0.85
fallback_action = "new_conversation"

[route_classes.balanced]
provider = "xenodia"
model = "gpt-5.4"
reasoning_effort = "medium"
fallback_model = "gpt-5.4-mini"

[profiles.main]
default_route_class = "balanced"

[task_types.conversation]
default_profile = "main"
default_route_class = "balanced"
"#,
        )
        .expect("routing file should write");
        fs::write(
            config_dir.join("chat-runtime-secrets.toml"),
            r#"
version = 1

[providers.xenodia]
api_key = "xenodia-local-key"
"#,
        )
        .expect("secrets file should write");

        let runtime = ChatRuntime::from_config_dir(Some(config_dir.as_path()))
            .expect("runtime should build from saved config");
        let readiness = runtime.readiness();

        assert_eq!(readiness.status, "live");
        assert_eq!(readiness.active_provider.as_deref(), Some("xenodia"));

        let _ = fs::remove_dir_all(config_dir);
    }

    #[test]
    fn persists_chat_setup_without_exposing_raw_keys_in_summary() {
        let config_dir = unique_temp_config_dir();

        persist_chat_runtime_setup(
            config_dir.as_path(),
            &ChatRuntimeSetupInput {
                openai_api_key: Some("openai-local-key".to_string()),
                xenodia_api_key: Some("".to_string()),
            },
        )
        .expect("setup should persist");

        let runtime = ChatRuntime::from_config_dir(Some(config_dir.as_path()))
            .expect("runtime should reload from saved setup");
        let route_class = runtime
            .resolve_route_class(MAIN_PROFILE_NAME)
            .expect("main profile route should resolve");
        let provider = runtime
            .resolve_provider_with_environment(&route_class, &HashMap::new())
            .expect("saved OpenAI key should resolve without host env leakage");
        let raw = fs::read_to_string(config_dir.join("chat-runtime-secrets.toml"))
            .expect("saved secrets file should exist");

        assert_eq!(provider.name, "openai");
        assert!(raw.contains("openai-local-key"));
        assert!(!runtime.readiness().detail.contains("openai-local-key"));

        let _ = fs::remove_dir_all(config_dir);
    }

    #[test]
    fn clearing_a_saved_provider_key_removes_it_from_local_secrets() {
        let config_dir = unique_temp_config_dir();

        persist_chat_runtime_setup(
            config_dir.as_path(),
            &ChatRuntimeSetupInput {
                openai_api_key: Some("openai-local-key".to_string()),
                xenodia_api_key: Some("xenodia-local-key".to_string()),
            },
        )
        .expect("setup should persist");

        clear_chat_runtime_provider(config_dir.as_path(), "xenodia")
            .expect("provider key should clear");

        let raw = fs::read_to_string(config_dir.join("chat-runtime-secrets.toml"))
            .expect("saved secrets file should exist");

        assert!(raw.contains("openai-local-key"));
        assert!(!raw.contains("xenodia-local-key"));

        let _ = fs::remove_dir_all(config_dir);
    }

    #[test]
    fn loads_default_chat_routing_settings() {
        let config_dir = unique_temp_config_dir();

        let settings = load_chat_routing_settings(Some(config_dir.as_path()))
            .expect("routing settings should load");

        assert_eq!(settings.default_route_class, "balanced");
        assert!(settings
            .profiles
            .iter()
            .any(|profile| profile.name == "main" && profile.default_route_class == "balanced"));
        assert!(settings
            .provider_choices
            .iter()
            .any(|provider| provider == "xenodia"));

        let _ = fs::remove_dir_all(config_dir);
    }

    #[test]
    fn active_agent_system_prompt_includes_profile_context() {
        let profile = AgentProfile {
            id: "nyko".to_string(),
            name: "Nyko".to_string(),
            tagline: "Playful follow-through".to_string(),
            personality_prompt: "Stay playful but finish the task.".to_string(),
            appearance: agent_kernel::AgentAppearance::Abstract,
            skills: Vec::new(),
            allowed_tool_ids: None,
            source: agent_kernel::ProfileSource::UserCreated,
            version: "2".to_string(),
        };
        let runtime_facts = RuntimeFacts {
            local_time: "2026-04-22 15:30:00 SGT".to_string(),
            time_zone: "SGT".to_string(),
            cwd: "/tmp/geeagent".to_string(),
            surface: "desktop_workspace_chat".to_string(),
        };

        let prompt =
            system_prompt_for_active_agent(WORKSPACE_SYSTEM_PROMPT, &profile, &runtime_facts);

        assert!(prompt.contains("[RUNTIME_FACTS]"));
        assert!(prompt.contains("local_time = \"2026-04-22 15:30:00 SGT\""));
        assert!(prompt.contains("surface = \"desktop_workspace_chat\""));
        assert!(prompt.contains("[ACTIVE_AGENT]"));
        assert!(prompt.contains("name = \"Nyko\""));
        assert!(prompt.contains("Playful follow-through"));
        assert!(prompt.contains("Stay playful but finish the task."));
    }

    #[test]
    fn persists_chat_routing_settings_and_keeps_them_reloadable() {
        let config_dir = unique_temp_config_dir();
        let mut settings = load_chat_routing_settings(Some(config_dir.as_path()))
            .expect("routing settings should load");

        let balanced = settings
            .route_classes
            .iter_mut()
            .find(|route_class| route_class.name == "balanced")
            .expect("balanced route class should exist");
        balanced.provider = "xenodia".to_string();
        balanced.model = "gpt-5.4".to_string();
        balanced.fallback_model = "gpt-5.4-mini".to_string();
        let worker = settings
            .profiles
            .iter_mut()
            .find(|profile| profile.name == "worker")
            .expect("worker profile should exist");
        worker.default_route_class = "cheap".to_string();

        persist_chat_routing_settings(config_dir.as_path(), &settings)
            .expect("routing settings should persist");

        let reloaded = ChatRuntime::from_config_dir(Some(config_dir.as_path()))
            .expect("chat runtime should reload with saved routing");

        assert_eq!(
            reloaded
                .routing
                .route_classes
                .get("balanced")
                .map(|route_class| route_class.provider.as_str()),
            Some("xenodia")
        );
        assert_eq!(
            reloaded
                .routing
                .profiles
                .get("worker")
                .map(|profile| profile.default_route_class.as_str()),
            Some("cheap")
        );

        let _ = fs::remove_dir_all(config_dir);
    }

    #[test]
    fn planner_response_parses_controlled_terminal_json_inside_code_fence() {
        let raw = r#"```json
{
  "decision": "controlled_terminal",
  "terminal_plan": {
    "goal": "检查 Cargo.toml 是否存在并读取 package 名",
    "plan_summary": "先确认 Cargo.toml 存在，再读取并提取 package 名",
    "kind": "generic_shell",
    "subject": "Cargo manifest inspection",
    "steps": [
      {
        "title": "Read manifest",
        "command": "cat",
        "args": ["Cargo.toml"],
        "condition": "always"
      },
      {
        "title": "Extract package name",
        "command": "grep",
        "args": ["^name", "Cargo.toml"],
        "condition": "always"
      }
    ]
  }
}
```"#;

        let planned = parse_turn_planner_response(raw).expect("planner response should parse");

        match planned {
            PlannedTurnDecision::ControlledTerminal { request } => {
                assert_eq!(request.steps.len(), 2);
                assert!(matches!(
                    request.kind,
                    execution_runtime::ControlledTerminalPlanKind::GenericShell { .. }
                ));
                assert_eq!(request.steps[0].command, "cat");
                assert_eq!(request.steps[1].command, "grep");
            }
            other => panic!("expected controlled terminal plan, got {other:?}"),
        }
    }
}
