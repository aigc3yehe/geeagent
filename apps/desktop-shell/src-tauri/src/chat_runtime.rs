use std::{
    collections::HashMap,
    env, fs,
    path::{Path, PathBuf},
};

use execution_runtime::capture_host_runtime_facts;
use model_router::{RouteClass, RoutingConfig};
use serde::{Deserialize, Serialize};

const MAIN_PROFILE_NAME: &str = "main";
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
    routing: RoutingConfig,
    config: ChatRuntimeConfig,
    secrets: ChatRuntimeSecretsConfig,
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

        Ok(Self {
            routing,
            config,
            secrets,
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

#[cfg(test)]
mod tests {
    use std::{
        collections::HashMap,
        fs,
        path::PathBuf,
        time::{SystemTime, UNIX_EPOCH},
    };

    use super::{
        load_chat_routing_settings, persist_chat_routing_settings, ChatRuntime,
        ChatRuntimeConfig, ChatRuntimeSecretsConfig, DEFAULT_MODEL_ROUTING_TOML,
    };
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
        let routing = model_router::RoutingConfig::from_toml_str(DEFAULT_MODEL_ROUTING_TOML)
            .expect("routing config should parse");

        ChatRuntime {
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
}
