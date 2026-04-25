mod chat_runtime;

use agent_kernel::{
    validate_pack, AgentAppearance, AgentProfile, AgentProfileRegistry, PackError, ProfileSource,
    ValidatedAgentPack,
};
use automation_engine::AutomationDefinition;
use chat_runtime::{
    load_chat_routing_settings, persist_chat_routing_settings, ChatReadiness, ChatRoutingSettings,
    ChatRuntime, RuntimeFacts, WorkspaceChatMessage,
};
use chrono::Utc;
use execution_runtime::{
    summarize_prompt as summarize_runtime_prompt, ControlledTerminalPlanKind,
    ControlledTerminalRequest, ControlledTerminalStep, ExecutionAutomationDraft, ExecutionOutcome,
    ExecutionRequestMeta,
};
use experience_registry::{
    AgentSkinManifest, ExperienceRegistry, InstallState, InstalledAppManifest, ModuleDisplayMode,
};
use module_gateway::{
    ArtifactEnvelope, ModuleRun, ModuleRunStage, ModuleRunStatus, Recoverability,
};
#[cfg(test)]
use runtime_kernel::{
    classify_first_party_execution, FirstPartyDetectionContext, FirstPartyRoutingDecision,
    KernelRun, KernelRunStatus,
};
use runtime_kernel::{
    invoke_tool, AgentSessionRuntime, KernelSession, KernelSessionStatus, KernelSurfaceKind,
    QueuedRuntimeMessage, ToolOutcome, ToolRequest,
};
use serde::{Deserialize, Serialize};
use std::{
    collections::{hash_map::DefaultHasher, HashMap, HashSet},
    fs,
    hash::{Hash, Hasher},
    io::{BufRead, BufReader, Write},
    path::{Path, PathBuf},
    process::{Child, ChildStderr, ChildStdin, ChildStdout, Command, Stdio},
    sync::{Mutex, OnceLock},
};
use task_engine::{
    ArtifactRef, ExecutionMode, ExecutionSession, ExecutionSurface, ImportanceLevel,
    SessionPersistencePolicy, TaskRun, TaskStage, TaskStatus, TaskType, ToolInvocation,
    ToolInvocationStatus, TranscriptEvent, TranscriptEventPayload,
};
use workspace_runtime::{WorkspaceRuntime, WorkspaceSnapshot};
const ITERATIVE_TURN_MAX_STEPS: usize = 8;
const PERSONA_SKILL_PROMPT_CHAR_LIMIT: usize = 20_000;

#[derive(Clone, Debug, Deserialize, Serialize)]
struct RuntimeTaskRecord {
    task_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    conversation_id: Option<String>,
    title: String,
    summary: String,
    current_stage: String,
    status: String,
    importance_level: String,
    progress_percent: u8,
    artifact_count: u32,
    approval_request_id: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
struct RuntimeApprovalParameter {
    label: String,
    value: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
struct RuntimeApprovalRecord {
    approval_request_id: String,
    task_id: String,
    action_title: String,
    reason: String,
    risk_tags: Vec<String>,
    review_required: bool,
    status: String,
    parameters: Vec<RuntimeApprovalParameter>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    machine_context: Option<RuntimeApprovalMachineContext>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
enum RuntimeApprovalMachineContext {
    ControlledTerminal {
        request: ControlledTerminalRequest,
    },
    SdkBridgeTerminal {
        source: RuntimeRequestSource,
        surface: ExecutionSurface,
        user_prompt: String,
        #[serde(default)]
        bridge_session_id: String,
        #[serde(default)]
        bridge_request_id: String,
        scope: TerminalAccessScope,
        command: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        cwd: Option<String>,
    },
}

#[derive(Clone, Debug, Deserialize, Serialize)]
struct RuntimeConversationMessageRecord {
    message_id: String,
    role: String,
    content: String,
    timestamp: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
struct RuntimeConversationRecord {
    conversation_id: String,
    title: String,
    status: String,
    messages: Vec<RuntimeConversationMessageRecord>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
struct RuntimeConversationSummaryRecord {
    conversation_id: String,
    title: String,
    status: String,
    last_message_preview: String,
    last_timestamp: String,
    is_active: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
struct RuntimeWorkspaceFocus {
    mode: String,
    task_id: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
struct RuntimeChatRuntimeRecord {
    status: String,
    active_provider: Option<String>,
    detail: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum RuntimeInteractionSurface {
    DesktopLive,
    PreviewReadonly,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
struct RuntimeInteractionCapabilitiesRecord {
    surface: RuntimeInteractionSurface,
    can_send_messages: bool,
    can_use_quick_input: bool,
    can_mutate_runtime: bool,
    can_run_first_party_actions: bool,
    read_only_reason: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum RuntimeRequestSource {
    WorkspaceChat,
    QuickInput,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum RuntimeRequestOutcomeKind {
    ChatReply,
    TaskHandoff,
    FirstPartyAction,
    ClarifyNeeded,
    NeedsSetup,
    Error,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
struct RuntimeRequestOutcomeRecord {
    source: RuntimeRequestSource,
    kind: RuntimeRequestOutcomeKind,
    detail: String,
    task_id: Option<String>,
    module_run_id: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
struct RuntimeRunStateRecord {
    conversation_id: Option<String>,
    status: String,
    stop_reason: String,
    detail: String,
    resumable: bool,
    task_id: Option<String>,
    module_run_id: Option<String>,
}

#[cfg(test)]
#[derive(Clone, Debug)]
struct RunStatusFollowUpDecision {
    assistant_reply: String,
    run_state: RuntimeRunStateRecord,
}

#[cfg(test)]
#[derive(Clone, Debug)]
struct GroundedRuntimeFactReplyDecision {
    quick_reply: String,
    run_state: RuntimeRunStateRecord,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct TurnReplayCursor {
    session_id: String,
    user_message_id: String,
    step_count: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum TurnMode {
    QuickPrompt,
    WorkspaceMessage,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct TurnRoute {
    mode: TurnMode,
    source: RuntimeRequestSource,
    surface: ExecutionSurface,
}

#[derive(Clone, Debug)]
struct PreparedTurnContext {
    active_agent_profile: AgentProfile,
    workspace_messages: Vec<WorkspaceChatMessage>,
    should_reuse_active_conversation: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum TerminalAccessDecision {
    Allow,
    Deny,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(tag = "kind", rename_all = "snake_case")]
enum TerminalAccessScope {
    ControlledTerminalPlan {
        signature: String,
    },
    SdkBridgeBash {
        command: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        cwd: Option<String>,
    },
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
struct TerminalAccessRule {
    scope: TerminalAccessScope,
    decision: TerminalAccessDecision,
    label: String,
    updated_at: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
struct RuntimeTerminalAccessRuleRecord {
    rule_id: String,
    decision: String,
    kind: String,
    label: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    command: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    cwd: Option<String>,
    updated_at: String,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
struct TerminalAccessPermissionsFile {
    #[serde(default)]
    rules: Vec<TerminalAccessRule>,
}

#[derive(Clone, Debug)]
struct ClaudeSdkPendingTerminalApproval {
    bridge_session_id: String,
    bridge_request_id: String,
    scope: TerminalAccessScope,
    command: String,
    cwd: Option<String>,
    input_summary: Option<String>,
}

#[derive(Debug, Default)]
struct ClaudeSdkBridgeTurnResult {
    assistant_chunks: Vec<String>,
    final_result: Option<String>,
    tool_events: Vec<ClaudeSdkBridgeObservedToolEvent>,
    auto_approved_tools: usize,
    failed_reason: Option<String>,
    pending_terminal_approval: Option<ClaudeSdkPendingTerminalApproval>,
    terminal_access_denied_reason: Option<String>,
}

struct AgentRuntimeBridgeProcess {
    child: Child,
    stdin: ChildStdin,
    reader: BufReader<ChildStdout>,
    _stderr: ChildStderr,
}

impl Drop for AgentRuntimeBridgeProcess {
    fn drop(&mut self) {
        let _ = write_agent_runtime_bridge_command(
            &mut self.stdin,
            serde_json::json!({ "type": "bridge.shutdown" }),
        );
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

#[derive(Default)]
struct AgentRuntimeBridgeManager {
    sessions: HashMap<String, AgentRuntimeBridgeProcess>,
}

static AGENT_RUNTIME_BRIDGE_MANAGER: OnceLock<Mutex<AgentRuntimeBridgeManager>> = OnceLock::new();

impl ClaudeSdkBridgeTurnResult {
    fn tool_step_count(&self) -> usize {
        self.tool_events
            .iter()
            .filter(|event| matches!(event, ClaudeSdkBridgeObservedToolEvent::Invocation { .. }))
            .count()
    }
}

#[derive(Debug)]
enum ClaudeSdkBridgeObservedToolEvent {
    Invocation {
        invocation_id: String,
        tool_name: String,
        input_summary: Option<String>,
    },
    Result {
        invocation_id: String,
        status: ToolInvocationStatus,
        summary: Option<String>,
        error: Option<String>,
    },
}

#[derive(Clone, Debug)]
struct ControlledTerminalObservation {
    step: ControlledTerminalStep,
    outcome: ToolOutcome,
}

fn desktop_interaction_capabilities() -> RuntimeInteractionCapabilitiesRecord {
    RuntimeInteractionCapabilitiesRecord {
        surface: RuntimeInteractionSurface::DesktopLive,
        can_send_messages: true,
        can_use_quick_input: true,
        can_mutate_runtime: true,
        can_run_first_party_actions: true,
        read_only_reason: None,
    }
}

fn default_agent_profile_registry() -> AgentProfileRegistry {
    AgentProfileRegistry::bundled_defaults().expect("bundled gee profile should be valid")
}

fn default_runtime_agent_profile() -> AgentProfile {
    default_agent_profile_registry()
        .active()
        .cloned()
        .expect("bundled agent profile registry should contain gee")
}

fn resolved_active_agent_profile(store: &RuntimeStore) -> AgentProfile {
    store
        .active_agent_profile()
        .cloned()
        .unwrap_or_else(default_runtime_agent_profile)
}

fn agent_display_name(profile: &AgentProfile) -> &str {
    let trimmed = profile.name.trim();
    if trimmed.is_empty() {
        "GeeAgent"
    } else {
        trimmed
    }
}

fn active_agent_system_prompt(profile: &AgentProfile) -> String {
    let mut sections = vec![profile.personality_prompt.trim().to_string()];
    let skill_sections = profile
        .skills
        .iter()
        .filter_map(|skill| {
            let path = skill.path.as_ref()?;
            let raw = fs::read_to_string(path.join("SKILL.md")).ok()?;
            let body = truncate_persona_skill_prompt(&raw);
            if body.trim().is_empty() {
                return None;
            }
            Some(format!(
                "## {}\nPath: {}\n\n{}",
                skill.id.trim(),
                path.display(),
                body
            ))
        })
        .collect::<Vec<_>>();

    if !skill_sections.is_empty() {
        sections.push(format!(
            "[PERSONA SKILL WHITELIST]\nOnly the following persona skills are enabled. When a user request matches one of these skills, follow that skill's SKILL.md instructions. Do not assume access to unlisted local skills.\n\n{}",
            skill_sections.join("\n\n")
        ));
    }

    sections
        .into_iter()
        .map(|section| section.trim().to_string())
        .filter(|section| !section.is_empty())
        .collect::<Vec<_>>()
        .join("\n\n")
}

fn truncate_persona_skill_prompt(raw: &str) -> String {
    let trimmed = raw.trim();
    if trimmed.chars().count() <= PERSONA_SKILL_PROMPT_CHAR_LIMIT {
        return trimmed.to_string();
    }

    let mut truncated = trimmed
        .chars()
        .take(PERSONA_SKILL_PROMPT_CHAR_LIMIT)
        .collect::<String>();
    truncated.push_str("\n\n[Skill content truncated by GeeAgent to fit the active turn context.]");
    truncated
}

fn runtime_facts_for_surface(surface: ExecutionSurface) -> RuntimeFacts {
    let surface_label = match surface {
        ExecutionSurface::DesktopWorkspaceChat => "desktop_workspace_chat",
        ExecutionSurface::DesktopQuickInput => "desktop_quick_input",
        ExecutionSurface::CliWorkspaceChat => "cli_workspace_chat",
        ExecutionSurface::CliQuickInput => "cli_quick_input",
        ExecutionSurface::Automation => "automation",
        ExecutionSurface::BackgroundAgent => "background_agent",
    };

    RuntimeFacts::capture(surface_label)
}

fn turn_setup_summary(surface: ExecutionSurface) -> String {
    let facts = runtime_facts_for_surface(surface);
    format!(
        "Turn setup complete. GeeAgent grounded local time {}, time zone {}, cwd {}, and the active {} surface.",
        summarize_prompt(&facts.local_time, 40),
        summarize_prompt(&facts.time_zone, 32),
        summarize_prompt(&facts.cwd, 64),
        summarize_prompt(&facts.surface, 32)
    )
}

fn turn_step_summary(step_index: usize, detail: &str) -> String {
    format!(
        "Step {step_index}/{ITERATIVE_TURN_MAX_STEPS}: {}",
        summarize_prompt(detail, 120)
    )
}

fn turn_finalize_summary(step_count: usize, reason: &str) -> String {
    format!(
        "Turn finalized after {step_count} grounded step{}: {}",
        if step_count == 1 { "" } else { "s" },
        summarize_prompt(reason, 120)
    )
}

fn personalize_execution_outcome_for_agent(
    outcome: &mut execution_runtime::ExecutionOutcome,
    profile: &AgentProfile,
) {
    let agent_name = agent_display_name(profile);
    outcome.assistant_reply = format!(
        "{agent_name} handled that locally. {}",
        outcome.assistant_reply
    );
    outcome.quick_reply = format!("{agent_name} · {}", outcome.quick_reply);
}

fn default_runtime_agent_profiles() -> Vec<AgentProfile> {
    default_agent_profile_registry().into_profiles()
}

fn default_active_agent_profile_id() -> String {
    default_runtime_agent_profile().id
}

fn hydrate_runtime_agent_profiles(
    active_agent_profile: AgentProfile,
) -> (Vec<AgentProfile>, String) {
    let active_profile_id = active_agent_profile.id.clone();
    let mut agent_profiles = default_runtime_agent_profiles();
    if let Some(existing_profile) = agent_profiles
        .iter_mut()
        .find(|profile| profile.id == active_profile_id)
    {
        *existing_profile = active_agent_profile;
    } else {
        agent_profiles.insert(0, active_agent_profile);
    }
    (agent_profiles, active_profile_id)
}

fn load_runtime_agent_profile_registry(config_dir: Option<&Path>) -> AgentProfileRegistry {
    let mut registry = default_agent_profile_registry();
    if let Some(config_dir) = config_dir {
        let user_profiles_dir = config_dir.join("agents");
        match AgentProfileRegistry::load_dir(&user_profiles_dir) {
            Ok(user_registry) => {
                if let Err(error) = registry.merge(user_registry) {
                    log::warn!("failed to merge agent profiles from disk: {error}");
                }
            }
            Err(error) => {
                log::warn!("failed to load agent profiles from disk: {error}");
            }
        }
    }

    registry
}

#[derive(Clone, Debug, Deserialize, Serialize)]
struct RuntimeModuleRunRecord {
    module_run: ModuleRun,
    recoverability: Option<Recoverability>,
}

const CONTEXT_WINDOW_TOKENS: usize = 256_000;
const CONTEXT_AUTO_SUMMARY_TRIGGER_TOKENS: usize = CONTEXT_WINDOW_TOKENS * 95 / 100;
const CONTEXT_SUMMARY_SOON_TOKENS: usize = CONTEXT_WINDOW_TOKENS * 88 / 100;
const CONTEXT_RESERVED_OUTPUT_TOKENS: usize = 8_192;
const CONTEXT_RECENT_MESSAGE_KEEP_COUNT: usize = 12;

#[derive(Clone, Debug, Deserialize, Serialize)]
struct RuntimeContextBudgetRecord {
    max_tokens: usize,
    used_tokens: usize,
    reserved_output_tokens: usize,
    usage_ratio: f64,
    estimate_source: String,
    summary_state: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    last_summarized_at: Option<String>,
    next_summary_at_ratio: f64,
    compacted_messages_count: usize,
}

fn default_runtime_context_budget_record() -> RuntimeContextBudgetRecord {
    RuntimeContextBudgetRecord {
        max_tokens: CONTEXT_WINDOW_TOKENS,
        used_tokens: 0,
        reserved_output_tokens: CONTEXT_RESERVED_OUTPUT_TOKENS,
        usage_ratio: 0.0,
        estimate_source: "estimated".to_string(),
        summary_state: "watching".to_string(),
        last_summarized_at: None,
        next_summary_at_ratio: 0.95,
        compacted_messages_count: 0,
    }
}

#[derive(Clone, Debug, Deserialize, Serialize)]
struct RuntimeSnapshot {
    quick_input_hint: String,
    quick_reply: String,
    #[serde(default = "default_runtime_context_budget_record")]
    context_budget: RuntimeContextBudgetRecord,
    #[serde(default = "default_runtime_agent_profile")]
    active_agent_profile: AgentProfile,
    #[serde(default = "default_runtime_agent_profiles")]
    agent_profiles: Vec<AgentProfile>,
    #[serde(default = "desktop_interaction_capabilities")]
    interaction_capabilities: RuntimeInteractionCapabilitiesRecord,
    #[serde(default)]
    last_request_outcome: Option<RuntimeRequestOutcomeRecord>,
    #[serde(default)]
    last_run_state: Option<RuntimeRunStateRecord>,
    chat_runtime: RuntimeChatRuntimeRecord,
    #[serde(default)]
    conversations: Vec<RuntimeConversationSummaryRecord>,
    active_conversation: RuntimeConversationRecord,
    #[serde(default)]
    automations: Vec<AutomationDefinition>,
    #[serde(default)]
    module_runs: Vec<RuntimeModuleRunRecord>,
    #[serde(default)]
    execution_sessions: Vec<ExecutionSession>,
    #[serde(default)]
    kernel_sessions: Vec<AgentSessionRuntime>,
    #[serde(default)]
    transcript_events: Vec<TranscriptEvent>,
    tasks: Vec<RuntimeTaskRecord>,
    approval_requests: Vec<RuntimeApprovalRecord>,
    workspace_focus: RuntimeWorkspaceFocus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    workspace_runtime: Option<WorkspaceSnapshot>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
struct RuntimeAgentProfileFileEntryRecord {
    title: String,
    path: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
struct RuntimeAgentProfileFileStateRecord {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    workspace_root_path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    manifest_path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    identity_prompt_path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    soul_path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    playbook_path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    tools_context_path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    memory_seed_path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    heartbeat_path: Option<String>,
    #[serde(default)]
    visual_files: Vec<RuntimeAgentProfileFileEntryRecord>,
    #[serde(default)]
    supplemental_files: Vec<RuntimeAgentProfileFileEntryRecord>,
    can_reload: bool,
    can_delete: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
struct RuntimeBridgeAgentProfileRecord {
    id: String,
    name: String,
    tagline: String,
    personality_prompt: String,
    appearance: AgentAppearance,
    #[serde(default)]
    skills: Vec<agent_kernel::SkillRef>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    allowed_tool_ids: Option<Vec<String>>,
    source: ProfileSource,
    version: String,
    file_state: RuntimeAgentProfileFileStateRecord,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
struct RuntimeBridgeSnapshot {
    quick_input_hint: String,
    quick_reply: String,
    context_budget: RuntimeContextBudgetRecord,
    active_agent_profile: RuntimeBridgeAgentProfileRecord,
    agent_profiles: Vec<RuntimeBridgeAgentProfileRecord>,
    #[serde(default = "desktop_interaction_capabilities")]
    interaction_capabilities: RuntimeInteractionCapabilitiesRecord,
    #[serde(default)]
    last_request_outcome: Option<RuntimeRequestOutcomeRecord>,
    #[serde(default)]
    last_run_state: Option<RuntimeRunStateRecord>,
    chat_runtime: RuntimeChatRuntimeRecord,
    #[serde(default)]
    conversations: Vec<RuntimeConversationSummaryRecord>,
    active_conversation: RuntimeConversationRecord,
    #[serde(default)]
    automations: Vec<AutomationDefinition>,
    #[serde(default)]
    module_runs: Vec<RuntimeModuleRunRecord>,
    #[serde(default)]
    execution_sessions: Vec<ExecutionSession>,
    #[serde(default)]
    kernel_sessions: Vec<AgentSessionRuntime>,
    #[serde(default)]
    transcript_events: Vec<TranscriptEvent>,
    tasks: Vec<RuntimeTaskRecord>,
    approval_requests: Vec<RuntimeApprovalRecord>,
    #[serde(default)]
    terminal_access_rules: Vec<RuntimeTerminalAccessRuleRecord>,
    #[serde(default)]
    security_preferences: RuntimeSecurityPreferences,
    workspace_focus: RuntimeWorkspaceFocus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    workspace_runtime: Option<WorkspaceSnapshot>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
struct RuntimeSecurityPreferences {
    #[serde(default)]
    highest_authorization_enabled: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
struct RuntimeStore {
    quick_input_hint: String,
    quick_reply: String,
    #[serde(default = "default_runtime_agent_profiles")]
    agent_profiles: Vec<AgentProfile>,
    #[serde(default = "default_active_agent_profile_id")]
    active_agent_profile_id: String,
    #[serde(default = "desktop_interaction_capabilities")]
    interaction_capabilities: RuntimeInteractionCapabilitiesRecord,
    #[serde(default)]
    last_request_outcome: Option<RuntimeRequestOutcomeRecord>,
    #[serde(default)]
    last_run_state: Option<RuntimeRunStateRecord>,
    chat_runtime: RuntimeChatRuntimeRecord,
    conversations: Vec<RuntimeConversationRecord>,
    active_conversation_id: String,
    #[serde(default)]
    automations: Vec<AutomationDefinition>,
    #[serde(default)]
    module_runs: Vec<RuntimeModuleRunRecord>,
    #[serde(default)]
    execution_sessions: Vec<ExecutionSession>,
    #[serde(default)]
    kernel_sessions: Vec<AgentSessionRuntime>,
    #[serde(default)]
    transcript_events: Vec<TranscriptEvent>,
    tasks: Vec<RuntimeTaskRecord>,
    approval_requests: Vec<RuntimeApprovalRecord>,
    workspace_focus: RuntimeWorkspaceFocus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    workspace_runtime: Option<WorkspaceSnapshot>,
}

impl RuntimeStore {
    fn from_snapshot(snapshot: RuntimeSnapshot) -> Self {
        let (agent_profiles, active_agent_profile_id) =
            hydrate_runtime_agent_profiles(snapshot.active_agent_profile);
        let active_conversation_id = snapshot.active_conversation.conversation_id.clone();
        let mut conversations = vec![snapshot.active_conversation];

        for summary in snapshot.conversations {
            if summary.conversation_id == active_conversation_id {
                continue;
            }

            conversations.push(RuntimeConversationRecord {
                conversation_id: summary.conversation_id,
                title: summary.title,
                status: summary.status,
                messages: Vec::new(),
            });
        }

        let mut store = Self {
            quick_input_hint: snapshot.quick_input_hint,
            quick_reply: snapshot.quick_reply,
            agent_profiles,
            active_agent_profile_id,
            interaction_capabilities: snapshot.interaction_capabilities,
            last_request_outcome: snapshot.last_request_outcome,
            last_run_state: snapshot.last_run_state,
            chat_runtime: snapshot.chat_runtime,
            conversations,
            active_conversation_id,
            automations: snapshot.automations,
            module_runs: snapshot.module_runs,
            execution_sessions: snapshot.execution_sessions,
            kernel_sessions: snapshot.kernel_sessions,
            transcript_events: snapshot.transcript_events,
            tasks: snapshot.tasks,
            approval_requests: snapshot.approval_requests,
            workspace_focus: snapshot.workspace_focus,
            workspace_runtime: snapshot
                .workspace_runtime
                .or_else(|| Some(bootstrap_workspace_snapshot())),
        };
        ensure_workspace_runtime_catalog(&mut store);
        store.sync_conversation_statuses();
        store.sync_execution_sessions();
        store.sync_kernel_sessions();
        store
    }

    fn snapshot(&self) -> RuntimeSnapshot {
        let active_conversation = self
            .active_conversation()
            .cloned()
            .or_else(|| self.conversations.first().cloned())
            .unwrap_or(RuntimeConversationRecord {
                conversation_id: "conv_01".to_string(),
                title: "New Conversation".to_string(),
                status: "active".to_string(),
                messages: Vec::new(),
            });

        RuntimeSnapshot {
            quick_input_hint: self.quick_input_hint.clone(),
            quick_reply: self.quick_reply.clone(),
            context_budget: context_budget_record_for_store(self),
            active_agent_profile: self
                .active_agent_profile()
                .cloned()
                .unwrap_or_else(default_runtime_agent_profile),
            agent_profiles: self.agent_profiles.clone(),
            interaction_capabilities: self.interaction_capabilities.clone(),
            last_request_outcome: self.last_request_outcome.clone(),
            last_run_state: self.last_run_state.clone(),
            chat_runtime: self.chat_runtime.clone(),
            conversations: self
                .conversations
                .iter()
                .map(|conversation| self.conversation_summary(conversation))
                .collect(),
            active_conversation,
            automations: self.automations.clone(),
            module_runs: self.module_runs.clone(),
            execution_sessions: self.execution_sessions.clone(),
            kernel_sessions: self.kernel_sessions.clone(),
            transcript_events: self.transcript_events.clone(),
            tasks: self.tasks.clone(),
            approval_requests: self.approval_requests.clone(),
            workspace_focus: self.workspace_focus.clone(),
            workspace_runtime: self
                .workspace_runtime
                .clone()
                .or_else(|| Some(bootstrap_workspace_snapshot())),
        }
    }

    fn active_conversation(&self) -> Option<&RuntimeConversationRecord> {
        self.conversations
            .iter()
            .find(|conversation| conversation.conversation_id == self.active_conversation_id)
    }

    fn active_conversation_mut(&mut self) -> Option<&mut RuntimeConversationRecord> {
        self.conversations
            .iter_mut()
            .find(|conversation| conversation.conversation_id == self.active_conversation_id)
    }

    fn active_agent_profile(&self) -> Option<&AgentProfile> {
        self.agent_profiles
            .iter()
            .find(|profile| profile.id == self.active_agent_profile_id)
            .or_else(|| self.agent_profiles.first())
    }

    fn sync_agent_profiles_from_registry(&mut self, mut registry: AgentProfileRegistry) {
        let preferred_active_profile_id = self.active_agent_profile_id.clone();
        if !preferred_active_profile_id.trim().is_empty() {
            let _ = registry.set_active(&preferred_active_profile_id);
        }

        let mut agent_profiles = registry.into_profiles();
        if agent_profiles.is_empty() {
            agent_profiles = default_runtime_agent_profiles();
        }

        let resolved_active_profile_id = if agent_profiles
            .iter()
            .any(|profile| profile.id == preferred_active_profile_id)
        {
            preferred_active_profile_id
        } else {
            agent_profiles
                .first()
                .map(|profile| profile.id.clone())
                .unwrap_or_else(default_active_agent_profile_id)
        };

        self.agent_profiles = agent_profiles;
        self.active_agent_profile_id = resolved_active_profile_id;
    }

    fn refresh_agent_profiles(&mut self, config_dir: Option<&Path>) {
        let registry = load_runtime_agent_profile_registry(config_dir);
        self.sync_agent_profiles_from_registry(registry);
    }

    fn set_active_agent_profile(&mut self, profile_id: &str) -> Result<bool, String> {
        if !self
            .agent_profiles
            .iter()
            .any(|profile| profile.id == profile_id)
        {
            return Err(format!("unknown agent profile `{profile_id}`"));
        }

        if self.active_agent_profile_id == profile_id {
            return Ok(false);
        }

        self.active_agent_profile_id = profile_id.to_string();
        self.sync_kernel_sessions();
        Ok(true)
    }

    fn create_conversation(&mut self, title: Option<String>) -> String {
        let conversation_id = self.next_conversation_id();
        let conversation_title = title
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| {
                format!(
                    "Conversation {}",
                    self.conversations.len().saturating_add(1)
                )
            });

        self.active_conversation_id = conversation_id.clone();
        self.conversations.push(RuntimeConversationRecord {
            conversation_id: conversation_id.clone(),
            title: conversation_title.clone(),
            status: "active".to_string(),
            messages: vec![RuntimeConversationMessageRecord {
                message_id: "msg_assistant_01".to_string(),
                role: "assistant".to_string(),
                content: "New conversation ready. Tell GeeAgent what to do next.".to_string(),
                timestamp: current_timestamp_rfc3339(),
            }],
        });
        self.quick_reply = format!(
            "Opened {}. You can start a fresh thread here.",
            conversation_title
        );
        self.last_run_state = None;
        self.workspace_focus = RuntimeWorkspaceFocus {
            mode: "default".to_string(),
            task_id: None,
        };
        self.sync_conversation_statuses();
        self.sync_execution_sessions();
        self.sync_kernel_sessions();
        conversation_id
    }

    fn set_active_conversation(&mut self, conversation_id: &str) -> Result<(), String> {
        let exists = self
            .conversations
            .iter()
            .any(|conversation| conversation.conversation_id == conversation_id);
        if !exists {
            return Err("conversation not found".to_string());
        }

        self.active_conversation_id = conversation_id.to_string();
        self.last_run_state = None;
        self.workspace_focus = RuntimeWorkspaceFocus {
            mode: "default".to_string(),
            task_id: None,
        };
        self.sync_conversation_statuses();
        self.sync_kernel_sessions();
        Ok(())
    }

    fn delete_conversation(&mut self, conversation_id: &str) -> Result<(), String> {
        let Some(index) = self
            .conversations
            .iter()
            .position(|conversation| conversation.conversation_id == conversation_id)
        else {
            return Err("conversation not found".to_string());
        };

        let deleted_title = self.conversations[index].title.clone();
        let deleted_was_active = self.active_conversation_id == conversation_id;
        self.conversations.remove(index);

        if self.conversations.is_empty() {
            let replacement_id = self.next_conversation_id();
            self.active_conversation_id = replacement_id.clone();
            self.conversations.push(RuntimeConversationRecord {
                conversation_id: replacement_id,
                title: "New Conversation".to_string(),
                status: "active".to_string(),
                messages: vec![RuntimeConversationMessageRecord {
                    message_id: "msg_assistant_01".to_string(),
                    role: "assistant".to_string(),
                    content: "Fresh conversation ready. Tell GeeAgent what to do next.".to_string(),
                    timestamp: current_timestamp_rfc3339(),
                }],
            });
        } else if deleted_was_active {
            self.active_conversation_id = self.conversations[0].conversation_id.clone();
        }

        if deleted_was_active {
            self.last_run_state = None;
        }
        self.quick_reply = format!(
            "Deleted {} and refreshed the workspace thread list.",
            deleted_title
        );
        self.workspace_focus = RuntimeWorkspaceFocus {
            mode: "default".to_string(),
            task_id: None,
        };
        self.sync_conversation_statuses();
        self.sync_execution_sessions();
        self.sync_kernel_sessions();
        Ok(())
    }

    fn conversation_summary(
        &self,
        conversation: &RuntimeConversationRecord,
    ) -> RuntimeConversationSummaryRecord {
        let last_message = conversation.messages.last();
        RuntimeConversationSummaryRecord {
            conversation_id: conversation.conversation_id.clone(),
            title: conversation.title.clone(),
            status: conversation.status.clone(),
            last_message_preview: last_message
                .map(|message| summarize_prompt(&message.content, 72))
                .unwrap_or_else(|| "Fresh conversation.".to_string()),
            last_timestamp: last_message
                .map(|message| message.timestamp.clone())
                .unwrap_or_else(|| "--".to_string()),
            is_active: conversation.conversation_id == self.active_conversation_id,
        }
    }

    fn next_conversation_id(&self) -> String {
        let mut next_index = self.conversations.len().saturating_add(1);
        loop {
            let candidate = format!("conv_{next_index:02}");
            if !self
                .conversations
                .iter()
                .any(|conversation| conversation.conversation_id == candidate)
            {
                return candidate;
            }
            next_index = next_index.saturating_add(1);
        }
    }

    fn sync_conversation_statuses(&mut self) {
        for conversation in &mut self.conversations {
            conversation.status = if conversation.conversation_id == self.active_conversation_id {
                "active".to_string()
            } else {
                "idle".to_string()
            };
        }
    }

    fn sync_execution_sessions(&mut self) {
        let mut next_sessions = Vec::with_capacity(self.conversations.len());
        for conversation in &self.conversations {
            let session_id = execution_session_id_for_conversation(&conversation.conversation_id);
            let session = self
                .execution_sessions
                .iter()
                .find(|candidate| candidate.session_id == session_id)
                .cloned()
                .unwrap_or_else(|| ExecutionSession {
                    session_id: session_id.clone(),
                    conversation_id: Some(conversation.conversation_id.clone()),
                    surface: ExecutionSurface::DesktopWorkspaceChat,
                    mode: ExecutionMode::Interactive,
                    project_path: runtime_project_path(),
                    parent_session_id: None,
                    persistence_policy: SessionPersistencePolicy::Persisted,
                    created_at: "now".to_string(),
                    updated_at: "now".to_string(),
                });
            next_sessions.push(session);
        }

        self.execution_sessions = next_sessions;
        let live_session_ids = self
            .execution_sessions
            .iter()
            .map(|session| session.session_id.clone())
            .collect::<HashSet<_>>();
        self.transcript_events
            .retain(|event| live_session_ids.contains(&event.session_id));
    }

    fn sync_kernel_sessions(&mut self) {
        let mut next_sessions = Vec::with_capacity(self.conversations.len());
        for conversation in &self.conversations {
            let session_id = kernel_session_id_for_conversation(&conversation.conversation_id);
            let surface = kernel_surface_for_execution_surface(
                self.execution_sessions
                    .iter()
                    .find(|session| {
                        session.session_id
                            == execution_session_id_for_conversation(&conversation.conversation_id)
                    })
                    .map(|session| session.surface.clone())
                    .unwrap_or(ExecutionSurface::DesktopWorkspaceChat),
            );
            let session = self
                .kernel_sessions
                .iter()
                .find(|candidate| candidate.session.session_id == session_id)
                .cloned()
                .unwrap_or_else(|| {
                    AgentSessionRuntime::new(
                        KernelSession {
                            session_id: session_id.clone(),
                            surface_kind: surface,
                            created_at: "now".to_string(),
                            updated_at: "now".to_string(),
                            active_agent_id: self.active_agent_profile_id.clone(),
                            status: KernelSessionStatus::Idle,
                            current_run_id: None,
                            history_cursor: 0,
                            cwd: runtime_project_path(),
                            workspace_ref: Some(conversation.conversation_id.clone()),
                            runtime_home_ref: None,
                            continuation_strategy: Some("conversation".to_string()),
                            summary_ref: None,
                        },
                        ITERATIVE_TURN_MAX_STEPS as u32,
                    )
                });
            next_sessions.push(session);
        }

        for session in &mut next_sessions {
            session.session.surface_kind = kernel_surface_for_execution_surface(
                self.execution_sessions
                    .iter()
                    .find(|candidate| {
                        candidate.session_id
                            == execution_session_id_for_conversation(
                                session.session.workspace_ref.as_deref().unwrap_or_default(),
                            )
                    })
                    .map(|candidate| candidate.surface.clone())
                    .unwrap_or(ExecutionSurface::DesktopWorkspaceChat),
            );
            session.session.active_agent_id = self.active_agent_profile_id.clone();
            session.session.cwd = runtime_project_path();
            session.session.updated_at = "now".to_string();
        }

        self.kernel_sessions = next_sessions;
    }

    fn ensure_execution_session_for_conversation(
        &mut self,
        conversation_id: &str,
        surface: ExecutionSurface,
    ) -> String {
        let session_id = execution_session_id_for_conversation(conversation_id);
        let project_path = runtime_project_path();

        if let Some(session) = self
            .execution_sessions
            .iter_mut()
            .find(|session| session.session_id == session_id)
        {
            session.surface = surface;
            session.updated_at = "now".to_string();
            if session.project_path.is_none() {
                session.project_path = project_path;
            }
            return session_id;
        }

        self.execution_sessions.push(ExecutionSession {
            session_id: session_id.clone(),
            conversation_id: Some(conversation_id.to_string()),
            surface,
            mode: ExecutionMode::Interactive,
            project_path,
            parent_session_id: None,
            persistence_policy: SessionPersistencePolicy::Persisted,
            created_at: "now".to_string(),
            updated_at: "now".to_string(),
        });

        session_id
    }

    fn ensure_execution_session_for_active_conversation(
        &mut self,
        surface: ExecutionSurface,
    ) -> Option<String> {
        let conversation_id = self.active_conversation_id.clone();
        self.conversations
            .iter()
            .any(|conversation| conversation.conversation_id == conversation_id)
            .then(|| self.ensure_execution_session_for_conversation(&conversation_id, surface))
    }

    fn ensure_kernel_session_for_conversation(
        &mut self,
        conversation_id: &str,
        surface: ExecutionSurface,
    ) -> String {
        let session_id = kernel_session_id_for_conversation(conversation_id);
        let cwd = runtime_project_path();
        let surface_kind = kernel_surface_for_execution_surface(surface);

        if let Some(session) = self
            .kernel_sessions
            .iter_mut()
            .find(|session| session.session.session_id == session_id)
        {
            session.session.surface_kind = surface_kind;
            session.session.active_agent_id = self.active_agent_profile_id.clone();
            session.session.workspace_ref = Some(conversation_id.to_string());
            session.session.cwd = cwd;
            session.session.updated_at = "now".to_string();
            return session_id;
        }

        self.kernel_sessions.push(AgentSessionRuntime::new(
            KernelSession {
                session_id: session_id.clone(),
                surface_kind,
                created_at: "now".to_string(),
                updated_at: "now".to_string(),
                active_agent_id: self.active_agent_profile_id.clone(),
                status: KernelSessionStatus::Idle,
                current_run_id: None,
                history_cursor: 0,
                cwd,
                workspace_ref: Some(conversation_id.to_string()),
                runtime_home_ref: None,
                continuation_strategy: Some("conversation".to_string()),
                summary_ref: None,
            },
            ITERATIVE_TURN_MAX_STEPS as u32,
        ));

        session_id
    }

    fn ensure_kernel_session_for_active_conversation(
        &mut self,
        surface: ExecutionSurface,
    ) -> Option<String> {
        let conversation_id = self.active_conversation_id.clone();
        self.conversations
            .iter()
            .any(|conversation| conversation.conversation_id == conversation_id)
            .then(|| self.ensure_kernel_session_for_conversation(&conversation_id, surface))
    }

    fn kernel_session_runtime_mut(&mut self, session_id: &str) -> Option<&mut AgentSessionRuntime> {
        self.kernel_sessions
            .iter_mut()
            .find(|session| session.session.session_id == session_id)
    }

    fn last_transcript_event_id(&self, session_id: &str) -> Option<String> {
        self.transcript_events
            .iter()
            .rev()
            .find(|event| event.session_id == session_id)
            .map(|event| event.event_id.clone())
    }

    fn next_transcript_event_id(&self, session_id: &str) -> String {
        let next_index = self
            .transcript_events
            .iter()
            .filter(|event| event.session_id == session_id)
            .count()
            .saturating_add(1);
        format!("event_{session_id}_{next_index:02}")
    }

    fn append_transcript_event(
        &mut self,
        session_id: &str,
        payload: TranscriptEventPayload,
    ) -> String {
        let event_id = self.next_transcript_event_id(session_id);
        let parent_event_id = self.last_transcript_event_id(session_id);
        self.transcript_events.push(TranscriptEvent {
            event_id: event_id.clone(),
            session_id: session_id.to_string(),
            parent_event_id,
            created_at: "now".to_string(),
            payload,
        });

        if let Some(session) = self
            .execution_sessions
            .iter_mut()
            .find(|session| session.session_id == session_id)
        {
            session.updated_at = "now".to_string();
        }

        event_id
    }

    fn next_automation_id(&self) -> String {
        let mut next_index = self.automations.len().saturating_add(1);
        loop {
            let candidate = format!("auto_{next_index:02}");
            if !self
                .automations
                .iter()
                .any(|automation| automation.automation_id == candidate)
            {
                return candidate;
            }
            next_index = next_index.saturating_add(1);
        }
    }

    fn insert_execution_automation_draft(&mut self, draft: ExecutionAutomationDraft) {
        self.automations.insert(
            0,
            AutomationDefinition {
                automation_id: self.next_automation_id(),
                name: draft.name,
                status: draft.status,
                trigger_kind: draft.trigger_kind,
                goal_prompt: draft.goal_prompt,
                lock_policy: draft.lock_policy,
                cadence: draft.cadence,
                time_of_day: draft.time_of_day,
                schedule_hint: draft.schedule_hint,
            },
        );
    }
}

#[cfg(test)]
fn seeded_runtime_snapshot() -> RuntimeSnapshot {
    RuntimeSnapshot {
        quick_input_hint:
            "Ask GeeAgent to review a draft, check your queue, or run a task.".to_string(),
        quick_reply: "GeeAgent is standing by in the creator ops workspace.".to_string(),
        context_budget: default_runtime_context_budget_record(),
        active_agent_profile: default_runtime_agent_profile(),
        agent_profiles: default_runtime_agent_profiles(),
        interaction_capabilities: desktop_interaction_capabilities(),
        last_request_outcome: None,
        last_run_state: None,
        chat_runtime: RuntimeChatRuntimeRecord {
            status: "live".to_string(),
            active_provider: Some("xenodia".to_string()),
            detail: "Live chat via xenodia. Ready for workspace chat and quick replies."
                .to_string(),
        },
        conversations: vec![RuntimeConversationSummaryRecord {
            conversation_id: "conv_notes".to_string(),
            title: "Notes Lab".to_string(),
            status: "idle".to_string(),
            last_message_preview: "Waiting on the next note revision.".to_string(),
            last_timestamp: "now".to_string(),
            is_active: false,
        }],
        active_conversation: RuntimeConversationRecord {
            conversation_id: "conv_creator_ops".to_string(),
            title: "Creator Ops".to_string(),
            status: "active".to_string(),
            messages: vec![
                RuntimeConversationMessageRecord {
                    message_id: "msg_assistant_01".to_string(),
                    role: "assistant".to_string(),
                    content: "Creator ops thread ready. Bring me the next upload review or routing task.".to_string(),
                    timestamp: "now".to_string(),
                },
                RuntimeConversationMessageRecord {
                    message_id: "msg_user_02".to_string(),
                    role: "user".to_string(),
                    content: "Review the newest creator upload and tell me if it should be saved as a note.".to_string(),
                    timestamp: "now".to_string(),
                },
            ],
        },
        automations: Vec::new(),
        module_runs: vec![
            RuntimeModuleRunRecord {
                module_run: ModuleRun {
                    module_run_id: "run_publish_01".to_string(),
                    task_id: "task_review_publish".to_string(),
                    module_id: "content.publisher".to_string(),
                    capability_id: "publish_ready_draft".to_string(),
                    status: ModuleRunStatus::WaitingReview,
                    stage: ModuleRunStage::ReviewPending,
                    attempt_count: 1,
                    result_summary: Some(
                        "Prepared publish action is waiting for review approval.".to_string(),
                    ),
                    artifacts: vec![ArtifactEnvelope {
                        artifact_id: "artifact_publish_preview".to_string(),
                        artifact_type: "draft_preview".to_string(),
                        title: "Publish preview".to_string(),
                        summary: "Draft copy prepared for a final publish review.".to_string(),
                        payload_ref: "memory://publish/preview".to_string(),
                        inline_preview: None,
                        domain_tags: vec!["publish".to_string(), "review".to_string()],
                    }],
                    created_at: "2026-04-14T08:50:00Z".to_string(),
                    updated_at: "now".to_string(),
                },
                recoverability: Some(Recoverability {
                    retry_safe: true,
                    resume_supported: true,
                    hint: Some("Revise the draft or approve the publish action.".to_string()),
                }),
            },
            RuntimeModuleRunRecord {
                module_run: ModuleRun {
                    module_run_id: "run_digest_01".to_string(),
                    task_id: "task_digest_youtube".to_string(),
                    module_id: "content.youtube.monitor".to_string(),
                    capability_id: "digest_recent_uploads".to_string(),
                    status: ModuleRunStatus::Running,
                    stage: ModuleRunStage::Postprocess,
                    attempt_count: 1,
                    result_summary: Some(
                        "The upstream work finished and GeeAgent is packaging the returned artifacts."
                            .to_string(),
                    ),
                    artifacts: vec![
                        ArtifactEnvelope {
                            artifact_id: "artifact_digest_board".to_string(),
                            artifact_type: "digest_summary".to_string(),
                            title: "Morning digest draft".to_string(),
                            summary: "Three creator uploads ranked by importance.".to_string(),
                            payload_ref: "memory://digest/14".to_string(),
                            inline_preview: None,
                            domain_tags: vec!["youtube".to_string(), "digest".to_string()],
                        },
                        ArtifactEnvelope {
                            artifact_id: "artifact_digest_notes".to_string(),
                            artifact_type: "note_bundle".to_string(),
                            title: "Digest notes".to_string(),
                            summary: "Working notes captured from the upstream module.".to_string(),
                            payload_ref: "memory://digest/14/notes".to_string(),
                            inline_preview: None,
                            domain_tags: vec!["youtube".to_string(), "notes".to_string()],
                        },
                        ArtifactEnvelope {
                            artifact_id: "artifact_digest_links".to_string(),
                            artifact_type: "link_bundle".to_string(),
                            title: "Creator links".to_string(),
                            summary: "Outgoing links prepared for the digest board.".to_string(),
                            payload_ref: "memory://digest/14/links".to_string(),
                            inline_preview: None,
                            domain_tags: vec!["youtube".to_string(), "links".to_string()],
                        },
                        ArtifactEnvelope {
                            artifact_id: "artifact_digest_payload".to_string(),
                            artifact_type: "upstream_payload".to_string(),
                            title: "Upstream payload".to_string(),
                            summary: "Captured upstream payload for the digest run.".to_string(),
                            payload_ref: "memory://digest/14/payload".to_string(),
                            inline_preview: None,
                            domain_tags: vec!["youtube".to_string(), "payload".to_string()],
                        },
                    ],
                    created_at: "2026-04-14T09:55:00Z".to_string(),
                    updated_at: "now".to_string(),
                },
                recoverability: Some(Recoverability {
                    retry_safe: true,
                    resume_supported: false,
                    hint: Some("GeeAgent is finalizing the digest package.".to_string()),
                }),
            },
        ],
        execution_sessions: Vec::new(),
        kernel_sessions: Vec::new(),
        transcript_events: Vec::new(),
        tasks: vec![
            RuntimeTaskRecord {
                task_id: "task_review_publish".to_string(),
                conversation_id: Some("conv_creator_ops".to_string()),
                title: "Publish the prepared creator update".to_string(),
                summary: "Prepared publish action is waiting for review approval.".to_string(),
                current_stage: "review_pending".to_string(),
                status: "waiting_review".to_string(),
                importance_level: "review".to_string(),
                progress_percent: 92,
                artifact_count: 1,
                approval_request_id: Some("apr_01".to_string()),
            },
            RuntimeTaskRecord {
                task_id: "task_digest_youtube".to_string(),
                conversation_id: Some("conv_creator_ops".to_string()),
                title: "Digest the latest creator uploads".to_string(),
                summary:
                    "The upstream work finished and GeeAgent is packaging the returned artifacts."
                        .to_string(),
                current_stage: "postprocess".to_string(),
                status: "running".to_string(),
                importance_level: "important".to_string(),
                progress_percent: 82,
                artifact_count: 5,
                approval_request_id: None,
            },
            RuntimeTaskRecord {
                task_id: "task_waiting_note".to_string(),
                conversation_id: Some("conv_notes".to_string()),
                title: "Refine the private note".to_string(),
                summary: "Waiting for direction on how to rewrite the private note.".to_string(),
                current_stage: "waiting_input".to_string(),
                status: "waiting_input".to_string(),
                importance_level: "important".to_string(),
                progress_percent: 48,
                artifact_count: 0,
                approval_request_id: None,
            },
            RuntimeTaskRecord {
                task_id: "task_background_watch".to_string(),
                conversation_id: Some("conv_creator_ops".to_string()),
                title: "Background creator monitoring".to_string(),
                summary: "Monitoring continues in the background.".to_string(),
                current_stage: "reporting".to_string(),
                status: "running".to_string(),
                importance_level: "background".to_string(),
                progress_percent: 34,
                artifact_count: 0,
                approval_request_id: None,
            },
        ],
        approval_requests: vec![RuntimeApprovalRecord {
            approval_request_id: "apr_01".to_string(),
            task_id: "task_review_publish".to_string(),
            action_title: "Approve the prepared publish action".to_string(),
            reason: "This publish action will change an external destination.".to_string(),
            risk_tags: vec!["external_state_change".to_string()],
            review_required: true,
            status: "open".to_string(),
            parameters: vec![RuntimeApprovalParameter {
                label: "Destination".to_string(),
                value: "Creator feed".to_string(),
            }],
            machine_context: None,
        }],
        workspace_focus: RuntimeWorkspaceFocus {
            mode: "default".to_string(),
            task_id: None,
        },
        workspace_runtime: Some(bootstrap_workspace_snapshot()),
    }
}

#[cfg(test)]
fn seed_shell_snapshot() -> Result<RuntimeSnapshot, String> {
    let fixture_path =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../src/fixtures/runtime-snapshot.json");
    if fixture_path.is_file() {
        return fs::read_to_string(&fixture_path)
            .map_err(|error| error.to_string())
            .and_then(|raw| serde_json::from_str(&raw).map_err(|error| error.to_string()));
    }

    Ok(seeded_runtime_snapshot())
}

#[cfg(test)]
fn seed_runtime_store() -> Result<RuntimeStore, String> {
    seed_shell_snapshot().map(RuntimeStore::from_snapshot)
}

fn bootstrap_workspace_runtime() -> WorkspaceRuntime {
    let registry = ExperienceRegistry::new(
        vec![InstalledAppManifest::with_display_mode(
            "media.library",
            "Media Library",
            InstallState::Installed,
            ModuleDisplayMode::FullCanvas,
        )],
        vec![AgentSkinManifest::new(
            "default.operator",
            "Default Operator",
        )],
    )
    .expect("seeded workspace registry should be valid");

    WorkspaceRuntime::new(registry)
}

fn bootstrap_workspace_snapshot() -> WorkspaceSnapshot {
    bootstrap_workspace_runtime().snapshot()
}

fn is_obsolete_workspace_app(app_id: &str) -> bool {
    matches!(app_id, "media.playlists")
}

fn ensure_workspace_runtime_catalog(store: &mut RuntimeStore) {
    let canonical_snapshot = bootstrap_workspace_snapshot();
    let Some(runtime) = store.workspace_runtime.as_mut() else {
        store.workspace_runtime = Some(canonical_snapshot);
        return;
    };

    let active_section = runtime.active_section.clone();
    let existing_sections = runtime.sections.clone();
    let existing_apps = runtime.apps.clone();
    let existing_skins = runtime.agent_skins.clone();
    let mut reconciled = canonical_snapshot;

    reconciled.active_section = active_section;
    for section in existing_sections {
        if !reconciled.sections.contains(&section) {
            reconciled.sections.push(section);
        }
    }
    for app in existing_apps {
        if is_obsolete_workspace_app(&app.app_id) {
            continue;
        }
        if !reconciled
            .apps
            .iter()
            .any(|candidate| candidate.app_id == app.app_id)
        {
            reconciled.apps.push(app);
        }
    }
    for skin in existing_skins {
        if !reconciled
            .agent_skins
            .iter()
            .any(|candidate| candidate.skin_id == skin.skin_id)
        {
            reconciled.agent_skins.push(skin);
        }
    }

    store.workspace_runtime = Some(reconciled);
}

fn default_runtime_store() -> RuntimeStore {
    let mut store = RuntimeStore {
        quick_input_hint: "Ask GeeAgent to review a draft, check your queue, or run a task."
            .to_string(),
        quick_reply: "GeeAgent is standing by. Use quick input or the workspace chat to start a task."
            .to_string(),
        agent_profiles: default_runtime_agent_profiles(),
        active_agent_profile_id: default_active_agent_profile_id(),
        interaction_capabilities: desktop_interaction_capabilities(),
        last_request_outcome: None,
        last_run_state: None,
        chat_runtime: RuntimeChatRuntimeRecord {
            status: "needs_setup".to_string(),
            active_provider: None,
            detail: "Live chat is waiting for provider configuration.".to_string(),
        },
        conversations: vec![RuntimeConversationRecord {
            conversation_id: "conv_01".to_string(),
            title: "New Conversation".to_string(),
            status: "active".to_string(),
            messages: vec![RuntimeConversationMessageRecord {
                message_id: "msg_assistant_01".to_string(),
                role: "assistant".to_string(),
                content:
                    "New conversation ready. Tell GeeAgent what to do next, or use quick input for a lighter command."
                        .to_string(),
                timestamp: current_timestamp_rfc3339(),
            }],
        }],
        active_conversation_id: "conv_01".to_string(),
        automations: Vec::new(),
        module_runs: Vec::new(),
        execution_sessions: Vec::new(),
        kernel_sessions: Vec::new(),
        transcript_events: Vec::new(),
        tasks: Vec::new(),
        approval_requests: Vec::new(),
        workspace_focus: RuntimeWorkspaceFocus {
            mode: "default".to_string(),
            task_id: None,
        },
        workspace_runtime: Some(bootstrap_workspace_snapshot()),
    };
    ensure_workspace_runtime_catalog(&mut store);
    store.sync_conversation_statuses();
    store.sync_execution_sessions();
    store.sync_kernel_sessions();
    store
}

fn current_timestamp_rfc3339() -> String {
    Utc::now().to_rfc3339()
}

fn runtime_project_path() -> Option<String> {
    std::env::current_dir()
        .ok()
        .map(|path| path.to_string_lossy().to_string())
}

fn agent_runtime_bridge_dir() -> PathBuf {
    if let Ok(path) = std::env::var("GEEAGENT_AGENT_RUNTIME_BRIDGE_DIR") {
        let trimmed = path.trim();
        if !trimmed.is_empty() {
            return PathBuf::from(trimmed);
        }
    }

    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../agent-runtime-bridge")
        .canonicalize()
        .unwrap_or_else(|_| {
            PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../agent-runtime-bridge")
        })
}

fn agent_runtime_bridge_entrypoint() -> PathBuf {
    if let Ok(path) = std::env::var("GEEAGENT_AGENT_RUNTIME_BRIDGE_ENTRYPOINT") {
        let trimmed = path.trim();
        if !trimmed.is_empty() {
            return PathBuf::from(trimmed);
        }
    }

    agent_runtime_bridge_dir().join("dist/index.js")
}

fn claude_sdk_runtime_provider_label() -> &'static str {
    "sdk (xenodia backend)"
}

fn ensure_agent_runtime_bridge_ready() -> Result<PathBuf, String> {
    let bridge_dir = agent_runtime_bridge_dir();
    if !bridge_dir.is_dir() {
        return Err(format!(
            "Agent runtime bridge directory is missing: {}",
            bridge_dir.display()
        ));
    }

    let entrypoint = agent_runtime_bridge_entrypoint();
    if entrypoint.is_file() {
        return Ok(entrypoint);
    }

    let install_status = Command::new("npm")
        .arg("install")
        .current_dir(&bridge_dir)
        .status()
        .map_err(|error| format!("failed to run npm install for agent runtime bridge: {error}"))?;
    if !install_status.success() {
        return Err("npm install failed for agent runtime bridge".to_string());
    }

    let build_status = Command::new("npm")
        .args(["run", "build"])
        .current_dir(&bridge_dir)
        .status()
        .map_err(|error| format!("failed to build agent runtime bridge: {error}"))?;
    if !build_status.success() {
        return Err("npm run build failed for agent runtime bridge".to_string());
    }

    if !entrypoint.is_file() {
        return Err(format!(
            "Agent runtime bridge build completed but entrypoint is still missing: {}",
            entrypoint.display()
        ));
    }

    Ok(entrypoint)
}

fn write_agent_runtime_bridge_command(
    stdin: &mut std::process::ChildStdin,
    command: serde_json::Value,
) -> Result<(), String> {
    let serialized = serde_json::to_string(&command)
        .map_err(|error| format!("invalid bridge command: {error}"))?;
    stdin
        .write_all(serialized.as_bytes())
        .map_err(|error| format!("failed to write bridge command: {error}"))?;
    stdin
        .write_all(b"\n")
        .map_err(|error| format!("failed to terminate bridge command: {error}"))?;
    stdin
        .flush()
        .map_err(|error| format!("failed to flush bridge command: {error}"))?;
    Ok(())
}

fn read_agent_runtime_bridge_event(
    reader: &mut BufReader<ChildStdout>,
) -> Result<Option<serde_json::Value>, String> {
    let mut line = String::new();
    loop {
        line.clear();
        let bytes = reader
            .read_line(&mut line)
            .map_err(|error| format!("failed reading SDK bridge output: {error}"))?;
        if bytes == 0 {
            return Ok(None);
        }

        let raw = line.trim();
        if raw.is_empty() {
            continue;
        }

        let event: serde_json::Value = serde_json::from_str(raw)
            .map_err(|error| format!("invalid SDK bridge JSON: {error}"))?;
        return Ok(Some(event));
    }
}

fn bridge_event_type(event: &serde_json::Value) -> &str {
    event
        .get("type")
        .and_then(serde_json::Value::as_str)
        .unwrap_or_default()
}

fn start_agent_runtime_bridge_process(
    session_id: &str,
    route: &TurnRoute,
    prepared: &PreparedTurnContext,
    config_dir: Option<&Path>,
    gateway_backend: &chat_runtime::ClaudeSdkGatewayBackend,
) -> Result<AgentRuntimeBridgeProcess, String> {
    let entrypoint = ensure_agent_runtime_bridge_ready()?;
    let bridge_dir = agent_runtime_bridge_dir();
    let runtime_facts = runtime_facts_for_surface(route.surface.clone());

    let mut bridge_command = Command::new("node");
    bridge_command
        .arg(entrypoint)
        .current_dir(&bridge_dir)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .env("GEEAGENT_XENODIA_API_KEY", &gateway_backend.api_key)
        .env(
            "GEEAGENT_XENODIA_CHAT_COMPLETIONS_URL",
            &gateway_backend.chat_completions_url,
        )
        .env("GEEAGENT_XENODIA_MODEL", &gateway_backend.model)
        .env(
            "CLAUDE_AGENT_SDK_CLIENT_APP",
            "geeagent/agent-runtime-bridge",
        );
    if let Some(path) = config_dir {
        bridge_command.env("GEEAGENT_CONFIG_DIR", path);
    }

    let mut child = bridge_command
        .spawn()
        .map_err(|error| format!("failed to launch SDK bridge: {error}"))?;
    let mut stdin = child
        .stdin
        .take()
        .ok_or_else(|| "SDK bridge stdin unavailable".to_string())?;
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| "SDK bridge stdout unavailable".to_string())?;
    let stderr = child
        .stderr
        .take()
        .ok_or_else(|| "SDK bridge stderr unavailable".to_string())?;
    let mut reader = BufReader::new(stdout);

    loop {
        let Some(event) = read_agent_runtime_bridge_event(&mut reader)? else {
            return Err("SDK bridge exited before it was ready.".to_string());
        };
        if bridge_event_type(&event) == "bridge.ready" {
            break;
        }
        if bridge_event_type(&event) == "session.error" {
            return Err(event
                .get("error")
                .and_then(serde_json::Value::as_str)
                .unwrap_or("SDK bridge failed during startup.")
                .to_string());
        }
    }

    write_agent_runtime_bridge_command(
        &mut stdin,
        serde_json::json!({
            "type": "bridge.init",
            "defaultModel": "sonnet"
        }),
    )?;
    loop {
        let Some(event) = read_agent_runtime_bridge_event(&mut reader)? else {
            return Err("SDK bridge exited before initialization completed.".to_string());
        };
        match bridge_event_type(&event) {
            "bridge.initialized" => break,
            "session.error" => {
                return Err(event
                    .get("error")
                    .and_then(serde_json::Value::as_str)
                    .unwrap_or("SDK bridge failed during initialization.")
                    .to_string());
            }
            _ => {}
        }
    }

    write_agent_runtime_bridge_command(
        &mut stdin,
        serde_json::json!({
            "type": "session.create",
            "sessionId": session_id,
            "cwd": runtime_project_path().unwrap_or_else(|| runtime_facts.cwd.clone()),
            "model": "sonnet",
            "maxTurns": ITERATIVE_TURN_MAX_STEPS,
            "systemPrompt": active_agent_system_prompt(&prepared.active_agent_profile),
            "runtimeContext": {
                "localTime": runtime_facts.local_time,
                "timezone": runtime_facts.time_zone,
                "surface": format!("{:?}", route.surface),
                "cwd": runtime_facts.cwd,
                "approvalPosture": if highest_authorization_enabled(config_dir) { "highest_authorization" } else { "gee_terminal_permissions" },
                "capabilities": ["bash", "read", "write", "edit", "grep", "glob", "ls", "websearch", "webfetch"]
            },
            "autoApproveTools": ["Read", "Glob", "Grep", "LS", "ToolSearch", "ExitPlanMode", "BashOutput", "KillBash"]
        }),
    )?;
    loop {
        let Some(event) = read_agent_runtime_bridge_event(&mut reader)? else {
            return Err("SDK bridge exited before session creation completed.".to_string());
        };
        match bridge_event_type(&event) {
            "session.created" => break,
            "session.error" => {
                return Err(event
                    .get("error")
                    .and_then(serde_json::Value::as_str)
                    .unwrap_or("SDK bridge failed during session creation.")
                    .to_string());
            }
            _ => {}
        }
    }

    Ok(AgentRuntimeBridgeProcess {
        child,
        stdin,
        reader,
        _stderr: stderr,
    })
}

fn compose_claude_sdk_turn_prompt(
    route: &TurnRoute,
    prepared: &PreparedTurnContext,
    text: &str,
) -> String {
    let trimmed = text.trim();
    if matches!(route.mode, TurnMode::QuickPrompt) || prepared.workspace_messages.is_empty() {
        return trimmed.to_string();
    }

    let projected_messages = context_projected_workspace_messages(&prepared.workspace_messages).0;
    let history = projected_messages
        .iter()
        .map(|message| {
            format!(
                "{}: {}",
                if message.role == "assistant" {
                    "Assistant"
                } else {
                    "User"
                },
                message.content
            )
        })
        .collect::<Vec<_>>()
        .join("\n");

    format!(
        "Conversation context before the latest turn:\n{history}\n\nLatest user request:\n{trimmed}\n\nSolve the latest request directly. Use tools when needed. Do not ask the user to type 'continue' for ordinary local work."
    )
}

fn approximate_context_tokens(text: &str) -> usize {
    let mut cjk_chars = 0usize;
    let mut other_chars = 0usize;
    for ch in text.chars() {
        if ('\u{4e00}'..='\u{9fff}').contains(&ch)
            || ('\u{3400}'..='\u{4dbf}').contains(&ch)
            || ('\u{3040}'..='\u{30ff}').contains(&ch)
            || ('\u{ac00}'..='\u{d7af}').contains(&ch)
        {
            cjk_chars = cjk_chars.saturating_add(1);
        } else {
            other_chars = other_chars.saturating_add(1);
        }
    }

    let char_estimate = cjk_chars.saturating_add(other_chars.saturating_add(3) / 4);
    let byte_estimate = text.len().saturating_add(3) / 4;
    char_estimate.max(byte_estimate).max(1)
}

fn estimate_workspace_message_tokens(message: &WorkspaceChatMessage) -> usize {
    // Add a small per-message overhead for role labels and SDK message framing.
    approximate_context_tokens(&message.role)
        .saturating_add(approximate_context_tokens(&message.content))
        .saturating_add(8)
}

fn estimate_workspace_messages_tokens(messages: &[WorkspaceChatMessage]) -> usize {
    messages
        .iter()
        .map(estimate_workspace_message_tokens)
        .sum::<usize>()
}

fn build_context_compaction_summary(messages: &[WorkspaceChatMessage]) -> String {
    let user_messages = messages
        .iter()
        .filter(|message| message.role != "assistant")
        .map(|message| summarize_prompt(&message.content, 180))
        .collect::<Vec<_>>();
    let assistant_messages = messages
        .iter()
        .filter(|message| message.role == "assistant")
        .map(|message| summarize_prompt(&message.content, 180))
        .collect::<Vec<_>>();

    let mut lines = vec![
        "[AUTO CONTEXT SUMMARY] Older conversation turns were compacted before the 256k context window filled. The full transcript remains available in GeeAgent history; this summary is the model-facing continuity layer.".to_string(),
        format!("Compacted messages: {}.", messages.len()),
    ];

    if !user_messages.is_empty() {
        lines.push("User intent and feedback from compacted history:".to_string());
        for entry in user_messages.iter().take(12) {
            lines.push(format!("- {entry}"));
        }
        if user_messages.len() > 12 {
            lines.push(format!(
                "- …{} more older user message(s) retained in transcript.",
                user_messages.len() - 12
            ));
        }
    }

    if !assistant_messages.is_empty() {
        lines.push("Prior assistant work from compacted history:".to_string());
        for entry in assistant_messages.iter().rev().take(8).rev() {
            lines.push(format!("- {entry}"));
        }
    }

    lines.push(
        "Continue from the recent verbatim messages below. Preserve active tasks, approvals, files, commands, and user corrections from the recent context."
            .to_string(),
    );
    lines.join("\n")
}

fn context_projected_workspace_messages(
    messages: &[WorkspaceChatMessage],
) -> (Vec<WorkspaceChatMessage>, usize, usize) {
    let raw_tokens = estimate_workspace_messages_tokens(messages);
    if raw_tokens < CONTEXT_AUTO_SUMMARY_TRIGGER_TOKENS
        || messages.len() <= CONTEXT_RECENT_MESSAGE_KEEP_COUNT
    {
        return (messages.to_vec(), 0, raw_tokens);
    }

    let split_at = messages
        .len()
        .saturating_sub(CONTEXT_RECENT_MESSAGE_KEEP_COUNT);
    let (older, recent) = messages.split_at(split_at);
    let summary = WorkspaceChatMessage {
        role: "assistant".to_string(),
        content: build_context_compaction_summary(older),
    };
    let mut projected = Vec::with_capacity(recent.len().saturating_add(1));
    projected.push(summary);
    projected.extend(recent.iter().cloned());
    let projected_tokens = estimate_workspace_messages_tokens(&projected);
    (projected, older.len(), projected_tokens)
}

fn context_budget_record_for_store(store: &RuntimeStore) -> RuntimeContextBudgetRecord {
    let messages = workspace_messages_from_store(store);
    let raw_tokens = estimate_workspace_messages_tokens(&messages);
    let (_, compacted_messages_count, projected_tokens) =
        context_projected_workspace_messages(&messages);
    let used_tokens = projected_tokens.min(CONTEXT_WINDOW_TOKENS);
    let usage_ratio = used_tokens as f64 / CONTEXT_WINDOW_TOKENS as f64;
    let summary_state = if compacted_messages_count > 0 {
        "summarized"
    } else if raw_tokens >= CONTEXT_AUTO_SUMMARY_TRIGGER_TOKENS {
        "summarizing"
    } else if raw_tokens >= CONTEXT_SUMMARY_SOON_TOKENS {
        "scheduled"
    } else if raw_tokens == 0 {
        "idle"
    } else {
        "watching"
    };

    RuntimeContextBudgetRecord {
        max_tokens: CONTEXT_WINDOW_TOKENS,
        used_tokens,
        reserved_output_tokens: CONTEXT_RESERVED_OUTPUT_TOKENS,
        usage_ratio,
        estimate_source: "estimated".to_string(),
        summary_state: summary_state.to_string(),
        last_summarized_at: None,
        next_summary_at_ratio: 0.95,
        compacted_messages_count,
    }
}

fn claude_sdk_chat_runtime_record() -> RuntimeChatRuntimeRecord {
    RuntimeChatRuntimeRecord {
        status: "live".to_string(),
        active_provider: Some(claude_sdk_runtime_provider_label().to_string()),
        detail: "The SDK is driving the agent loop through the local Xenodia model gateway."
            .to_string(),
    }
}

fn claude_sdk_degraded_chat_runtime_record(reason: &str) -> RuntimeChatRuntimeRecord {
    RuntimeChatRuntimeRecord {
        status: "degraded".to_string(),
        active_provider: Some(claude_sdk_runtime_provider_label().to_string()),
        detail: format!(
            "The SDK through the Xenodia gateway degraded during this turn. {}",
            summarize_prompt(reason, 220)
        ),
    }
}

fn claude_sdk_completed_run_state(
    store: &RuntimeStore,
    assistant_reply: &str,
) -> RuntimeRunStateRecord {
    runtime_run_state(
        active_conversation_id(store),
        "completed",
        "claude_sdk_completed",
        if assistant_reply.trim().is_empty() {
            "The SDK bridge completed the turn.".to_string()
        } else {
            summarize_prompt(assistant_reply, 220)
        },
        false,
        None,
        None,
    )
}

fn claude_sdk_failed_run_state(store: &RuntimeStore, error: &str) -> RuntimeRunStateRecord {
    runtime_run_state(
        active_conversation_id(store),
        "failed",
        "claude_sdk_failed",
        summarize_prompt(error, 220),
        false,
        None,
        None,
    )
}

fn claude_sdk_quick_reply(assistant_reply: &str, tool_step_count: usize) -> String {
    let summary = summarize_prompt(assistant_reply, 140);
    if tool_step_count == 0 || summary.is_empty() {
        summary
    } else {
        format!("Completed {tool_step_count} tool step(s). {summary}")
    }
}

fn claude_sdk_failed_quick_reply(reason: &str) -> String {
    format!(
        "The SDK + Xenodia could not complete this run. {}",
        summarize_prompt(reason, 180)
    )
}

fn claude_sdk_failure_assistant_reply(reason: &str) -> String {
    format!(
        "The SDK + Xenodia did not complete this run successfully: {}. I did not present it as completed.",
        summarize_prompt(reason, 220)
    )
}

fn map_claude_sdk_tool_status(raw_status: &str) -> ToolInvocationStatus {
    match raw_status {
        "failed" => ToolInvocationStatus::Failed,
        _ => ToolInvocationStatus::Succeeded,
    }
}

fn parse_claude_sdk_tool_result_summary(
    value: &serde_json::Value,
) -> (Option<String>, Option<String>) {
    let summary = value
        .get("summary")
        .and_then(serde_json::Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| summarize_prompt(value, 220));
    let error = value
        .get("error")
        .and_then(serde_json::Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| summarize_prompt(value, 220));
    (summary, error)
}

fn is_auto_approved_read_only_sdk_tool(tool_name: &str) -> bool {
    matches!(
        tool_name.to_ascii_lowercase().as_str(),
        "websearch" | "webfetch"
    )
}

fn collect_agent_runtime_bridge_events_until_pause_or_result(
    bridge: &mut AgentRuntimeBridgeProcess,
    session_id: &str,
    config_dir: Option<&Path>,
    transient_allowed_terminal_scopes: &[TerminalAccessScope],
    turn: &mut ClaudeSdkBridgeTurnResult,
) -> Result<(), String> {
    let mut pending_invocations = HashMap::<String, (String, Option<String>)>::new();

    loop {
        let Some(event) = read_agent_runtime_bridge_event(&mut bridge.reader)? else {
            turn.failed_reason =
                Some("SDK bridge exited before the active run reached a result.".to_string());
            break;
        };

        match bridge_event_type(&event) {
            "session.approval_requested" => {
                let request_id = event
                    .get("requestId")
                    .and_then(serde_json::Value::as_str)
                    .ok_or_else(|| {
                        "SDK bridge approval request was missing requestId".to_string()
                    })?;
                let tool_name = event
                    .get("toolName")
                    .and_then(serde_json::Value::as_str)
                    .unwrap_or_default();
                let input = event
                    .get("input")
                    .cloned()
                    .unwrap_or_else(|| serde_json::json!({}));

                if highest_authorization_enabled(config_dir) {
                    turn.auto_approved_tools = turn.auto_approved_tools.saturating_add(1);
                    write_agent_runtime_bridge_command(
                        &mut bridge.stdin,
                        serde_json::json!({
                            "type": "session.approval",
                            "sessionId": session_id,
                            "requestId": request_id,
                            "decision": "allow"
                        }),
                    )?;
                    continue;
                }

                if is_auto_approved_read_only_sdk_tool(tool_name) {
                    turn.auto_approved_tools = turn.auto_approved_tools.saturating_add(1);
                    write_agent_runtime_bridge_command(
                        &mut bridge.stdin,
                        serde_json::json!({
                            "type": "session.approval",
                            "sessionId": session_id,
                            "requestId": request_id,
                            "decision": "allow"
                        }),
                    )?;
                    continue;
                }

                if tool_name == "Bash" {
                    let (command, cwd) = bridge_bash_request_from_input(&input)
                        .unwrap_or_else(|| ("Bash tool request".to_string(), None));
                    let scope = sdk_bridge_bash_scope(&command, cwd.as_deref());
                    let is_transient_allow = transient_allowed_terminal_scopes
                        .iter()
                        .any(|allowed| allowed == &scope);
                    let decision = if is_transient_allow {
                        Some(TerminalAccessDecision::Allow)
                    } else {
                        terminal_access_decision_for_scope(config_dir, &scope)
                    };

                    match decision {
                        Some(TerminalAccessDecision::Allow) => {
                            turn.auto_approved_tools = turn.auto_approved_tools.saturating_add(1);
                            write_agent_runtime_bridge_command(
                                &mut bridge.stdin,
                                serde_json::json!({
                                    "type": "session.approval",
                                    "sessionId": session_id,
                                    "requestId": request_id,
                                    "decision": "allow"
                                }),
                            )?;
                        }
                        Some(TerminalAccessDecision::Deny) => {
                            turn.terminal_access_denied_reason = Some(format!(
                                "GeeAgent terminal permissions blocked this command: {}",
                                terminal_access_label_for_scope(&scope)
                            ));
                            write_agent_runtime_bridge_command(
                                &mut bridge.stdin,
                                serde_json::json!({
                                    "type": "session.approval",
                                    "sessionId": session_id,
                                    "requestId": request_id,
                                    "decision": "deny",
                                    "message": "GeeAgent terminal permissions deny this Bash request."
                                }),
                            )?;
                        }
                        None => {
                            turn.pending_terminal_approval =
                                Some(ClaudeSdkPendingTerminalApproval {
                                    bridge_session_id: session_id.to_string(),
                                    bridge_request_id: request_id.to_string(),
                                    scope,
                                    command: command.clone(),
                                    cwd: cwd.clone(),
                                    input_summary: Some(summarize_prompt(
                                        &match cwd.clone() {
                                            Some(cwd) => format!("{command} @ {cwd}"),
                                            None => command,
                                        },
                                        180,
                                    )),
                                });
                            break;
                        }
                    }
                    continue;
                }

                let denial_message = format!(
                    "GeeAgent host policy does not directly approve `{tool_name}` through this boundary yet. Use Bash for local shell/file work so it can go through the terminal permission review flow."
                );
                write_agent_runtime_bridge_command(
                    &mut bridge.stdin,
                    serde_json::json!({
                        "type": "session.approval",
                        "sessionId": session_id,
                        "requestId": request_id,
                        "decision": "deny",
                        "message": denial_message
                    }),
                )?;
            }
            "session.tool_use" => {
                let invocation_id = event
                    .get("toolUseId")
                    .and_then(serde_json::Value::as_str)
                    .ok_or_else(|| "SDK bridge tool use was missing toolUseId".to_string())?
                    .to_string();
                let tool_name = event
                    .get("toolName")
                    .and_then(serde_json::Value::as_str)
                    .unwrap_or("tool")
                    .to_string();
                let input_summary = event
                    .get("input")
                    .map(|value| summarize_prompt(&value.to_string(), 180));

                pending_invocations.insert(
                    invocation_id.clone(),
                    (tool_name.clone(), input_summary.clone()),
                );
                turn.tool_events
                    .push(ClaudeSdkBridgeObservedToolEvent::Invocation {
                        invocation_id,
                        tool_name,
                        input_summary,
                    });
            }
            "session.tool_result" => {
                let invocation_id = event
                    .get("toolUseId")
                    .and_then(serde_json::Value::as_str)
                    .ok_or_else(|| "SDK bridge tool result was missing toolUseId".to_string())?
                    .to_string();
                let raw_status = event
                    .get("status")
                    .and_then(serde_json::Value::as_str)
                    .unwrap_or("succeeded");
                let (summary, error) = parse_claude_sdk_tool_result_summary(&event);
                let _ = pending_invocations.remove(&invocation_id);
                turn.tool_events
                    .push(ClaudeSdkBridgeObservedToolEvent::Result {
                        invocation_id,
                        status: map_claude_sdk_tool_status(raw_status),
                        summary,
                        error,
                    });
            }
            "session.assistant_text" => {
                if let Some(text) = event.get("text").and_then(serde_json::Value::as_str) {
                    let trimmed = text.trim();
                    if !trimmed.is_empty() {
                        turn.assistant_chunks.push(trimmed.to_string());
                    }
                }
            }
            "session.result" => {
                let result_text = event
                    .get("result")
                    .and_then(serde_json::Value::as_str)
                    .map(str::trim)
                    .filter(|value| !value.is_empty())
                    .map(|value| value.to_string());
                let is_error = event
                    .get("raw")
                    .and_then(|value| value.get("is_error"))
                    .and_then(serde_json::Value::as_bool)
                    .unwrap_or(false);
                if is_error {
                    turn.failed_reason = Some(
                        result_text
                            .clone()
                            .unwrap_or_else(|| "The SDK returned an error result.".to_string()),
                    );
                }
                turn.final_result = result_text;
                break;
            }
            "session.error" => {
                let message = event
                    .get("error")
                    .and_then(serde_json::Value::as_str)
                    .unwrap_or("SDK bridge failed.");
                turn.failed_reason = Some(message.to_string());
                break;
            }
            _ => {}
        }
    }

    Ok(())
}

fn run_agent_runtime_bridge_turn(
    bridge_session_id: &str,
    route: &TurnRoute,
    prepared: &PreparedTurnContext,
    text: &str,
    config_dir_override: Option<&Path>,
    transient_allowed_terminal_scopes: &[TerminalAccessScope],
) -> Result<ClaudeSdkBridgeTurnResult, String> {
    let prompt = compose_claude_sdk_turn_prompt(route, prepared, text);
    let config_dir = config_dir_override
        .map(Path::to_path_buf)
        .or_else(default_native_bridge_config_dir);
    let gateway_backend = ChatRuntime::from_config_dir(config_dir.as_deref())
        .map_err(|error| {
            format!("failed to load GeeAgent chat runtime for the SDK gateway: {error}")
        })?
        .xenodia_gateway_backend()
        .map_err(|error| format!("failed to configure the Xenodia gateway backend: {error}"))?;

    let mut turn = ClaudeSdkBridgeTurnResult::default();
    let manager = AGENT_RUNTIME_BRIDGE_MANAGER
        .get_or_init(|| Mutex::new(AgentRuntimeBridgeManager::default()));
    let mut manager = manager.lock().map_err(|error| error.to_string())?;
    if !manager.sessions.contains_key(bridge_session_id) {
        let bridge = start_agent_runtime_bridge_process(
            bridge_session_id,
            route,
            prepared,
            config_dir.as_deref(),
            &gateway_backend,
        )?;
        manager
            .sessions
            .insert(bridge_session_id.to_string(), bridge);
    }
    let bridge = manager
        .sessions
        .get_mut(bridge_session_id)
        .ok_or_else(|| "SDK bridge session was not available after startup.".to_string())?;

    write_agent_runtime_bridge_command(
        &mut bridge.stdin,
        serde_json::json!({
            "type": "session.send",
            "sessionId": bridge_session_id,
            "content": prompt
        }),
    )?;
    collect_agent_runtime_bridge_events_until_pause_or_result(
        bridge,
        bridge_session_id,
        config_dir.as_deref(),
        transient_allowed_terminal_scopes,
        &mut turn,
    )?;

    Ok(turn)
}

fn resume_agent_runtime_bridge_approval(
    bridge_session_id: &str,
    bridge_request_id: &str,
    decision: TerminalAccessDecision,
) -> Result<ClaudeSdkBridgeTurnResult, String> {
    let manager = AGENT_RUNTIME_BRIDGE_MANAGER
        .get_or_init(|| Mutex::new(AgentRuntimeBridgeManager::default()));
    let mut manager = manager.lock().map_err(|error| error.to_string())?;
    let bridge = manager
        .sessions
        .get_mut(bridge_session_id)
        .ok_or_else(|| {
            "The paused SDK bridge session is no longer alive, so GeeAgent cannot resume this approval inside the same run.".to_string()
        })?;

    let mut turn = ClaudeSdkBridgeTurnResult::default();
    let (decision_value, message) = match decision {
        TerminalAccessDecision::Allow => ("allow", None),
        TerminalAccessDecision::Deny => (
            "deny",
            Some("GeeAgent terminal permission review denied this Bash request."),
        ),
    };
    write_agent_runtime_bridge_command(
        &mut bridge.stdin,
        serde_json::json!({
            "type": "session.approval",
            "sessionId": bridge_session_id,
            "requestId": bridge_request_id,
            "decision": decision_value,
            "message": message
        }),
    )?;
    collect_agent_runtime_bridge_events_until_pause_or_result(
        bridge,
        bridge_session_id,
        None,
        &[],
        &mut turn,
    )?;
    Ok(turn)
}

fn execution_session_id_for_conversation(conversation_id: &str) -> String {
    format!("session_{conversation_id}")
}

fn kernel_session_id_for_conversation(conversation_id: &str) -> String {
    format!("kernel_{conversation_id}")
}

fn kernel_surface_for_execution_surface(surface: ExecutionSurface) -> KernelSurfaceKind {
    match surface {
        ExecutionSurface::DesktopWorkspaceChat => KernelSurfaceKind::DesktopWorkspaceChat,
        ExecutionSurface::DesktopQuickInput => KernelSurfaceKind::DesktopQuickInput,
        ExecutionSurface::CliWorkspaceChat => KernelSurfaceKind::CliWorkspaceChat,
        ExecutionSurface::CliQuickInput => KernelSurfaceKind::CliQuickInput,
        ExecutionSurface::Automation => KernelSurfaceKind::Automation,
        ExecutionSurface::BackgroundAgent => KernelSurfaceKind::BackgroundAgent,
    }
}

fn tool_invocation_id_for_module_run(module_run_id: &str) -> String {
    format!("toolinv_{module_run_id}")
}

fn next_approval_request_id_for_task(store: &RuntimeStore, task_id: &str) -> String {
    let existing_count = store
        .approval_requests
        .iter()
        .filter(|approval| approval.task_id == task_id)
        .count();
    if existing_count == 0 {
        format!("apr_{task_id}")
    } else {
        format!("apr_{task_id}_{}", existing_count + 1)
    }
}

fn append_user_message_for_active_conversation(
    store: &mut RuntimeStore,
    surface: ExecutionSurface,
    content: &str,
) -> Result<(String, String), String> {
    let session_id = store
        .ensure_execution_session_for_active_conversation(surface)
        .ok_or_else(|| "active conversation not found".to_string())?;
    let message_id = user_message_id(store);
    let message = RuntimeConversationMessageRecord {
        message_id: message_id.clone(),
        role: "user".to_string(),
        content: content.to_string(),
        timestamp: current_timestamp_rfc3339(),
    };

    if let Some(active_conversation) = store.active_conversation_mut() {
        active_conversation.messages.push(message.clone());
        active_conversation.status = "active".to_string();
    }

    store.append_transcript_event(
        &session_id,
        TranscriptEventPayload::UserMessage {
            message_id: message_id.clone(),
            content: content.to_string(),
        },
    );

    Ok((session_id, message_id))
}

fn append_session_state_for_session(
    store: &mut RuntimeStore,
    session_id: &str,
    summary: impl Into<String>,
) {
    store.append_transcript_event(
        session_id,
        TranscriptEventPayload::SessionStateChanged {
            summary: summary.into(),
        },
    );
}

fn session_contains_tool_invocation(
    store: &RuntimeStore,
    session_id: &str,
    invocation_id: &str,
) -> bool {
    store.transcript_events.iter().any(|event| {
        event.session_id == session_id
            && matches!(
                &event.payload,
                TranscriptEventPayload::ToolInvocation { invocation }
                    if invocation.invocation_id == invocation_id
            )
    })
}

fn session_contains_tool_result(
    store: &RuntimeStore,
    session_id: &str,
    invocation_id: &str,
) -> bool {
    store.transcript_events.iter().any(|event| {
        event.session_id == session_id
            && matches!(
                &event.payload,
                TranscriptEventPayload::ToolResult {
                    invocation_id: result_invocation_id,
                    ..
                } if result_invocation_id == invocation_id
            )
    })
}

fn append_tool_result_for_existing_invocation(
    store: &mut RuntimeStore,
    session_id: &str,
    invocation_id: &str,
    status: ToolInvocationStatus,
    summary: Option<String>,
    error: Option<String>,
) {
    if !session_contains_tool_invocation(store, session_id, invocation_id)
        || session_contains_tool_result(store, session_id, invocation_id)
    {
        return;
    }

    store.append_transcript_event(
        session_id,
        TranscriptEventPayload::ToolResult {
            invocation_id: invocation_id.to_string(),
            status,
            summary,
            error,
            artifacts: Vec::new(),
        },
    );
}

fn begin_turn_replay(
    store: &mut RuntimeStore,
    surface: ExecutionSurface,
    user_content: &str,
) -> Result<TurnReplayCursor, String> {
    let (session_id, user_message_id) =
        append_user_message_for_active_conversation(store, surface.clone(), user_content)?;
    append_session_state_for_session(store, &session_id, turn_setup_summary(surface));
    Ok(TurnReplayCursor {
        session_id,
        user_message_id,
        step_count: 0,
    })
}

fn append_turn_step(cursor: &mut TurnReplayCursor, store: &mut RuntimeStore, detail: &str) {
    cursor.step_count = cursor.step_count.saturating_add(1);
    append_session_state_for_session(
        store,
        &cursor.session_id,
        turn_step_summary(cursor.step_count, detail),
    );
}

fn append_turn_steps(
    cursor: &mut TurnReplayCursor,
    store: &mut RuntimeStore,
    step_details: &[String],
) {
    for detail in step_details {
        append_turn_step(cursor, store, detail);
    }
}

fn finalize_turn_replay(store: &mut RuntimeStore, cursor: &TurnReplayCursor, reason: &str) {
    let step_count = cursor.step_count.max(1);
    append_session_state_for_session(
        store,
        &cursor.session_id,
        turn_finalize_summary(step_count, reason),
    );
}

fn append_assistant_message_for_active_conversation(
    store: &mut RuntimeStore,
    session_id: &str,
    content: &str,
) -> Result<String, String> {
    let message_id = assistant_message_id(store);
    let trimmed_content = content.trim().to_string();
    let message = RuntimeConversationMessageRecord {
        message_id: message_id.clone(),
        role: "assistant".to_string(),
        content: trimmed_content.clone(),
        timestamp: current_timestamp_rfc3339(),
    };

    if let Some(active_conversation) = store.active_conversation_mut() {
        active_conversation.messages.push(message);
        active_conversation.status = "active".to_string();
    } else {
        return Err("active conversation not found".to_string());
    }

    store.append_transcript_event(
        session_id,
        TranscriptEventPayload::AssistantMessage {
            message_id: message_id.clone(),
            content: trimmed_content,
        },
    );

    Ok(message_id)
}

fn active_execution_surface(store: &RuntimeStore, fallback: ExecutionSurface) -> ExecutionSurface {
    let session_id = execution_session_id_for_conversation(&store.active_conversation_id);
    store
        .execution_sessions
        .iter()
        .find(|session| session.session_id == session_id)
        .map(|session| session.surface.clone())
        .unwrap_or(fallback)
}

fn artifact_ref_from_envelope(artifact: &ArtifactEnvelope) -> ArtifactRef {
    ArtifactRef {
        artifact_id: artifact.artifact_id.clone(),
        artifact_type: artifact.artifact_type.clone(),
        title: artifact.title.clone(),
        payload_ref: artifact.payload_ref.clone(),
        inline_preview_summary: Some(artifact.summary.clone())
            .filter(|summary| !summary.is_empty()),
    }
}

fn tool_invocation_status_from_module_run_status(status: &ModuleRunStatus) -> ToolInvocationStatus {
    match status {
        ModuleRunStatus::Queued => ToolInvocationStatus::Queued,
        ModuleRunStatus::Running | ModuleRunStatus::WaitingReview => ToolInvocationStatus::Running,
        ModuleRunStatus::Completed => ToolInvocationStatus::Succeeded,
        ModuleRunStatus::Failed => ToolInvocationStatus::Failed,
        ModuleRunStatus::Cancelled => ToolInvocationStatus::Cancelled,
    }
}

#[cfg(test)]
fn append_first_party_trace_for_outcome(
    store: &mut RuntimeStore,
    cursor: &TurnReplayCursor,
    invocation_input: &str,
    outcome: &ExecutionOutcome,
) {
    let invocation_id = tool_invocation_id_for_module_run(&outcome.module_run.module_run_id);
    let final_status = tool_invocation_status_from_module_run_status(&outcome.module_run.status);
    let tool_name = format!(
        "{}.{}",
        outcome.module_run.module_id, outcome.module_run.capability_id
    );
    let artifacts = outcome
        .module_run
        .artifacts
        .iter()
        .map(artifact_ref_from_envelope)
        .collect::<Vec<_>>();

    store.append_transcript_event(
        &cursor.session_id,
        TranscriptEventPayload::ToolInvocation {
            invocation: ToolInvocation {
                invocation_id: invocation_id.clone(),
                session_id: cursor.session_id.clone(),
                originating_message_id: cursor.user_message_id.clone(),
                tool_name,
                input_summary: Some(summarize_prompt(invocation_input, 120)),
                status: ToolInvocationStatus::Running,
                approval_request_id: outcome.task_run.approval_request_id.clone(),
                created_at: "now".to_string(),
                updated_at: "now".to_string(),
            },
        },
    );

    store.append_transcript_event(
        &cursor.session_id,
        TranscriptEventPayload::ToolResult {
            invocation_id,
            status: final_status.clone(),
            summary: outcome.module_run.result_summary.clone(),
            error: matches!(
                final_status,
                ToolInvocationStatus::Failed | ToolInvocationStatus::Cancelled
            )
            .then(|| outcome.task_run.summary.clone()),
            artifacts,
        },
    );
}

fn append_control_resolution_trace_for_task(
    store: &mut RuntimeStore,
    surface: ExecutionSurface,
    task_id: &str,
    approval_request_id: Option<&str>,
    control_summary: &str,
    assistant_reply: &str,
    finalize_reason: &str,
    final_status: ToolInvocationStatus,
    error: Option<String>,
) -> Result<(), String> {
    let session_id = store
        .ensure_execution_session_for_active_conversation(surface)
        .ok_or_else(|| "active conversation not found".to_string())?;
    append_session_state_for_session(store, &session_id, control_summary.to_string());

    let module_trace = store
        .module_runs
        .iter()
        .find(|module_run| module_run.module_run.task_id == task_id)
        .map(|module_run| {
            let module_run = module_run.module_run.clone();
            let task = store
                .tasks
                .iter()
                .find(|task| task.task_id == task_id)
                .cloned();
            (module_run, task)
        });

    if let Some((module_run, task)) = module_trace {
        let invocation_id = tool_invocation_id_for_module_run(&module_run.module_run_id);
        if !session_contains_tool_invocation(store, &session_id, &invocation_id) {
            let originating_message_id = store
                .active_conversation()
                .and_then(|conversation| {
                    conversation
                        .messages
                        .iter()
                        .rev()
                        .find(|message| message.role == "user")
                        .map(|message| message.message_id.clone())
                })
                .unwrap_or_else(|| user_message_id(store));
            store.append_transcript_event(
                &session_id,
                TranscriptEventPayload::ToolInvocation {
                    invocation: ToolInvocation {
                        invocation_id: invocation_id.clone(),
                        session_id: session_id.clone(),
                        originating_message_id,
                        tool_name: format!("{}.{}", module_run.module_id, module_run.capability_id),
                        input_summary: task.as_ref().map(|task| summarize_prompt(&task.title, 120)),
                        status: ToolInvocationStatus::Running,
                        approval_request_id: approval_request_id.map(|value| value.to_string()),
                        created_at: "now".to_string(),
                        updated_at: "now".to_string(),
                    },
                },
            );
        }

        let artifacts = module_run
            .artifacts
            .iter()
            .map(artifact_ref_from_envelope)
            .collect::<Vec<_>>();
        store.append_transcript_event(
            &session_id,
            TranscriptEventPayload::ToolResult {
                invocation_id,
                status: final_status,
                summary: module_run.result_summary.clone(),
                error,
                artifacts,
            },
        );
    }

    append_assistant_message_for_active_conversation(store, &session_id, assistant_reply)?;
    append_session_state_for_session(store, &session_id, finalize_reason.to_string());
    Ok(())
}

#[cfg(test)]
#[allow(dead_code)]
fn default_structured_action_turn_steps() -> Vec<String> {
    vec![
        "interpreting the request and selecting a structured action to dispatch through the shared turn runner"
            .to_string(),
        "dispatching the structured action and writing its result back into the active run before deciding what to do next"
            .to_string(),
        "reading the structured action result inside the same run and deciding whether to finalize or leave a resumable interruption"
            .to_string(),
    ]
}

#[cfg(test)]
#[allow(dead_code)]
fn default_direct_reply_turn_steps() -> Vec<String> {
    vec!["generating a direct reply through the shared turn runner".to_string()]
}

#[cfg(test)]
#[allow(dead_code)]
fn default_clarification_turn_steps() -> Vec<String> {
    vec![
        "evaluating the request and surfacing the next clarification needed to continue safely"
            .to_string(),
    ]
}

#[cfg(test)]
fn record_first_party_turn_with_steps(
    store: &mut RuntimeStore,
    surface: ExecutionSurface,
    user_content: &str,
    step_details: &[String],
    assistant_reply: &str,
    outcome: &ExecutionOutcome,
    finalize_reason: &str,
) -> Result<(), String> {
    let mut cursor = begin_turn_replay(store, surface, user_content)?;
    append_turn_steps(&mut cursor, store, step_details);
    append_first_party_trace_for_outcome(store, &cursor, user_content, outcome);
    append_assistant_message_for_active_conversation(store, &cursor.session_id, assistant_reply)?;
    finalize_turn_replay(store, &cursor, finalize_reason);
    Ok(())
}

#[cfg(test)]
#[allow(dead_code)]
fn record_first_party_turn(
    store: &mut RuntimeStore,
    surface: ExecutionSurface,
    user_content: &str,
    assistant_reply: &str,
    outcome: &ExecutionOutcome,
) -> Result<(), String> {
    let step_details = default_structured_action_turn_steps();
    record_first_party_turn_with_steps(
        store,
        surface,
        user_content,
        &step_details,
        assistant_reply,
        outcome,
        "the structured action completed and its result was committed to the active run",
    )
}

fn record_clarification_turn_with_steps(
    store: &mut RuntimeStore,
    surface: ExecutionSurface,
    user_content: &str,
    step_details: &[String],
    assistant_reply: &str,
    finalize_reason: &str,
) -> Result<(), String> {
    let mut cursor = begin_turn_replay(store, surface, user_content)?;
    append_turn_steps(&mut cursor, store, step_details);
    append_assistant_message_for_active_conversation(store, &cursor.session_id, assistant_reply)?;
    finalize_turn_replay(store, &cursor, finalize_reason);
    Ok(())
}

#[cfg(test)]
#[allow(dead_code)]
fn record_clarification_turn(
    store: &mut RuntimeStore,
    surface: ExecutionSurface,
    user_content: &str,
    assistant_reply: &str,
) -> Result<(), String> {
    let step_details = default_clarification_turn_steps();
    record_clarification_turn_with_steps(
        store,
        surface,
        user_content,
        &step_details,
        assistant_reply,
        "clarification is required before GeeAgent can continue the run",
    )
}

fn snapshot_store_path(config_dir: &Path) -> PathBuf {
    config_dir.join("runtime-store.json")
}

fn load_persisted_store(snapshot_path: &Path) -> Result<Option<RuntimeStore>, String> {
    if !snapshot_path.exists() {
        return Ok(None);
    }

    let raw = fs::read_to_string(snapshot_path).map_err(|error| error.to_string())?;
    if let Ok(store) = serde_json::from_str::<RuntimeStore>(&raw) {
        return Ok(Some(store));
    }

    serde_json::from_str::<RuntimeSnapshot>(&raw)
        .map(RuntimeStore::from_snapshot)
        .map(Some)
        .map_err(|error| error.to_string())
}

fn persist_store_to_disk(store: &RuntimeStore, snapshot_path: &Path) -> Result<(), String> {
    if let Some(parent) = snapshot_path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }

    let raw = serde_json::to_string_pretty(store).map_err(|error| error.to_string())?;
    fs::write(snapshot_path, raw).map_err(|error| error.to_string())
}

fn chat_runtime_record_from_readiness(readiness: ChatReadiness) -> RuntimeChatRuntimeRecord {
    RuntimeChatRuntimeRecord {
        status: readiness.status,
        active_provider: readiness.active_provider,
        detail: readiness.detail,
    }
}

fn startup_chat_runtime_record_from_config_dir(
    config_dir: Option<&Path>,
) -> RuntimeChatRuntimeRecord {
    match ChatRuntime::from_config_dir(config_dir) {
        Ok(runtime) => chat_runtime_record_from_readiness(runtime.readiness()),
        Err(error) => RuntimeChatRuntimeRecord {
            status: "needs_setup".to_string(),
            active_provider: None,
            detail: error,
        },
    }
}

fn default_native_bridge_config_dir() -> Option<PathBuf> {
    if let Ok(override_dir) = std::env::var("GEEAGENT_CONFIG_DIR") {
        let trimmed = override_dir.trim();
        if !trimmed.is_empty() {
            return Some(PathBuf::from(trimmed));
        }
    }

    std::env::var_os("HOME").map(PathBuf::from).map(|home| {
        home.join("Library")
            .join("Application Support")
            .join("io.geeagent.desktop")
    })
}

fn resolve_native_bridge_config_dir(config_dir_override: Option<PathBuf>) -> Option<PathBuf> {
    config_dir_override.or_else(default_native_bridge_config_dir)
}

fn terminal_access_permissions_path(config_dir: &Path) -> PathBuf {
    config_dir.join("terminal-access.json")
}

fn runtime_security_preferences_path(config_dir: &Path) -> PathBuf {
    config_dir.join("runtime-security.json")
}

fn load_runtime_security_preferences(config_dir: Option<&Path>) -> RuntimeSecurityPreferences {
    let Some(config_dir) = config_dir else {
        return RuntimeSecurityPreferences::default();
    };
    let path = runtime_security_preferences_path(config_dir);
    let Ok(raw) = fs::read_to_string(&path) else {
        return RuntimeSecurityPreferences::default();
    };
    serde_json::from_str(&raw).unwrap_or_default()
}

fn persist_runtime_security_preferences(
    config_dir: Option<&Path>,
    preferences: &RuntimeSecurityPreferences,
) -> Result<(), String> {
    let Some(config_dir) = config_dir else {
        return Err(
            "GeeAgent config dir is unavailable, so runtime security preferences cannot be persisted."
                .to_string(),
        );
    };
    ensure_directory(config_dir)?;
    let path = runtime_security_preferences_path(config_dir);
    let raw = serde_json::to_string_pretty(preferences).map_err(|error| error.to_string())?;
    fs::write(&path, raw).map_err(|error| format!("failed to write `{}`: {error}", path.display()))
}

fn highest_authorization_enabled(config_dir: Option<&Path>) -> bool {
    load_runtime_security_preferences(config_dir).highest_authorization_enabled
}

fn load_terminal_access_permissions(config_dir: Option<&Path>) -> TerminalAccessPermissionsFile {
    let Some(config_dir) = config_dir else {
        return TerminalAccessPermissionsFile::default();
    };
    let path = terminal_access_permissions_path(config_dir);
    let Ok(raw) = fs::read_to_string(&path) else {
        return TerminalAccessPermissionsFile::default();
    };
    serde_json::from_str(&raw).unwrap_or_default()
}

fn persist_terminal_access_permissions(
    config_dir: Option<&Path>,
    permissions: &TerminalAccessPermissionsFile,
) -> Result<(), String> {
    let Some(config_dir) = config_dir else {
        return Err(
            "GeeAgent config dir is unavailable, so terminal permissions cannot be persisted."
                .to_string(),
        );
    };
    ensure_directory(config_dir)?;
    let path = terminal_access_permissions_path(config_dir);
    let raw = serde_json::to_string_pretty(permissions).map_err(|error| error.to_string())?;
    fs::write(&path, raw).map_err(|error| format!("failed to write `{}`: {error}", path.display()))
}

fn terminal_access_decision_for_scope(
    config_dir: Option<&Path>,
    scope: &TerminalAccessScope,
) -> Option<TerminalAccessDecision> {
    load_terminal_access_permissions(config_dir)
        .rules
        .into_iter()
        .find(|rule| &rule.scope == scope)
        .map(|rule| rule.decision)
}

fn terminal_access_rule_id(scope: &TerminalAccessScope) -> String {
    let canonical =
        serde_json::to_string(scope).unwrap_or_else(|_| terminal_access_label_for_scope(scope));
    let mut hasher = DefaultHasher::new();
    canonical.hash(&mut hasher);
    format!("terminal_access_{:016x}", hasher.finish())
}

fn runtime_terminal_access_rule_record(
    rule: &TerminalAccessRule,
) -> RuntimeTerminalAccessRuleRecord {
    let (kind, command, cwd) = match &rule.scope {
        TerminalAccessScope::ControlledTerminalPlan { .. } => {
            ("controlled_terminal_plan".to_string(), None, None)
        }
        TerminalAccessScope::SdkBridgeBash { command, cwd } => (
            "sdk_bridge_bash".to_string(),
            Some(command.clone()),
            cwd.clone(),
        ),
    };

    RuntimeTerminalAccessRuleRecord {
        rule_id: terminal_access_rule_id(&rule.scope),
        decision: match rule.decision {
            TerminalAccessDecision::Allow => "allow".to_string(),
            TerminalAccessDecision::Deny => "deny".to_string(),
        },
        kind,
        label: rule.label.clone(),
        command,
        cwd,
        updated_at: rule.updated_at.clone(),
    }
}

fn terminal_access_rule_records(config_dir: Option<&Path>) -> Vec<RuntimeTerminalAccessRuleRecord> {
    load_terminal_access_permissions(config_dir)
        .rules
        .iter()
        .map(runtime_terminal_access_rule_record)
        .collect()
}

fn delete_terminal_access_rule(config_dir: Option<&Path>, rule_id: &str) -> Result<(), String> {
    let trimmed_rule_id = rule_id.trim();
    if trimmed_rule_id.is_empty() {
        return Err("terminal permission rule id is required".to_string());
    }

    let mut permissions = load_terminal_access_permissions(config_dir);
    let original_count = permissions.rules.len();
    permissions
        .rules
        .retain(|rule| terminal_access_rule_id(&rule.scope) != trimmed_rule_id);

    if permissions.rules.len() == original_count {
        return Err(format!(
            "terminal permission rule `{trimmed_rule_id}` was not found"
        ));
    }

    persist_terminal_access_permissions(config_dir, &permissions)
}

fn upsert_terminal_access_rule(
    config_dir: Option<&Path>,
    scope: TerminalAccessScope,
    decision: TerminalAccessDecision,
    label: impl Into<String>,
) -> Result<(), String> {
    let mut permissions = load_terminal_access_permissions(config_dir);
    let label = label.into();

    if let Some(existing) = permissions
        .rules
        .iter_mut()
        .find(|rule| rule.scope == scope)
    {
        existing.decision = decision;
        existing.label = label;
        existing.updated_at = current_timestamp_rfc3339();
    } else {
        permissions.rules.insert(
            0,
            TerminalAccessRule {
                scope,
                decision,
                label,
                updated_at: current_timestamp_rfc3339(),
            },
        );
    }

    persist_terminal_access_permissions(config_dir, &permissions)
}

fn controlled_terminal_scope(request: &ControlledTerminalRequest) -> TerminalAccessScope {
    let signature =
        serde_json::to_string(&request.steps).unwrap_or_else(|_| request.plan_summary.clone());
    TerminalAccessScope::ControlledTerminalPlan { signature }
}

fn sdk_bridge_bash_scope(command: &str, cwd: Option<&str>) -> TerminalAccessScope {
    TerminalAccessScope::SdkBridgeBash {
        command: command.trim().to_string(),
        cwd: cwd
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty()),
    }
}

fn bridge_bash_request_from_input(input: &serde_json::Value) -> Option<(String, Option<String>)> {
    let command = input
        .get("command")
        .and_then(serde_json::Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())?
        .to_string();
    let cwd = input
        .get("cwd")
        .or_else(|| input.get("workdir"))
        .or_else(|| input.get("working_directory"))
        .and_then(serde_json::Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string);
    Some((command, cwd))
}

fn terminal_access_label_for_scope(scope: &TerminalAccessScope) -> String {
    match scope {
        TerminalAccessScope::ControlledTerminalPlan { signature } => {
            format!(
                "controlled terminal plan: {}",
                summarize_prompt(signature, 120)
            )
        }
        TerminalAccessScope::SdkBridgeBash { command, cwd } => {
            let command_summary = summarize_prompt(command, 120);
            match cwd {
                Some(cwd) if !cwd.is_empty() => format!("{command_summary} @ {cwd}"),
                _ => command_summary,
            }
        }
    }
}

fn default_persona_assets_root() -> Option<PathBuf> {
    if let Ok(override_dir) = std::env::var("GEEAGENT_PERSONAS_ROOT") {
        let trimmed = override_dir.trim();
        if !trimmed.is_empty() {
            return Some(PathBuf::from(trimmed));
        }
    }

    std::env::var_os("HOME").map(PathBuf::from).map(|home| {
        home.join("Library")
            .join("Application Support")
            .join("GeeAgent")
            .join("Personas")
    })
}

fn resolve_persona_assets_root(config_dir_override: Option<&Path>) -> Option<PathBuf> {
    config_dir_override
        .map(|path| path.join("Personas"))
        .or_else(default_persona_assets_root)
}

fn profile_workspace_root(
    profile: &AgentProfile,
    persona_assets_root: Option<&Path>,
) -> Option<PathBuf> {
    match profile.source {
        ProfileSource::FirstParty => None,
        ProfileSource::UserCreated | ProfileSource::ModulePack => {
            persona_assets_root.map(|root| root.join(&profile.id))
        }
    }
}

fn bridge_file_entry(path: &Path) -> RuntimeAgentProfileFileEntryRecord {
    let title = path
        .file_name()
        .and_then(|name| name.to_str())
        .map(|name| name.to_string())
        .unwrap_or_else(|| path.to_string_lossy().to_string());
    RuntimeAgentProfileFileEntryRecord {
        title,
        path: path.to_string_lossy().to_string(),
    }
}

fn collect_workspace_files(
    root: &Path,
    relative_dir: &str,
) -> Vec<RuntimeAgentProfileFileEntryRecord> {
    let directory = root.join(relative_dir);
    let mut files = Vec::new();
    if !directory.is_dir() {
        return files;
    }

    let mut stack = vec![directory];
    while let Some(dir) = stack.pop() {
        let entries = match fs::read_dir(&dir) {
            Ok(entries) => entries,
            Err(_) => continue,
        };

        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                stack.push(path);
                continue;
            }
            files.push(bridge_file_entry(&path));
        }
    }

    files.sort_by(|a, b| a.path.cmp(&b.path));
    files
}

fn workspace_file(root: &Path, name: &str) -> Option<PathBuf> {
    let path = root.join(name);
    path.is_file().then_some(path)
}

fn runtime_agent_profile_file_state(
    profile: &AgentProfile,
    config_dir: Option<&Path>,
    persona_assets_root: Option<&Path>,
) -> RuntimeAgentProfileFileStateRecord {
    let workspace_root =
        profile_workspace_root(profile, persona_assets_root).filter(|path| path.exists());
    let manifest_path = workspace_root
        .as_ref()
        .map(|root| root.join("agent.json"))
        .filter(|path| path.is_file());
    let identity_prompt_path = workspace_root
        .as_ref()
        .map(|root| root.join("identity-prompt.md"))
        .filter(|path| path.is_file());
    let soul_path = workspace_root
        .as_ref()
        .and_then(|root| workspace_file(root, "soul.md"));
    let playbook_path = workspace_root
        .as_ref()
        .and_then(|root| workspace_file(root, "playbook.md"));
    let tools_context_path = workspace_root
        .as_ref()
        .and_then(|root| workspace_file(root, "tools.md"));
    let memory_seed_path = workspace_root
        .as_ref()
        .and_then(|root| workspace_file(root, "memory.md"));
    let heartbeat_path = workspace_root
        .as_ref()
        .and_then(|root| workspace_file(root, "heartbeat.md"));

    let visual_files = workspace_root.as_ref().map_or_else(Vec::new, |root| {
        let mut files = collect_workspace_files(root, "appearance");
        if files.is_empty() {
            files.extend(collect_workspace_files(root, "image"));
            files.extend(collect_workspace_files(root, "video"));
            files.extend(collect_workspace_files(root, "live2d"));
        }
        files.sort_by(|a, b| a.path.cmp(&b.path));
        files
    });

    let supplemental_files = workspace_root.as_ref().map_or_else(Vec::new, |root| {
        ["README.md", "LICENSE"]
            .iter()
            .map(|name| root.join(name))
            .filter(|path| path.is_file())
            .map(|path| bridge_file_entry(&path))
            .collect()
    });

    let can_reload = !matches!(profile.source, ProfileSource::FirstParty)
        && manifest_path.is_some()
        && workspace_root.is_some();
    let can_delete = !matches!(profile.source, ProfileSource::FirstParty)
        && (workspace_root.is_some()
            || config_dir
                .map(|dir| {
                    dir.join("agents")
                        .join(format!("{}.json", profile.id))
                        .is_file()
                })
                .unwrap_or(false));

    RuntimeAgentProfileFileStateRecord {
        workspace_root_path: workspace_root.map(|path| path.to_string_lossy().to_string()),
        manifest_path: manifest_path.map(|path| path.to_string_lossy().to_string()),
        identity_prompt_path: identity_prompt_path.map(|path| path.to_string_lossy().to_string()),
        soul_path: soul_path.map(|path| path.to_string_lossy().to_string()),
        playbook_path: playbook_path.map(|path| path.to_string_lossy().to_string()),
        tools_context_path: tools_context_path.map(|path| path.to_string_lossy().to_string()),
        memory_seed_path: memory_seed_path.map(|path| path.to_string_lossy().to_string()),
        heartbeat_path: heartbeat_path.map(|path| path.to_string_lossy().to_string()),
        visual_files,
        supplemental_files,
        can_reload,
        can_delete,
    }
}

fn bridge_agent_profile_record(
    profile: &AgentProfile,
    config_dir: Option<&Path>,
    persona_assets_root: Option<&Path>,
) -> RuntimeBridgeAgentProfileRecord {
    RuntimeBridgeAgentProfileRecord {
        id: profile.id.clone(),
        name: profile.name.clone(),
        tagline: profile.tagline.clone(),
        personality_prompt: profile.personality_prompt.clone(),
        appearance: profile.appearance.clone(),
        skills: profile.skills.clone(),
        allowed_tool_ids: profile.allowed_tool_ids.clone(),
        source: profile.source.clone(),
        version: profile.version.clone(),
        file_state: runtime_agent_profile_file_state(profile, config_dir, persona_assets_root),
    }
}

fn bridge_snapshot(
    snapshot: RuntimeSnapshot,
    config_dir: Option<&Path>,
    persona_assets_root: Option<&Path>,
) -> RuntimeBridgeSnapshot {
    let active_agent_profile = bridge_agent_profile_record(
        &snapshot.active_agent_profile,
        config_dir,
        persona_assets_root,
    );
    let agent_profiles = snapshot
        .agent_profiles
        .iter()
        .map(|profile| bridge_agent_profile_record(profile, config_dir, persona_assets_root))
        .collect();

    RuntimeBridgeSnapshot {
        quick_input_hint: snapshot.quick_input_hint,
        quick_reply: snapshot.quick_reply,
        context_budget: snapshot.context_budget,
        active_agent_profile,
        agent_profiles,
        interaction_capabilities: snapshot.interaction_capabilities,
        last_request_outcome: snapshot.last_request_outcome,
        last_run_state: snapshot.last_run_state,
        chat_runtime: snapshot.chat_runtime,
        conversations: snapshot.conversations,
        active_conversation: snapshot.active_conversation,
        automations: snapshot.automations,
        module_runs: snapshot.module_runs,
        execution_sessions: snapshot.execution_sessions,
        kernel_sessions: snapshot.kernel_sessions,
        transcript_events: snapshot.transcript_events,
        tasks: snapshot.tasks,
        approval_requests: snapshot.approval_requests,
        terminal_access_rules: terminal_access_rule_records(config_dir),
        security_preferences: load_runtime_security_preferences(config_dir),
        workspace_focus: snapshot.workspace_focus,
        workspace_runtime: snapshot.workspace_runtime,
    }
}

fn ensure_directory(path: &Path) -> Result<(), String> {
    fs::create_dir_all(path)
        .map_err(|error| format!("failed to create `{}`: {error}", path.display()))
}

fn copy_dir_contents(from: &Path, to: &Path) -> Result<(), String> {
    ensure_directory(to)?;
    for entry in fs::read_dir(from)
        .map_err(|error| format!("failed to read `{}`: {error}", from.display()))?
    {
        let entry = entry.map_err(|error| error.to_string())?;
        let source = entry.path();
        let destination = to.join(entry.file_name());
        if source.is_dir() {
            copy_dir_contents(&source, &destination)?;
        } else {
            if let Some(parent) = destination.parent() {
                ensure_directory(parent)?;
            }
            fs::copy(&source, &destination).map_err(|error| {
                format!(
                    "failed to copy `{}` to `{}`: {error}",
                    source.display(),
                    destination.display()
                )
            })?;
        }
    }
    Ok(())
}

fn run_ditto_extract(zip_path: &Path, destination_dir: &Path) -> Result<(), String> {
    let output = Command::new("/usr/bin/ditto")
        .arg("-x")
        .arg("-k")
        .arg(zip_path)
        .arg(destination_dir)
        .output()
        .map_err(|error| {
            format!(
                "failed to spawn ditto for `{}`: {error}",
                zip_path.display()
            )
        })?;

    if output.status.success() {
        return Ok(());
    }

    let stderr = String::from_utf8_lossy(&output.stderr);
    Err(format!(
        "ditto failed while extracting `{}`: {}",
        zip_path.display(),
        stderr.trim()
    ))
}

fn normalized_pack_root(root: &Path) -> Result<PathBuf, String> {
    if root.join("agent.json").is_file() {
        return Ok(root.to_path_buf());
    }

    fn ignorable_pack_entry(path: &Path) -> bool {
        path.file_name()
            .and_then(|name| name.to_str())
            .map(|name| name == "__MACOSX" || name == ".DS_Store" || name.starts_with('.'))
            .unwrap_or(false)
    }

    let mut child_dirs = fs::read_dir(root)
        .map_err(|error| format!("failed to read `{}`: {error}", root.display()))?
        .filter_map(|entry| entry.ok().map(|entry| entry.path()))
        .filter(|path| !ignorable_pack_entry(path))
        .filter(|path| path.is_dir())
        .collect::<Vec<_>>();
    child_dirs.sort();

    if child_dirs.len() == 1 && child_dirs[0].join("agent.json").is_file() {
        return Ok(child_dirs.remove(0));
    }

    Err(format!(
        "expected `{}` to be an agent definition root or contain a single wrapped agent definition directory",
        root.display()
    ))
}

enum PreparedPackSource {
    Directory(PathBuf),
    Extracted {
        _temp_dir: tempfile::TempDir,
        root: PathBuf,
    },
}

impl PreparedPackSource {
    fn root(&self) -> &Path {
        match self {
            Self::Directory(root) => root,
            Self::Extracted { root, .. } => root,
        }
    }
}

fn prepare_pack_source(path: &Path) -> Result<PreparedPackSource, String> {
    if path.is_dir() {
        return Ok(PreparedPackSource::Directory(normalized_pack_root(path)?));
    }

    let is_zip = path
        .extension()
        .and_then(|extension| extension.to_str())
        .map(|extension| extension.eq_ignore_ascii_case("zip"))
        .unwrap_or(false);
    if !is_zip {
        return Err(format!(
            "agent definition import expects a directory or `.zip` archive, got `{}`",
            path.display()
        ));
    }

    let temp_dir = tempfile::tempdir()
        .map_err(|error| format!("failed to create temp dir for zip import: {error}"))?;
    run_ditto_extract(path, temp_dir.path())?;
    let normalized_root = normalized_pack_root(temp_dir.path())?;
    Ok(PreparedPackSource::Extracted {
        _temp_dir: temp_dir,
        root: normalized_root,
    })
}

fn materialize_pack_workspace(
    validated: &ValidatedAgentPack,
    persona_assets_root: &Path,
) -> Result<PathBuf, String> {
    let destination = persona_assets_root.join(&validated.runtime_profile.id);
    if destination.exists() {
        return Err(format!(
            "agent profile workspace `{}` already exists at `{}`",
            validated.runtime_profile.id,
            destination.display()
        ));
    }
    ensure_directory(&destination)?;
    copy_dir_contents(&validated.root, &destination)?;
    Ok(destination)
}

fn load_runtime_profile_from_workspace(
    workspace_root: &Path,
    forced_source: ProfileSource,
) -> Result<AgentProfile, String> {
    let validated = validate_pack(workspace_root).map_err(format_pack_error)?;
    let mut profile = validated.runtime_profile;
    profile.source = forced_source;
    Ok(profile)
}

fn write_installed_agent_profile(
    config_dir: &Path,
    profile: &AgentProfile,
    overwrite: bool,
) -> Result<PathBuf, String> {
    let agents_dir = config_dir.join("agents");
    ensure_directory(&agents_dir)?;
    let destination = agents_dir.join(format!("{}.json", profile.id));
    if destination.exists() && !overwrite {
        return Err(format!(
            "agent profile `{}` is already installed at `{}`",
            profile.id,
            destination.display()
        ));
    }
    let raw = serde_json::to_string_pretty(profile).map_err(|error| error.to_string())?;
    fs::write(&destination, raw)
        .map_err(|error| format!("failed to write `{}`: {error}", destination.display()))?;
    Ok(destination)
}

fn load_native_bridge_store(
    config_dir_override: Option<PathBuf>,
) -> Result<(RuntimeStore, Option<PathBuf>, Option<PathBuf>), String> {
    let config_dir = resolve_native_bridge_config_dir(config_dir_override);
    let snapshot_path = config_dir.as_deref().map(snapshot_store_path);
    let mut store = match snapshot_path.as_ref() {
        Some(path) => match load_persisted_store(path) {
            Ok(Some(store)) => store,
            Ok(None) => default_runtime_store(),
            Err(error) => {
                log::warn!("failed to load persisted native bridge store: {error}");
                default_runtime_store()
            }
        },
        None => default_runtime_store(),
    };

    ensure_workspace_runtime_catalog(&mut store);
    store.refresh_agent_profiles(config_dir.as_deref());
    store.chat_runtime = startup_chat_runtime_record_from_config_dir(config_dir.as_deref());
    store.sync_conversation_statuses();

    Ok((store, config_dir, snapshot_path))
}

fn persist_native_bridge_store(
    store: &RuntimeStore,
    snapshot_path: Option<&PathBuf>,
) -> Result<(), String> {
    if let Some(snapshot_path) = snapshot_path {
        persist_store_to_disk(store, snapshot_path)?;
    }

    Ok(())
}

fn format_pack_error(error: PackError) -> String {
    format!("[{}] {}", error.code(), error)
}

fn install_agent_pack_into_store(
    pack_source: &Path,
    config_dir: &Path,
    persona_assets_root: &Path,
    store: &mut RuntimeStore,
) -> Result<RuntimeSnapshot, String> {
    let prepared = prepare_pack_source(pack_source)?;
    let validated = validate_pack(prepared.root()).map_err(format_pack_error)?;
    let workspace_root = materialize_pack_workspace(&validated, persona_assets_root)?;
    let installed_profile =
        load_runtime_profile_from_workspace(&workspace_root, ProfileSource::ModulePack)?;
    write_installed_agent_profile(config_dir, &installed_profile, false)?;
    store.refresh_agent_profiles(Some(config_dir));
    Ok(store.snapshot())
}

fn reload_agent_profile_into_store(
    profile_id: &str,
    config_dir: &Path,
    persona_assets_root: &Path,
    store: &mut RuntimeStore,
) -> Result<RuntimeSnapshot, String> {
    let existing_profile = store
        .agent_profiles
        .iter()
        .find(|profile| profile.id == profile_id)
        .cloned()
        .ok_or_else(|| format!("unknown agent profile `{profile_id}`"))?;
    if matches!(existing_profile.source, ProfileSource::FirstParty) {
        return Err(format!(
            "agent profile `{profile_id}` is bundled and cannot be reloaded"
        ));
    }

    let workspace_root = persona_assets_root.join(profile_id);
    if !workspace_root.is_dir() {
        return Err(format!(
            "agent profile `{profile_id}` has no local workspace at `{}`",
            workspace_root.display()
        ));
    }

    let reloaded_profile =
        load_runtime_profile_from_workspace(&workspace_root, existing_profile.source)?;
    if reloaded_profile.id != profile_id {
        return Err(format!(
            "agent profile workspace `{}` now declares id `{}`; rename the folder or restore the original id before reloading",
            workspace_root.display(),
            reloaded_profile.id
        ));
    }

    write_installed_agent_profile(config_dir, &reloaded_profile, true)?;
    store.refresh_agent_profiles(Some(config_dir));
    Ok(store.snapshot())
}

fn delete_agent_profile_from_store(
    profile_id: &str,
    config_dir: &Path,
    persona_assets_root: &Path,
    store: &mut RuntimeStore,
) -> Result<RuntimeSnapshot, String> {
    let existing_profile = store
        .agent_profiles
        .iter()
        .find(|profile| profile.id == profile_id)
        .cloned()
        .ok_or_else(|| format!("unknown agent profile `{profile_id}`"))?;
    if matches!(existing_profile.source, ProfileSource::FirstParty) {
        return Err(format!(
            "agent profile `{profile_id}` is bundled and cannot be deleted"
        ));
    }

    let runtime_profile_path = config_dir.join("agents").join(format!("{profile_id}.json"));
    if runtime_profile_path.is_file() {
        fs::remove_file(&runtime_profile_path).map_err(|error| {
            format!(
                "failed to delete runtime profile `{}`: {error}",
                runtime_profile_path.display()
            )
        })?;
    }

    let workspace_root = persona_assets_root.join(profile_id);
    if workspace_root.exists() {
        fs::remove_dir_all(&workspace_root).map_err(|error| {
            format!(
                "failed to delete agent workspace `{}`: {error}",
                workspace_root.display()
            )
        })?;
    }

    if store.active_agent_profile_id == profile_id {
        store.active_agent_profile_id = "gee".to_string();
    }
    store.refresh_agent_profiles(Some(config_dir));
    Ok(store.snapshot())
}

fn user_message_id(store: &RuntimeStore) -> String {
    format!(
        "msg_user_{:02}",
        store
            .active_conversation()
            .map(|conversation| conversation.messages.len())
            .unwrap_or_default()
            .saturating_add(1)
    )
}

fn assistant_message_id(store: &RuntimeStore) -> String {
    format!(
        "msg_assistant_{:02}",
        store
            .active_conversation()
            .map(|conversation| conversation.messages.len())
            .unwrap_or_default()
            .saturating_add(2)
    )
}

fn quick_task_id(store: &RuntimeStore) -> String {
    format!("task_quick_{:02}", store.tasks.len().saturating_add(1))
}

fn quick_module_run_id(store: &RuntimeStore) -> String {
    format!("run_quick_{:02}", store.module_runs.len().saturating_add(1))
}

#[cfg(test)]
fn detect_first_party_execution_from_store(
    store: &RuntimeStore,
    message: &str,
) -> Option<FirstPartyRoutingDecision> {
    let recent_user_messages = store
        .active_conversation()
        .map(|conversation| {
            conversation
                .messages
                .iter()
                .filter(|message_record| message_record.role == "user")
                .map(|message_record| message_record.content.clone())
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let focused_task_title = store
        .workspace_focus
        .task_id
        .as_ref()
        .and_then(|task_id| store.tasks.iter().find(|task| &task.task_id == task_id))
        .map(|task| task.title.as_str());

    classify_first_party_execution(&FirstPartyDetectionContext {
        message,
        focused_task_id: store.workspace_focus.task_id.as_deref(),
        focused_task_title,
        recent_user_messages: &recent_user_messages,
    })
}

fn active_conversation_id(store: &RuntimeStore) -> Option<String> {
    store
        .active_conversation()
        .map(|conversation| conversation.conversation_id.clone())
}

#[cfg(test)]
fn looks_like_runtime_facts_time_request(text: &str) -> bool {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return false;
    }

    let lowered = trimmed.to_ascii_lowercase();
    let explicit_patterns = [
        "现在几点",
        "现在是几点",
        "当前时间",
        "现在时间",
        "现在几号",
        "今天几号",
        "现在日期",
    ];
    explicit_patterns
        .iter()
        .any(|pattern| trimmed.contains(pattern))
        || lowered.contains("current time")
        || lowered.contains("what time")
        || lowered.contains("current date")
        || lowered.contains("what date")
}

#[cfg(test)]
fn grounded_runtime_fact_reply(
    store: &RuntimeStore,
    surface: ExecutionSurface,
    profile: &AgentProfile,
) -> GroundedRuntimeFactReplyDecision {
    let _ = profile;
    let facts = runtime_facts_for_surface(surface);
    let quick_reply = format!("Current local time: {}.", facts.local_time);
    let run_state = runtime_run_state(
        active_conversation_id(store),
        "idle",
        "runtime_fact_reply",
        "The request was answered directly from turn setup runtime facts without dispatching a separate tool.",
        false,
        None,
        None,
    );

    GroundedRuntimeFactReplyDecision {
        quick_reply,
        run_state,
    }
}

fn prepare_turn_context(store: &RuntimeStore, route: TurnRoute, text: &str) -> PreparedTurnContext {
    let active_agent_profile = resolved_active_agent_profile(store);
    let workspace_messages = matches!(route.mode, TurnMode::WorkspaceMessage)
        .then(|| workspace_messages_from_store(store))
        .unwrap_or_default();

    PreparedTurnContext {
        active_agent_profile,
        workspace_messages,
        should_reuse_active_conversation: should_reuse_active_conversation(store, text),
    }
}

fn runtime_run_state(
    conversation_id: Option<String>,
    status: impl Into<String>,
    stop_reason: impl Into<String>,
    detail: impl Into<String>,
    resumable: bool,
    task_id: Option<String>,
    module_run_id: Option<String>,
) -> RuntimeRunStateRecord {
    RuntimeRunStateRecord {
        conversation_id,
        status: status.into(),
        stop_reason: stop_reason.into(),
        detail: detail.into(),
        resumable,
        task_id,
        module_run_id,
    }
}

#[cfg(test)]
fn looks_like_run_status_follow_up(text: &str) -> bool {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return false;
    }

    let lowered = trimmed.to_ascii_lowercase();
    let patterns = [
        "结果如何",
        "结果呢",
        "怎么样了",
        "进展如何",
        "有结果吗",
        "查到了吗",
        "how did it go",
        "what happened",
        "any result",
        "status",
        "result?",
        "how's it going",
    ];

    patterns.iter().any(|pattern| {
        if pattern.is_ascii() {
            lowered.contains(pattern)
        } else {
            trimmed.contains(pattern)
        }
    })
}

#[cfg(test)]
fn describe_task_status_for_follow_up(
    task: &RuntimeTaskRecord,
    module_run_id: Option<&str>,
) -> (String, String, bool) {
    match task.status.as_str() {
        "queued" | "running" => (
            format!(
                "The previous run is still in progress: {}. Current stage: {}.",
                task.title, task.current_stage
            ),
            format!("Run still in progress: {}.", task.summary),
            true,
        ),
        "waiting_review" => (
            format!(
                "The previous run is waiting for approval: {}. Review it to continue.",
                task.title
            ),
            "Run is paused for approval.".to_string(),
            true,
        ),
        "waiting_input" => (
            format!(
                "The previous run is waiting for more input: {}. {}",
                task.title, task.summary
            ),
            "Run is waiting for more input.".to_string(),
            true,
        ),
        "completed" => (
            format!(
                "The previous run completed: {}. {}",
                task.title, task.summary
            ),
            module_run_id
                .map(|module_run_id| format!("Completed run {module_run_id}."))
                .unwrap_or_else(|| "Completed the previous run.".to_string()),
            false,
        ),
        "failed" | "cancelled" => (
            format!(
                "The previous run did not complete successfully: {}. {}",
                task.title, task.summary
            ),
            "Previous run did not complete successfully.".to_string(),
            false,
        ),
        other => (
            format!(
                "The previous run is currently {}: {}. {}",
                other, task.title, task.summary
            ),
            format!("Run status: {other}."),
            false,
        ),
    }
}

#[cfg(test)]
fn active_kernel_session(store: &RuntimeStore) -> Option<&AgentSessionRuntime> {
    let conversation_id = store.active_conversation()?.conversation_id.clone();
    let session_id = kernel_session_id_for_conversation(&conversation_id);
    store
        .kernel_sessions
        .iter()
        .find(|session| session.session.session_id == session_id)
}

#[cfg(test)]
fn latest_kernel_run_for_active_conversation(
    store: &RuntimeStore,
) -> Option<(&AgentSessionRuntime, &KernelRun)> {
    let session = active_kernel_session(store)?;
    let run_id = session.session.current_run_id.clone().or_else(|| {
        session
            .event_log
            .events()
            .iter()
            .rev()
            .find_map(|event| event.run_id.clone())
    })?;
    session.runs.get(&run_id).map(|run| (session, run))
}

#[cfg(test)]
fn kernel_task_id_for_run(run: &KernelRun) -> Option<String> {
    run.run_id.strip_prefix("krun_").map(|id| id.to_string())
}

#[cfg(test)]
fn module_run_id_for_task(store: &RuntimeStore, task_id: &str) -> Option<String> {
    store
        .module_runs
        .iter()
        .find(|module_run| module_run.module_run.task_id == task_id)
        .map(|module_run| module_run.module_run.module_run_id.clone())
}

#[cfg(test)]
fn kernel_run_status_follow_up(store: &RuntimeStore) -> Option<RunStatusFollowUpDecision> {
    let active_conversation_id = active_conversation_id(store);
    let (session, run) = latest_kernel_run_for_active_conversation(store)?;
    let task_id = kernel_task_id_for_run(run);
    let module_run_id = task_id
        .as_deref()
        .and_then(|task_id| module_run_id_for_task(store, task_id));

    if let Some(task_id) = task_id.as_deref() {
        if let Some(task) = store.tasks.iter().find(|task| task.task_id == task_id) {
            let (assistant_reply, _quick_reply, resumable) =
                describe_task_status_for_follow_up(task, module_run_id.as_deref());
            return Some(RunStatusFollowUpDecision {
                assistant_reply,
                run_state: runtime_run_state(
                    active_conversation_id,
                    task.status.clone(),
                    run.stop_reason
                        .clone()
                        .unwrap_or_else(|| "kernel_task_projection".to_string()),
                    task.summary.clone(),
                    resumable,
                    Some(task.task_id.clone()),
                    module_run_id,
                ),
            });
        }
    }

    let interruption = run
        .interrupt_id
        .as_deref()
        .and_then(|interrupt_id| session.interruptions.get(interrupt_id));

    let (status, stop_reason, detail, assistant_reply, _quick_reply, resumable) = match run.status {
        KernelRunStatus::Queued | KernelRunStatus::Running => (
            "running".to_string(),
            run.stop_reason
                .clone()
                .unwrap_or_else(|| "kernel_run_in_progress".to_string()),
            "The current kernel run is still in progress.".to_string(),
            "The previous run is still in progress, and I am continuing the same run.".to_string(),
            "Kernel run still in progress.".to_string(),
            true,
        ),
        KernelRunStatus::Interrupted => match interruption.map(|entry| &entry.reason) {
            Some(runtime_kernel::RunInterruptReason::ApprovalRequired) => (
                "waiting_review".to_string(),
                "kernel_run_waiting_review".to_string(),
                "The current kernel run is paused for approval.".to_string(),
                "The previous run is paused for approval. Once you approve it, I will continue the same run.".to_string(),
                "Kernel run paused for approval.".to_string(),
                true,
            ),
            Some(runtime_kernel::RunInterruptReason::UserInputRequired) => (
                "waiting_input".to_string(),
                "kernel_run_waiting_input".to_string(),
                "The current kernel run is waiting for more user input.".to_string(),
                "The previous run is waiting for more input, and I will continue from the same run.".to_string(),
                "Kernel run waiting for input.".to_string(),
                true,
            ),
            _ => (
                "interrupted".to_string(),
                "kernel_run_interrupted".to_string(),
                "The current kernel run is interrupted.".to_string(),
                "The previous run is currently paused and has not been finalized yet.".to_string(),
                "Kernel run interrupted.".to_string(),
                true,
            ),
        },
        KernelRunStatus::Completed => (
            "completed".to_string(),
            run.stop_reason
                .clone()
                .unwrap_or_else(|| "kernel_run_completed".to_string()),
            "The previous kernel run completed.".to_string(),
            "The previous run completed.".to_string(),
            "Kernel run completed.".to_string(),
            false,
        ),
        KernelRunStatus::Failed => (
            "failed".to_string(),
            run.stop_reason
                .clone()
                .unwrap_or_else(|| "kernel_run_failed".to_string()),
            run.error_summary
                .clone()
                .unwrap_or_else(|| "The previous kernel run failed.".to_string()),
            format!(
                "The previous run failed: {}",
                summarize_prompt(
                    run.error_summary.as_deref().unwrap_or("No additional error summary."),
                    180
                )
            ),
            "Kernel run failed.".to_string(),
            false,
        ),
        KernelRunStatus::Cancelled => (
            "cancelled".to_string(),
            run.stop_reason
                .clone()
                .unwrap_or_else(|| "kernel_run_cancelled".to_string()),
            "The previous kernel run was cancelled.".to_string(),
            "The previous run was cancelled.".to_string(),
            "Kernel run cancelled.".to_string(),
            false,
        ),
    };

    Some(RunStatusFollowUpDecision {
        assistant_reply,
        run_state: runtime_run_state(
            active_conversation_id,
            status,
            stop_reason,
            detail,
            resumable,
            task_id,
            module_run_id,
        ),
    })
}

#[cfg(test)]
fn detect_run_status_follow_up(
    store: &RuntimeStore,
    text: &str,
) -> Option<RunStatusFollowUpDecision> {
    if !looks_like_run_status_follow_up(text) {
        return None;
    }

    if let Some(follow_up) = kernel_run_status_follow_up(store) {
        return Some(follow_up);
    }

    let active_conversation_id = active_conversation_id(store);

    if let Some(run_state) = store
        .last_run_state
        .clone()
        .filter(|run_state| run_state.conversation_id == active_conversation_id)
    {
        if let Some(task_id) = run_state.task_id.as_deref() {
            if let Some(task) = store.tasks.iter().find(|task| task.task_id == task_id) {
                let (assistant_reply, _quick_reply, resumable) =
                    describe_task_status_for_follow_up(task, run_state.module_run_id.as_deref());
                return Some(RunStatusFollowUpDecision {
                    assistant_reply,
                    run_state: runtime_run_state(
                        active_conversation_id.clone(),
                        task.status.clone(),
                        run_state.stop_reason,
                        task.summary.clone(),
                        resumable,
                        Some(task.task_id.clone()),
                        run_state.module_run_id,
                    ),
                });
            }
        }

        if run_state.stop_reason == "direct_chat_reply" {
            return Some(RunStatusFollowUpDecision {
                assistant_reply:
                    "The previous reply did not start a local run, so there is no execution result to report yet."
                        .to_string(),
                run_state: runtime_run_state(
                    active_conversation_id.clone(),
                    "idle",
                    "no_active_run",
                    "The previous turn ended as a direct chat reply without starting a structured run.",
                    false,
                    None,
                    None,
                ),
            });
        }

        if run_state.stop_reason == "chat_runtime_needs_setup" {
            return Some(RunStatusFollowUpDecision {
                assistant_reply:
                    "The previous turn did not start a local run because the chat runtime is not configured, so there is no new execution result yet."
                        .to_string(),
                run_state: runtime_run_state(
                    active_conversation_id.clone(),
                    "idle",
                    "chat_runtime_needs_setup",
                    "The previous turn did not start a structured run because live chat was not configured.",
                    false,
                    None,
                    None,
                ),
            });
        }

        if run_state.stop_reason == "chat_runtime_degraded" {
            return Some(RunStatusFollowUpDecision {
                assistant_reply:
                    "The previous turn also did not start a local run because the chat runtime was degraded, so there is no follow-up execution result to report."
                        .to_string(),
                run_state: runtime_run_state(
                    active_conversation_id.clone(),
                    "idle",
                    "chat_runtime_degraded",
                    "The previous turn did not start a structured run because the live chat request failed.",
                    false,
                    None,
                    None,
                ),
            });
        }

        return Some(RunStatusFollowUpDecision {
            assistant_reply: run_state.detail.clone(),
            run_state,
        });
    }

    Some(RunStatusFollowUpDecision {
        assistant_reply: "There is no ongoing local run in this conversation right now, so there is no new execution result to report."
            .to_string(),
        run_state: runtime_run_state(
            active_conversation_id,
            "idle",
            "no_active_run",
            "There is no resumable local run in the current conversation.",
            false,
            None,
            None,
        ),
    })
}

fn task_status_label(status: &TaskStatus) -> String {
    match status {
        TaskStatus::Queued => "queued",
        TaskStatus::Running => "running",
        TaskStatus::WaitingReview => "waiting_review",
        TaskStatus::WaitingInput => "waiting_input",
        TaskStatus::Completed => "completed",
        TaskStatus::Failed => "failed",
        TaskStatus::Cancelled => "cancelled",
    }
    .to_string()
}

fn task_stage_label(stage: &TaskStage) -> String {
    match stage {
        TaskStage::Intent => "intent",
        TaskStage::Planning => "planning",
        TaskStage::Dispatching => "dispatching",
        TaskStage::Running => "running",
        TaskStage::Digesting => "digesting",
        TaskStage::ReviewPending => "review_pending",
        TaskStage::Reporting => "reporting",
        TaskStage::Finalized => "finalized",
    }
    .to_string()
}

fn importance_level_label(level: &ImportanceLevel) -> String {
    match level {
        ImportanceLevel::Background => "background",
        ImportanceLevel::Passive => "passive",
        ImportanceLevel::Important => "important",
        ImportanceLevel::Review => "review",
    }
    .to_string()
}

fn runtime_task_record_from_task_run(task_run: &TaskRun, artifact_count: u32) -> RuntimeTaskRecord {
    RuntimeTaskRecord {
        task_id: task_run.task_id.clone(),
        conversation_id: task_run.conversation_id.clone(),
        title: task_run.title.clone(),
        summary: task_run.summary.clone(),
        current_stage: task_stage_label(&task_run.current_stage),
        status: task_status_label(&task_run.status),
        importance_level: importance_level_label(&task_run.importance_level),
        progress_percent: task_run.progress_percent.unwrap_or_default(),
        artifact_count,
        approval_request_id: task_run.approval_request_id.clone(),
    }
}

fn activate_conversation_for_task(
    store: &mut RuntimeStore,
    task_id: &str,
) -> Result<Option<String>, String> {
    let target_conversation_id = store
        .tasks
        .iter()
        .find(|task| task.task_id == task_id)
        .and_then(|task| task.conversation_id.clone());

    let Some(target_conversation_id) = target_conversation_id else {
        return Ok(None);
    };

    if target_conversation_id == store.active_conversation_id {
        return Ok(Some(target_conversation_id));
    }

    store.set_active_conversation(&target_conversation_id)?;
    Ok(Some(target_conversation_id))
}

fn controlled_terminal_meta_for_request(
    store: &RuntimeStore,
    request: &ControlledTerminalRequest,
    task_id: Option<&str>,
) -> ExecutionRequestMeta {
    let existing_task = task_id.and_then(|task_id| {
        store
            .tasks
            .iter()
            .find(|task| task.task_id == task_id)
            .cloned()
    });
    let existing_module_run = task_id.and_then(|task_id| {
        store
            .module_runs
            .iter()
            .find(|module_run| module_run.module_run.task_id == task_id)
            .map(|module_run| module_run.module_run.clone())
    });

    ExecutionRequestMeta {
        task_id: task_id
            .map(|task_id| task_id.to_string())
            .unwrap_or_else(|| quick_task_id(store)),
        module_run_id: existing_module_run
            .map(|module_run| module_run.module_run_id)
            .unwrap_or_else(|| quick_module_run_id(store)),
        conversation_id: existing_task
            .as_ref()
            .and_then(|task| task.conversation_id.clone())
            .or_else(|| {
                store
                    .active_conversation()
                    .map(|conversation| conversation.conversation_id.clone())
            }),
        title: existing_task
            .as_ref()
            .map(|task| task.title.clone())
            .unwrap_or_else(|| {
                format!("Terminal request: {}", summarize_prompt(&request.goal, 44))
            }),
        prompt: request.goal.clone(),
        created_at: "now".to_string(),
        updated_at: "now".to_string(),
    }
}

fn build_terminal_tool_request(
    step: &ControlledTerminalStep,
    approval_token: Option<String>,
) -> ToolRequest {
    ToolRequest {
        tool_id: "shell.run".to_string(),
        arguments: serde_json::json!({
            "command": step.command,
            "args": step.args,
            "cwd": step.cwd,
        }),
        // Controlled terminal steps are system-run capabilities inside the
        // shared turn runner. Persona styling must not be able to disable the
        // runtime's guarded terminal lane; approval and shell policy still
        // enforce the real execution boundary.
        allowed_tool_ids: None,
        approval_token,
        files_root: None,
    }
}

fn execute_controlled_terminal_step(
    step: &ControlledTerminalStep,
    approval_token: Option<String>,
) -> ControlledTerminalObservation {
    let request = build_terminal_tool_request(step, approval_token);
    let outcome = invoke_tool(request);
    ControlledTerminalObservation {
        step: step.clone(),
        outcome,
    }
}

fn shell_stdout_contains_running_python_processes(stdout: &str) -> bool {
    stdout.lines().any(|line| {
        let lowered = line.to_ascii_lowercase();
        lowered.contains("python") && !lowered.trim().is_empty()
    })
}

fn shell_completed_output(observation: &ControlledTerminalObservation) -> Option<(String, String)> {
    let ToolOutcome::Completed { payload, .. } = &observation.outcome else {
        return None;
    };
    let stdout = payload
        .get("stdout")
        .and_then(serde_json::Value::as_str)
        .unwrap_or("")
        .trim()
        .to_string();
    let stderr = payload
        .get("stderr")
        .and_then(serde_json::Value::as_str)
        .unwrap_or("")
        .trim()
        .to_string();
    Some((stdout, stderr))
}

fn shell_completed_exit_code(observation: &ControlledTerminalObservation) -> Option<i64> {
    let ToolOutcome::Completed { payload, .. } = &observation.outcome else {
        return None;
    };
    payload.get("exit_code").and_then(serde_json::Value::as_i64)
}

fn summarize_docker_container_plan(
    only_startable: bool,
    observations: &[ControlledTerminalObservation],
) -> (String, String, String) {
    let Some((stdout, stderr)) = observations.iter().find_map(shell_completed_output) else {
        return (
            "Could not read the Docker container list.".to_string(),
            "Docker inspection did not produce terminal output.".to_string(),
            "docker inspection produced no output".to_string(),
        );
    };

    if !stderr.is_empty() && stdout.is_empty() {
        let summary = format!(
            "Docker inspection failed: {}",
            summarize_prompt(&stderr, 140)
        );
        return (
            format!(
                "I tried to inspect local Docker, but the step failed: {}",
                summarize_prompt(&stderr, 180)
            ),
            summary.clone(),
            summary,
        );
    }

    let containers = stdout
        .lines()
        .filter_map(|line| {
            let mut parts = line.split('\t');
            let name = parts.next()?.trim();
            let image = parts.next()?.trim();
            let status = parts.next()?.trim();
            if name.is_empty() {
                return None;
            }
            Some((name.to_string(), image.to_string(), status.to_string()))
        })
        .collect::<Vec<_>>();

    if containers.is_empty() {
        return (
            "I checked local Docker and did not find any containers.".to_string(),
            "No Docker containers were found locally.".to_string(),
            "no Docker containers found".to_string(),
        );
    }

    let startable = containers
        .iter()
        .filter(|(_, _, status)| !status.starts_with("Up"))
        .map(|(name, image, status)| format!("{name} ({image}, {status})"))
        .collect::<Vec<_>>();
    let running = containers
        .iter()
        .filter(|(_, _, status)| status.starts_with("Up"))
        .map(|(name, image, status)| format!("{name} ({image}, {status})"))
        .collect::<Vec<_>>();

    if only_startable {
        if startable.is_empty() {
            let running_suffix = if running.is_empty() {
                String::new()
            } else {
                format!(" Currently running: {}.", running.join("; "))
            };
            return (
                format!(
                    "I checked local Docker and did not find any stopped containers that can be started directly.{running_suffix}"
                ),
                "No directly startable Docker containers were found.".to_string(),
                "no directly startable Docker containers found".to_string(),
            );
        }

        return (
            format!(
                "I checked local Docker. These containers can be started directly: {}.",
                startable.join("; ")
            ),
            format!("Startable Docker containers: {}", startable.join(" | ")),
            format!(
                "found {} directly startable Docker container(s)",
                startable.len()
            ),
        );
    }

    (
        format!(
            "I checked local Docker. Current containers: {}.",
            containers
                .iter()
                .map(|(name, image, status)| format!("{name} ({image}, {status})"))
                .collect::<Vec<_>>()
                .join("; ")
        ),
        format!("Docker containers: {}", containers.len()),
        format!("inspected {} Docker container(s)", containers.len()),
    )
}

fn summarize_git_status_plan(
    observations: &[ControlledTerminalObservation],
) -> (String, String, String) {
    let Some((stdout, stderr)) = observations.iter().find_map(shell_completed_output) else {
        return (
            "Could not read the current repository status.".to_string(),
            "Git status produced no terminal output.".to_string(),
            "git status produced no output".to_string(),
        );
    };

    if !stderr.is_empty() && stdout.is_empty() {
        let summary = format!("Git status failed: {}", summarize_prompt(&stderr, 140));
        return (
            format!(
                "I tried to inspect the current repository status, but the step failed: {}",
                summarize_prompt(&stderr, 180)
            ),
            summary.clone(),
            summary,
        );
    }

    let compact = if stdout.is_empty() {
        "The working tree has no uncommitted changes.".to_string()
    } else {
        format!(
            "I checked the current repository status: {}",
            summarize_prompt(&stdout, 220)
        )
    };
    let quick = if stdout.is_empty() {
        "Git working tree is clean.".to_string()
    } else {
        summarize_prompt(&stdout, 140)
    };
    (compact, quick.clone(), quick)
}

fn summarize_directory_listing_plan(
    observations: &[ControlledTerminalObservation],
) -> (String, String, String) {
    let mut outputs = observations
        .iter()
        .filter_map(shell_completed_output)
        .collect::<Vec<_>>();
    if outputs.is_empty() {
        return (
            "Could not read the current directory.".to_string(),
            "Directory inspection produced no output.".to_string(),
            "directory inspection produced no output".to_string(),
        );
    }
    let (pwd_stdout, pwd_stderr) = outputs.remove(0);
    if !pwd_stderr.is_empty() && pwd_stdout.is_empty() {
        let summary = format!("pwd failed: {}", summarize_prompt(&pwd_stderr, 140));
        return (
            format!(
                "I tried to inspect the current directory, but the step failed: {}",
                summarize_prompt(&pwd_stderr, 180)
            ),
            summary.clone(),
            summary,
        );
    }
    let cwd = pwd_stdout.trim();
    let listing = outputs
        .last()
        .map(|(stdout, _)| stdout.clone())
        .unwrap_or_default();
    let compact_listing = summarize_prompt(&listing.replace('\n', "  "), 220);
    (
        format!(
            "I inspected the current directory: {}. Overview: {}",
            cwd, compact_listing
        ),
        format!("Directory: {}", cwd),
        format!("inspected working directory {}", cwd),
    )
}

fn summarize_generic_shell_plan(
    subject: &str,
    request: &ControlledTerminalRequest,
    observations: &[ControlledTerminalObservation],
) -> (String, String, String) {
    let completed_steps = observations
        .iter()
        .filter_map(|observation| {
            let (stdout, stderr) = shell_completed_output(observation)?;
            Some((
                observation.step.title.clone(),
                observation.step.command.clone(),
                shell_completed_exit_code(observation).unwrap_or_default(),
                stdout,
                stderr,
            ))
        })
        .collect::<Vec<_>>();

    if completed_steps.is_empty() {
        return (
            format!(
                "I tried to run {}, but there was no usable terminal output.",
                subject
            ),
            "Terminal command produced no usable output.".to_string(),
            "generic shell produced no usable output".to_string(),
        );
    }

    let step_summaries = completed_steps
        .iter()
        .map(|(title, command, exit_code, stdout, stderr)| {
            if *exit_code == 1 && matches!(command.as_str(), "grep" | "rg") {
                return format!("{title}: no matches found");
            }
            if !stderr.trim().is_empty() && stdout.trim().is_empty() {
                return format!("{title}: {}", summarize_prompt(stderr, 120));
            }
            if !stdout.trim().is_empty() {
                return format!("{title}: {}", summarize_prompt(stdout, 120));
            }
            if !stderr.trim().is_empty() {
                return format!("{title}: {}", summarize_prompt(stderr, 120));
            }
            format!("{title}: exit code {exit_code}")
        })
        .collect::<Vec<_>>();
    let compact = summarize_prompt(&step_summaries.join("; "), 220);
    (
        format!(
            "I executed the terminal plan as requested: {}. Result overview: {}",
            summarize_prompt(&request.plan_summary, 120),
            compact
        ),
        format!("Executed terminal plan: {}", summarize_prompt(subject, 80)),
        format!(
            "executed generic terminal plan for {}",
            summarize_prompt(subject, 120)
        ),
    )
}

fn summarize_host_diagnostics_plan(
    include_current_time: bool,
    observations: &[ControlledTerminalObservation],
) -> (String, String, String) {
    let current_time_label = include_current_time
        .then(|| runtime_facts_for_surface(ExecutionSurface::DesktopWorkspaceChat).local_time);
    let mut parts = Vec::new();
    let mut python_lines = Vec::new();
    let mut port_checked = false;
    let mut port_has_listener = false;
    let mut port_label = "target port".to_string();

    if let Some(current_time_label) = current_time_label {
        parts.push(format!(
            "First I recorded the current local time: {}.",
            current_time_label
        ));
    }

    for observation in observations {
        match observation.step.command.as_str() {
            "ps" => {
                let stdout = shell_completed_output(observation)
                    .map(|(stdout, _)| stdout)
                    .unwrap_or_default();
                python_lines = stdout
                    .lines()
                    .filter(|line| shell_stdout_contains_running_python_processes(line))
                    .map(|line| summarize_prompt(line, 160))
                    .collect::<Vec<_>>();

                if python_lines.is_empty() {
                    parts.push(
                        "I first checked the running python/python3 processes on this machine and did not find any process that looks like a service."
                            .to_string(),
                    );
                } else {
                    parts.push(format!(
                        "I first checked the running python/python3 processes on this machine and found {} candidate service(s): {}",
                        python_lines.len(),
                        python_lines.join("; ")
                    ));
                }
            }
            "lsof" => {
                let stdout = shell_completed_output(observation)
                    .map(|(stdout, _)| stdout)
                    .unwrap_or_default();
                port_checked = true;
                port_has_listener = !stdout.trim().is_empty();
                port_label = observation
                    .step
                    .args
                    .iter()
                    .find(|arg| arg.starts_with("-iTCP:"))
                    .map(|arg| arg.trim_start_matches("-iTCP:").to_string())
                    .unwrap_or_else(|| "target port".to_string());

                if port_has_listener {
                    parts.push(format!(
                        "Because the earlier result was not enough to conclude, I also checked port {}. Active LISTEN process(es): {}",
                        port_label,
                        summarize_prompt(&stdout.replace('\n', "  "), 220)
                    ));
                } else {
                    parts.push(format!(
                        "Because the earlier result was not enough to conclude, I also checked port {}. No process is currently in LISTEN state.",
                        port_label
                    ));
                }
            }
            _ => {}
        }
    }

    if python_lines.is_empty() && !port_checked && parts.is_empty() {
        parts.push(
            "This local diagnostic run did not produce any usable shell observations.".to_string(),
        );
    }

    let assistant = parts.join(" ");
    let quick = if !python_lines.is_empty() {
        format!("Found {} running python process(es).", python_lines.len())
    } else if port_checked {
        if port_has_listener {
            format!(
                "No running python process; port {} is listening.",
                port_label
            )
        } else {
            format!(
                "No running python process; port {} is not listening.",
                port_label
            )
        }
    } else {
        "No running python process found.".to_string()
    };
    let summary = summarize_prompt(&assistant, 220);
    (assistant, quick, summary)
}

fn summarize_controlled_terminal_request(
    request: &ControlledTerminalRequest,
    observations: &[ControlledTerminalObservation],
) -> (String, String, String) {
    match request.kind {
        ControlledTerminalPlanKind::DockerContainers { only_startable } => {
            summarize_docker_container_plan(only_startable, observations)
        }
        ControlledTerminalPlanKind::GitStatus => summarize_git_status_plan(observations),
        ControlledTerminalPlanKind::DirectoryListing => {
            summarize_directory_listing_plan(observations)
        }
        ControlledTerminalPlanKind::HostDiagnostics {
            include_current_time,
        } => summarize_host_diagnostics_plan(include_current_time, observations),
        ControlledTerminalPlanKind::GenericShell { ref subject } => {
            summarize_generic_shell_plan(subject, request, observations)
        }
    }
}

fn controlled_terminal_subject(request: &ControlledTerminalRequest) -> String {
    match request.kind {
        ControlledTerminalPlanKind::DockerContainers { .. } => "local Docker".to_string(),
        ControlledTerminalPlanKind::GitStatus => "current repository status".to_string(),
        ControlledTerminalPlanKind::DirectoryListing => "current directory".to_string(),
        ControlledTerminalPlanKind::HostDiagnostics { .. } => "local diagnostics".to_string(),
        ControlledTerminalPlanKind::GenericShell { ref subject } => subject.clone(),
    }
}

fn terminal_observation_error(observation: &ControlledTerminalObservation) -> Option<String> {
    match &observation.outcome {
        ToolOutcome::Completed { .. } => {
            let exit_code = shell_completed_exit_code(observation).unwrap_or_default();
            if exit_code == 1 && matches!(observation.step.command.as_str(), "grep" | "rg") {
                return None;
            }
            if exit_code == 0 {
                None
            } else {
                let (_, stderr) = shell_completed_output(observation).unwrap_or_default();
                if stderr.is_empty() {
                    Some(format!("the terminal step exited with code {exit_code}"))
                } else {
                    Some(stderr)
                }
            }
        }
        ToolOutcome::Error { message, .. } => Some(message.clone()),
        ToolOutcome::Denied { reason, .. } => Some(reason.clone()),
        ToolOutcome::NeedsApproval { prompt, .. } => Some(prompt.clone()),
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum TerminalObservationIssueKind {
    ApprovalRequired,
    Blocked,
    Failed,
}

fn terminal_observation_issue(
    observation: &ControlledTerminalObservation,
) -> Option<(TerminalObservationIssueKind, String)> {
    match &observation.outcome {
        ToolOutcome::NeedsApproval { .. } => terminal_observation_error(observation)
            .map(|message| (TerminalObservationIssueKind::ApprovalRequired, message)),
        ToolOutcome::Denied { .. } => terminal_observation_error(observation)
            .map(|message| (TerminalObservationIssueKind::Blocked, message)),
        ToolOutcome::Completed { .. } | ToolOutcome::Error { .. } => {
            terminal_observation_error(observation)
                .map(|message| (TerminalObservationIssueKind::Failed, message))
        }
    }
}

fn build_controlled_terminal_execution_outcome(
    meta: &ExecutionRequestMeta,
    request: &ControlledTerminalRequest,
    observations: &[ControlledTerminalObservation],
) -> ExecutionOutcome {
    let terminal_issue = observations.iter().find_map(terminal_observation_issue);
    let approval_request_id = format!("apr_{}", meta.task_id);
    let (assistant_reply, quick_reply, result_summary, status, progress_percent) = if let Some((
        kind,
        error,
    )) =
        terminal_issue
    {
        match kind {
                TerminalObservationIssueKind::ApprovalRequired => (
                    format!(
                        "This step needs your approval. I am ready to run it in the shared terminal lane: {}. Once approved, I will continue the same run.",
                        summarize_prompt(&request.plan_summary, 160)
                    ),
                    "Approval required before running this terminal plan.".to_string(),
                    format!("terminal execution paused for approval: {}", summarize_prompt(&error, 140)),
                    TaskStatus::WaitingReview,
                    Some(64),
                ),
                TerminalObservationIssueKind::Blocked => (
                    format!(
                        "I started the local terminal inspection as planned, but the step was blocked by system policy: {}",
                        summarize_prompt(&error, 180)
                    ),
                    format!("Terminal lane blocked: {}", summarize_prompt(&error, 120)),
                    format!("terminal lane blocked: {}", summarize_prompt(&error, 140)),
                    TaskStatus::Failed,
                    Some(72),
                ),
                TerminalObservationIssueKind::Failed => (
                    format!(
                        "I tried to inspect {}, but the step failed: {}",
                        controlled_terminal_subject(request),
                        summarize_prompt(&error, 180)
                    ),
                    format!(
                        "Terminal inspection failed: {}",
                        summarize_prompt(&error, 120)
                    ),
                    format!("terminal inspection failed: {}", summarize_prompt(&error, 140)),
                    TaskStatus::Failed,
                    Some(72),
                ),
            }
    } else {
        let (assistant_reply, quick_reply, summary) =
            summarize_controlled_terminal_request(request, observations);
        (
            assistant_reply,
            quick_reply,
            summary,
            TaskStatus::Completed,
            Some(100),
        )
    };

    let artifacts = observations
        .iter()
        .enumerate()
        .filter_map(|(index, observation)| {
            let (stdout, stderr) = shell_completed_output(observation)?;
            Some(ArtifactEnvelope {
                artifact_id: format!("artifact_terminal_step_{}", index + 1),
                artifact_type: "terminal_output".to_string(),
                title: observation.step.title.clone(),
                payload_ref: format!("terminal://{}/step/{}", meta.task_id, index + 1),
                summary: if stderr.is_empty() {
                    summarize_prompt(&stdout, 120)
                } else {
                    format!(
                        "stdout: {}; stderr: {}",
                        summarize_prompt(&stdout, 80),
                        summarize_prompt(&stderr, 80)
                    )
                },
                inline_preview: None,
                domain_tags: vec!["terminal".to_string(), "local_ops".to_string()],
            })
        })
        .collect::<Vec<_>>();

    let task_run = TaskRun {
        task_id: meta.task_id.clone(),
        conversation_id: meta.conversation_id.clone(),
        task_type: TaskType::AbilityRun,
        title: meta.title.clone(),
        status: status.clone(),
        current_stage: match status {
            TaskStatus::WaitingReview => TaskStage::ReviewPending,
            _ => TaskStage::Finalized,
        },
        summary: result_summary.clone(),
        progress_percent,
        importance_level: ImportanceLevel::Important,
        approval_request_id: matches!(status, TaskStatus::WaitingReview)
            .then_some(approval_request_id.clone()),
    };

    let module_run = ModuleRun {
        module_run_id: meta.module_run_id.clone(),
        task_id: meta.task_id.clone(),
        module_id: "geeagent.local.terminal".to_string(),
        capability_id: "controlled_terminal".to_string(),
        status: match status {
            TaskStatus::Completed => ModuleRunStatus::Completed,
            TaskStatus::Failed => ModuleRunStatus::Failed,
            TaskStatus::WaitingReview => ModuleRunStatus::WaitingReview,
            _ => ModuleRunStatus::Completed,
        },
        stage: match status {
            TaskStatus::WaitingReview => ModuleRunStage::ReviewPending,
            _ => ModuleRunStage::Finalized,
        },
        attempt_count: 1,
        result_summary: Some(result_summary),
        artifacts,
        created_at: meta.created_at.clone(),
        updated_at: meta.updated_at.clone(),
    };

    ExecutionOutcome {
        task_run,
        module_run,
        recoverability: matches!(status, TaskStatus::WaitingReview).then_some(Recoverability {
            retry_safe: false,
            resume_supported: true,
            hint: Some("Approve this terminal action to continue the same run.".to_string()),
        }),
        automation_drafts: Vec::new(),
        observation: None,
        assistant_reply,
        quick_reply,
    }
}

fn apply_execution_outcome_to_store(store: &mut RuntimeStore, outcome: ExecutionOutcome) {
    for draft in outcome.automation_drafts.clone() {
        store.insert_execution_automation_draft(draft);
    }

    let artifact_count = outcome.module_run.artifacts.len() as u32;
    let task_record = runtime_task_record_from_task_run(&outcome.task_run, artifact_count);

    if let Some(task) = store
        .tasks
        .iter_mut()
        .find(|task| task.task_id == task_record.task_id)
    {
        *task = task_record;
    } else {
        store.tasks.insert(0, task_record);
    }

    let runtime_module_record = RuntimeModuleRunRecord {
        module_run: outcome.module_run.clone(),
        recoverability: outcome.recoverability.clone(),
    };

    if let Some(module_run) = store
        .module_runs
        .iter_mut()
        .find(|module_run| module_run.module_run.task_id == outcome.task_run.task_id)
    {
        *module_run = runtime_module_record;
    } else {
        store.module_runs.insert(0, runtime_module_record);
    }

    store.workspace_focus = RuntimeWorkspaceFocus {
        mode: "task".to_string(),
        task_id: Some(outcome.task_run.task_id),
    };
}

fn sync_terminal_approval_projection(
    store: &mut RuntimeStore,
    meta: &ExecutionRequestMeta,
    request: &ControlledTerminalRequest,
    outcome: &ExecutionOutcome,
) {
    if let Some(approval_request_id) = outcome.task_run.approval_request_id.clone() {
        let action_title = format!(
            "Execute terminal plan: {}",
            summarize_prompt(&request.plan_summary, 72)
        );
        let reason = "This terminal action has side effects or broader shell scope, so GeeAgent paused the run for confirmation.".to_string();
        let parameters = request
            .steps
            .iter()
            .enumerate()
            .flat_map(|(index, step)| {
                let mut parameters = vec![RuntimeApprovalParameter {
                    label: format!("Step {} command", index + 1),
                    value: format!("{} {}", step.command, step.args.join(" "))
                        .trim()
                        .to_string(),
                }];
                if let Some(cwd) = step.cwd.clone() {
                    parameters.push(RuntimeApprovalParameter {
                        label: format!("Step {} cwd", index + 1),
                        value: cwd,
                    });
                }
                parameters
            })
            .collect::<Vec<_>>();

        if let Some(existing) = store
            .approval_requests
            .iter_mut()
            .find(|approval| approval.approval_request_id == approval_request_id)
        {
            existing.task_id = meta.task_id.clone();
            existing.action_title = action_title;
            existing.reason = reason;
            existing.risk_tags = vec!["terminal".to_string(), "shell".to_string()];
            existing.review_required = true;
            existing.status = "open".to_string();
            existing.parameters = parameters;
            existing.machine_context = Some(RuntimeApprovalMachineContext::ControlledTerminal {
                request: request.clone(),
            });
        } else {
            store.approval_requests.insert(
                0,
                RuntimeApprovalRecord {
                    approval_request_id,
                    task_id: meta.task_id.clone(),
                    action_title,
                    reason,
                    risk_tags: vec!["terminal".to_string(), "shell".to_string()],
                    review_required: true,
                    status: "open".to_string(),
                    parameters,
                    machine_context: Some(RuntimeApprovalMachineContext::ControlledTerminal {
                        request: request.clone(),
                    }),
                },
            );
        }
        return;
    }

    for approval in store.approval_requests.iter_mut() {
        if approval.task_id == meta.task_id && approval.status == "open" {
            approval.status = "approved".to_string();
        }
    }
}

fn summarize_prompt(prompt: &str, max_len: usize) -> String {
    summarize_runtime_prompt(prompt, max_len)
}

fn normalized_keywords(text: &str) -> HashSet<String> {
    const STOPWORDS: &[&str] = &[
        "about", "after", "before", "from", "have", "into", "just", "keep", "latest", "local",
        "should", "that", "them", "then", "this", "what", "with", "would", "your",
    ];

    let mut keywords = text
        .split(|ch: char| !ch.is_ascii_alphanumeric())
        .filter_map(|raw| {
            let lowercase = raw.to_ascii_lowercase();
            let trimmed = lowercase.trim();
            if trimmed.len() < 4 || STOPWORDS.contains(&trimmed) {
                return None;
            }

            let singular = if trimmed.ends_with('s') && trimmed.len() > 4 {
                &trimmed[..trimmed.len() - 1]
            } else {
                trimmed
            };

            Some(singular.to_string())
        })
        .collect::<HashSet<_>>();

    for token in cjk_topic_keywords(text) {
        keywords.insert(token);
    }

    keywords
}

fn is_cjk_topic_char(ch: char) -> bool {
    ('\u{4e00}'..='\u{9fff}').contains(&ch) || ('\u{3400}'..='\u{4dbf}').contains(&ch)
}

fn cjk_topic_keywords(text: &str) -> Vec<String> {
    const CJK_STOP_PHRASES: &[&str] = &[
        "什么",
        "为什么",
        "怎么",
        "如何",
        "告诉我",
        "看看",
        "查询",
        "检查",
        "现在",
        "这个",
        "那个",
        "一下",
        "有没有",
        "是多少",
        "是什么",
    ];

    let mut tokens = Vec::new();
    let mut current = String::new();

    for ch in text.chars() {
        if is_cjk_topic_char(ch) {
            current.push(ch);
        } else if !current.is_empty() {
            tokens.extend(cjk_topic_keywords_from_run(&current, CJK_STOP_PHRASES));
            current.clear();
        }
    }

    if !current.is_empty() {
        tokens.extend(cjk_topic_keywords_from_run(&current, CJK_STOP_PHRASES));
    }

    tokens
}

fn cjk_topic_keywords_from_run(run: &str, stop_phrases: &[&str]) -> Vec<String> {
    let mut cleaned = run.to_string();
    for phrase in stop_phrases {
        cleaned = cleaned.replace(phrase, "");
    }

    let chars = cleaned.chars().collect::<Vec<_>>();
    if chars.len() < 2 {
        return Vec::new();
    }

    let mut tokens = HashSet::new();
    if (2..=8).contains(&chars.len()) {
        tokens.insert(cleaned.clone());
    }

    for window in 2..=4 {
        if chars.len() < window {
            continue;
        }
        for slice in chars.windows(window) {
            tokens.insert(slice.iter().collect::<String>());
        }
    }

    tokens.into_iter().collect()
}

fn should_reuse_active_conversation(store: &RuntimeStore, prompt: &str) -> bool {
    let Some(active_conversation) = store.active_conversation() else {
        return false;
    };

    let prompt_keywords = routing_topic_keywords(prompt);
    if prompt_keywords.is_empty() {
        return false;
    }

    conversation_topic_match_score(active_conversation, &prompt_keywords).is_some()
}

fn routing_topic_keywords(text: &str) -> HashSet<String> {
    const GENERIC_ROUTING_WORDS: &[&str] = &[
        "answer",
        "check",
        "find",
        "official",
        "search",
        "site",
        "translate",
        "translation",
        "url",
        "website",
        "word",
    ];

    normalized_keywords(text)
        .into_iter()
        .filter(|keyword| !GENERIC_ROUTING_WORDS.contains(&keyword.as_str()))
        .collect()
}

fn conversation_topic_context(conversation: &RuntimeConversationRecord) -> String {
    let mut context = conversation.title.clone();
    for message in conversation.messages.iter().rev().take(12) {
        context.push(' ');
        context.push_str(&message.content);
    }
    context
}

fn conversation_topic_match_score(
    conversation: &RuntimeConversationRecord,
    prompt_keywords: &HashSet<String>,
) -> Option<usize> {
    let context = conversation_topic_context(conversation).to_ascii_lowercase();
    let conversation_keywords = normalized_keywords(&context);
    let mut score = 0usize;

    for keyword in prompt_keywords.intersection(&conversation_keywords) {
        let occurrence_count = context.matches(keyword.as_str()).count().max(1).min(4);
        let title_bonus = conversation
            .title
            .to_ascii_lowercase()
            .contains(keyword.as_str())
            .then_some(3)
            .unwrap_or(0);
        score = score.saturating_add(occurrence_count.saturating_add(title_bonus));
    }

    (score > 0).then_some(score)
}

fn best_quick_prompt_conversation_match(
    store: &RuntimeStore,
    prompt: &str,
) -> Option<(String, usize)> {
    let prompt_keywords = routing_topic_keywords(prompt);
    if prompt_keywords.is_empty() {
        return None;
    }

    let mut scored = store
        .conversations
        .iter()
        .filter_map(|conversation| {
            conversation_topic_match_score(conversation, &prompt_keywords)
                .map(|score| (conversation.conversation_id.clone(), score))
        })
        .collect::<Vec<_>>();

    scored.sort_by(|left, right| right.1.cmp(&left.1).then_with(|| left.0.cmp(&right.0)));
    let (best_id, best_score) = scored.first().cloned()?;
    if best_score == 0 {
        return None;
    }

    let second_score = scored.get(1).map(|(_, score)| *score).unwrap_or(0);
    if second_score == best_score {
        return None;
    }

    Some((best_id, best_score))
}

fn route_quick_prompt_to_best_conversation(
    store: &mut RuntimeStore,
    prompt: &str,
) -> Option<String> {
    let (conversation_id, _) = best_quick_prompt_conversation_match(store, prompt)?;
    if conversation_id == store.active_conversation_id {
        return Some(conversation_id);
    }

    if store
        .conversations
        .iter()
        .any(|conversation| conversation.conversation_id == conversation_id)
    {
        store.active_conversation_id = conversation_id.clone();
        store.workspace_focus = RuntimeWorkspaceFocus {
            mode: "default".to_string(),
            task_id: None,
        };
        store.sync_conversation_statuses();
        store.sync_execution_sessions();
        store.sync_kernel_sessions();
        return Some(conversation_id);
    }

    None
}

fn is_transient_quick_prompt(prompt: &str) -> bool {
    let trimmed = prompt.trim();
    if trimmed.is_empty() {
        return false;
    }

    let lowered = trimmed.to_ascii_lowercase();
    let looks_like_math = trimmed.chars().any(|ch| ch.is_ascii_digit())
        && trimmed.chars().any(|ch| {
            matches!(
                ch,
                '+' | '-' | '*' | '/' | '×' | '÷' | '=' | '^' | '%' | '(' | ')'
            )
        })
        && trimmed.chars().count() <= 120;
    if looks_like_math {
        return true;
    }

    let transient_patterns = [
        "的英文",
        "英文单词",
        "翻译成",
        "怎么说",
        "什么意思",
        "怎么算",
        "等于多少",
        "是多少",
        "读音",
        "拼写",
    ];
    if transient_patterns
        .iter()
        .any(|pattern| trimmed.contains(pattern))
        && trimmed.chars().count() <= 80
    {
        return true;
    }

    let english_transient_patterns = [
        "translate ",
        "what is ",
        "what's ",
        "calculate ",
        "spell ",
        "define ",
    ];
    english_transient_patterns
        .iter()
        .any(|pattern| lowered.contains(pattern))
        && trimmed.chars().count() <= 120
}

#[cfg(test)]
fn should_queue_quick_prompt_as_task(prompt: &str) -> bool {
    let trimmed = prompt.trim();
    if trimmed.is_empty() {
        return false;
    }

    let lowered = trimmed.to_ascii_lowercase();
    let word_count = lowered.split_whitespace().count();
    let non_ascii_count = trimmed.chars().filter(|ch| !ch.is_ascii()).count();
    let looks_like_math = trimmed
        .chars()
        .any(|ch| ['+', '-', '*', '/', '='].contains(&ch))
        || lowered.starts_with("what is ")
        || lowered.starts_with("calculate ");
    let action_keywords = [
        "review",
        "summarize",
        "digest",
        "monitor",
        "track",
        "watch",
        "save",
        "store",
        "publish",
        "post",
        "draft",
        "prepare",
        "create",
        "make",
        "design",
        "build",
        "plan",
        "schedule",
        "remind",
        "check",
        "collect",
        "analyze",
        "analyse",
        "search",
        "find",
        "download",
        "fetch",
        "compare",
        "organize",
        "organise",
        "write",
        "generate",
    ];
    let cjk_action_keywords = [
        "提醒", "通知", "定时", "监控", "跟踪", "追踪", "总结", "汇总", "分析", "抓取", "收集",
        "下载", "发布", "保存", "整理", "创建", "生成", "安排", "计划", "检查",
    ];
    let cjk_time_keywords = [
        "今天", "明天", "今晚", "明早", "每天", "每周", "每晚", "点", "号",
    ];

    if looks_like_math && trimmed.chars().count() <= 48 {
        return false;
    }

    lowered.contains("http://")
        || lowered.contains("https://")
        || trimmed.chars().count() >= 80
        || word_count >= 12
        || (word_count == 0 && non_ascii_count >= 10)
        || action_keywords
            .iter()
            .any(|keyword| lowered.contains(keyword))
        || cjk_action_keywords
            .iter()
            .any(|keyword| trimmed.contains(keyword))
        || (cjk_time_keywords
            .iter()
            .any(|keyword| trimmed.contains(keyword))
            && cjk_action_keywords
                .iter()
                .any(|keyword| trimmed.contains(keyword)))
}

fn quick_conversation_title(prompt: &str) -> String {
    summarize_prompt(prompt, 64)
}

fn controlled_terminal_kernel_final_output_ref(
    conversation_id: Option<String>,
    task_id: &str,
) -> Option<String> {
    conversation_id.map(|conversation_id| {
        format!("assistant://conversation/{conversation_id}/task/{task_id}/final-output")
    })
}

fn sync_kernel_approval_resolution(
    store: &mut RuntimeStore,
    surface: ExecutionSurface,
    task_id: &str,
    _approval_request_id: &str,
    decision: &str,
) -> Result<(), String> {
    let task_status = store
        .tasks
        .iter()
        .find(|task| task.task_id == task_id)
        .map(|task| task.status.clone());
    let task_summary = store
        .tasks
        .iter()
        .find(|task| task.task_id == task_id)
        .map(|task| task.summary.clone());
    let session_id = match store.ensure_kernel_session_for_active_conversation(surface) {
        Some(session_id) => session_id,
        None => return Ok(()),
    };
    let conversation_id = active_conversation_id(store);
    let final_output_ref = controlled_terminal_kernel_final_output_ref(conversation_id, task_id);
    let run_id = format!("krun_{task_id}");
    let interrupt_id = format!("kinterrupt_{task_id}");

    let runtime = match store.kernel_session_runtime_mut(&session_id) {
        Some(runtime) => runtime,
        None => return Ok(()),
    };
    if !runtime.runs.contains_key(&run_id) {
        return Ok(());
    }

    if runtime.interruptions.contains_key(&interrupt_id) {
        runtime.resolve_interruption(
            &interrupt_id,
            "now",
            format!("kevent_interrupt_resolution_{}_{}", task_id, decision),
            decision == "approve",
        );
    }

    if decision == "approve" {
        match task_status.as_deref() {
            Some("failed") | Some("cancelled") => runtime.fail_run(
                &run_id,
                "now",
                format!("kevent_run_failed_after_approval_{task_id}"),
                task_summary,
            ),
            _ => runtime.complete_run(
                &run_id,
                "now",
                format!("kevent_run_completed_after_approval_{task_id}"),
                final_output_ref,
            ),
        }
    }
    runtime.session.history_cursor = runtime
        .event_log
        .events()
        .last()
        .map(|event| event.sequence)
        .unwrap_or(runtime.session.history_cursor);

    Ok(())
}

fn sync_kernel_module_recovery(
    store: &mut RuntimeStore,
    surface: ExecutionSurface,
    task_id: &str,
    action: &str,
) -> Result<(), String> {
    let session_id = match store.ensure_kernel_session_for_active_conversation(surface) {
        Some(session_id) => session_id,
        None => return Ok(()),
    };
    let run_id = format!("krun_{task_id}");
    let interrupt_id = format!("kinterrupt_{task_id}");

    let runtime = match store.kernel_session_runtime_mut(&session_id) {
        Some(runtime) => runtime,
        None => return Ok(()),
    };
    if !runtime.runs.contains_key(&run_id) {
        return Ok(());
    }

    match action {
        "resume" => {
            if runtime.interruptions.contains_key(&interrupt_id) {
                runtime.resolve_interruption(
                    &interrupt_id,
                    "now",
                    format!("kevent_interrupt_resumed_{task_id}"),
                    true,
                );
            }
        }
        "retry" => {
            runtime.core.follow_up(QueuedRuntimeMessage {
                message_id: format!("follow_retry_{task_id}"),
                content: "retry the interrupted run".to_string(),
                created_at: "now".to_string(),
                source_kind: Some("recovery".to_string()),
            });
        }
        _ => {}
    }

    runtime.session.history_cursor = runtime
        .event_log
        .events()
        .last()
        .map(|event| event.sequence)
        .unwrap_or(runtime.session.history_cursor);

    Ok(())
}

fn execute_controlled_terminal_request_with_approval(
    request: &ControlledTerminalRequest,
    approval_request_id: &str,
) -> Vec<ControlledTerminalObservation> {
    let approval_token = Some(format!("approved:{approval_request_id}"));
    let mut observations = Vec::new();

    for step in request.steps.iter().cloned() {
        let observation = execute_controlled_terminal_step(&step, approval_token.clone());
        let should_stop = terminal_observation_issue(&observation).is_some();
        observations.push(observation);
        if should_stop {
            break;
        }
    }

    observations
}

fn turn_mode_for_source(source: &RuntimeRequestSource) -> TurnMode {
    match source {
        RuntimeRequestSource::WorkspaceChat => TurnMode::WorkspaceMessage,
        RuntimeRequestSource::QuickInput => TurnMode::QuickPrompt,
    }
}

fn resolve_sdk_bridge_terminal_approval(
    store: &mut RuntimeStore,
    approval_request_id: &str,
    task_id: &str,
    source: RuntimeRequestSource,
    surface: ExecutionSurface,
    user_prompt: String,
    bridge_session_id: String,
    bridge_request_id: String,
    scope: TerminalAccessScope,
    command: String,
    cwd: Option<String>,
    config_dir: Option<&Path>,
    decision: TerminalAccessDecision,
    allow_only_this_turn: bool,
) -> Result<(), String> {
    let _ = activate_conversation_for_task(store, task_id)?;
    let route = TurnRoute {
        mode: turn_mode_for_source(&source),
        source,
        surface: surface.clone(),
    };

    let resume_result = resume_agent_runtime_bridge_approval(
        &bridge_session_id,
        &bridge_request_id,
        decision.clone(),
    );
    let mut bridge_turn = match resume_result {
        Ok(turn) => turn,
        Err(error)
            if matches!(decision, TerminalAccessDecision::Allow)
                && is_lost_sdk_approval_resume_error(&error) =>
        {
            ClaudeSdkBridgeTurnResult {
                failed_reason: Some(error),
                ..ClaudeSdkBridgeTurnResult::default()
            }
        }
        Err(error)
            if matches!(decision, TerminalAccessDecision::Deny)
                && is_lost_sdk_approval_resume_error(&error) =>
        {
            ClaudeSdkBridgeTurnResult::default()
        }
        Err(error) => return Err(error),
    };

    if let Some(pending) = bridge_turn.pending_terminal_approval.clone() {
        let conversation_id =
            active_conversation_id(store).unwrap_or_else(|| store.active_conversation_id.clone());
        let session_id = execution_session_id_for_conversation(&conversation_id);
        append_tool_result_for_existing_invocation(
            store,
            &session_id,
            &format!("toolinv_{approval_request_id}"),
            ToolInvocationStatus::Succeeded,
            None,
            None,
        );
        return install_follow_up_claude_sdk_terminal_approval(
            store,
            &route,
            task_id,
            &user_prompt,
            &bridge_turn,
            &pending,
        );
    }

    if matches!(decision, TerminalAccessDecision::Deny) {
        bridge_turn.assistant_chunks = vec![format!(
            "This terminal access request was not executed. GeeAgent blocked it based on your choice: {}.",
            summarize_prompt(&command, 220)
        )];
    } else if let Some(reason) = bridge_turn.terminal_access_denied_reason.clone() {
        bridge_turn.assistant_chunks = vec![format!(
            "This terminal access request was not executed. GeeAgent's terminal permission file blocked it: {}.",
            summarize_prompt(&reason, 220)
        )];
    } else if let Some(reason) = bridge_turn.failed_reason.clone() {
        bridge_turn.assistant_chunks = vec![claude_sdk_failure_assistant_reply(&reason)];
    }

    let assistant_reply = if !bridge_turn.assistant_chunks.is_empty() {
        bridge_turn.assistant_chunks.join("\n\n")
    } else {
        bridge_turn.final_result.clone().unwrap_or_else(|| {
            "The SDK completed the resumed run without a text summary.".to_string()
        })
    };

    let control_summary = if matches!(decision, TerminalAccessDecision::Deny) {
        format!(
            "terminal access denied, resuming the paused SDK run with a deny decision: {}",
            summarize_prompt(&command, 120)
        )
    } else if bridge_turn.failed_reason.is_some() {
        "approval granted, resuming the paused SDK run and committing the failed result truthfully"
            .to_string()
    } else {
        format!(
            "approval granted, resuming the paused SDK run with terminal access allowed: {}",
            summarize_prompt(&command, 120)
        )
    };
    let finalize_reason = if matches!(decision, TerminalAccessDecision::Deny) {
        "the paused SDK run received the terminal denial and GeeAgent committed the blocked result back into the active conversation"
            .to_string()
    } else if bridge_turn.failed_reason.is_some() {
        "the resumed SDK run failed after terminal approval, and GeeAgent committed that failed result back into the active conversation"
            .to_string()
    } else {
        "the same SDK run continued after the terminal approval decision and GeeAgent committed the resulting tool trace back into the active conversation"
            .to_string()
    };
    append_claude_sdk_bridge_follow_up(
        store,
        surface.clone(),
        &control_summary,
        &bridge_turn,
        &assistant_reply,
        &finalize_reason,
    )?;

    let summary = if bridge_turn.failed_reason.is_some() {
        bridge_turn
            .failed_reason
            .clone()
            .unwrap_or_else(|| "The SDK failed after terminal approval.".to_string())
    } else if let Some(reason) = bridge_turn.terminal_access_denied_reason.clone() {
        reason
    } else {
        summarize_prompt(&assistant_reply, 180)
    };

    if store
        .module_runs
        .iter()
        .find(|module_run| module_run.module_run.task_id == task_id)
        .is_some()
    {
        let conversation_id =
            active_conversation_id(store).unwrap_or_else(|| store.active_conversation_id.clone());
        let session_id = execution_session_id_for_conversation(&conversation_id);
        append_tool_result_for_existing_invocation(
            store,
            &session_id,
            &format!("toolinv_{approval_request_id}"),
            if matches!(decision, TerminalAccessDecision::Deny)
                || bridge_turn.failed_reason.is_some()
            {
                ToolInvocationStatus::Failed
            } else {
                ToolInvocationStatus::Succeeded
            },
            None,
            if matches!(decision, TerminalAccessDecision::Deny)
                || bridge_turn.failed_reason.is_some()
            {
                Some(summary.clone())
            } else {
                None
            },
        );
    }

    if let Some(task) = store.tasks.iter_mut().find(|task| task.task_id == task_id) {
        task.summary = summary.clone();
        task.approval_request_id = None;
        task.current_stage = if matches!(decision, TerminalAccessDecision::Deny) {
            "rejected_waiting_input".to_string()
        } else if bridge_turn.failed_reason.is_some() {
            "finalized_failed".to_string()
        } else {
            "finalized".to_string()
        };
        task.progress_percent = if matches!(decision, TerminalAccessDecision::Deny) {
            68
        } else if bridge_turn.failed_reason.is_some() {
            72
        } else {
            100
        };
        task.status = if matches!(decision, TerminalAccessDecision::Deny) {
            "waiting_input".to_string()
        } else if bridge_turn.failed_reason.is_some() {
            "failed".to_string()
        } else {
            "completed".to_string()
        };
    }

    if let Some(module_run) = store
        .module_runs
        .iter_mut()
        .find(|module_run| module_run.module_run.task_id == task_id)
    {
        module_run.module_run.result_summary = Some(summary.clone());
        module_run.module_run.updated_at = "now".to_string();
        module_run.recoverability = if matches!(decision, TerminalAccessDecision::Deny) {
            Some(Recoverability {
                retry_safe: false,
                resume_supported: false,
                hint: Some("Terminal access was denied by review.".to_string()),
            })
        } else {
            None
        };
        module_run.module_run.status = if matches!(decision, TerminalAccessDecision::Deny) {
            ModuleRunStatus::Failed
        } else if bridge_turn.failed_reason.is_some() {
            ModuleRunStatus::Failed
        } else {
            ModuleRunStatus::Completed
        };
        module_run.module_run.stage = ModuleRunStage::Finalized;
    }

    store.quick_reply = if matches!(decision, TerminalAccessDecision::Deny) {
        "Terminal access denied. GeeAgent kept the run blocked without executing Bash.".to_string()
    } else if let Some(reason) = bridge_turn.failed_reason.as_deref() {
        claude_sdk_failed_quick_reply(reason)
    } else {
        claude_sdk_quick_reply(&assistant_reply, bridge_turn.tool_step_count())
    };
    store.chat_runtime = if let Some(reason) = bridge_turn.failed_reason.as_deref() {
        claude_sdk_degraded_chat_runtime_record(reason)
    } else {
        claude_sdk_chat_runtime_record()
    };
    store.last_run_state = Some(if matches!(decision, TerminalAccessDecision::Deny) {
        runtime_run_state(
            active_conversation_id(store),
            "waiting_input",
            "terminal_approval_denied",
            summarize_prompt(&assistant_reply, 220),
            true,
            Some(task_id.to_string()),
            store
                .module_runs
                .iter()
                .find(|module_run| module_run.module_run.task_id == task_id)
                .map(|module_run| module_run.module_run.module_run_id.clone()),
        )
    } else if let Some(reason) = bridge_turn.failed_reason.as_deref() {
        runtime_run_state(
            active_conversation_id(store),
            "failed",
            "terminal_approval_resume_failed",
            summarize_prompt(reason, 220),
            false,
            Some(task_id.to_string()),
            store
                .module_runs
                .iter()
                .find(|module_run| module_run.module_run.task_id == task_id)
                .map(|module_run| module_run.module_run.module_run_id.clone()),
        )
    } else {
        runtime_run_state(
            active_conversation_id(store),
            "completed",
            "terminal_approval_resume_completed",
            summarize_prompt(&assistant_reply, 220),
            false,
            Some(task_id.to_string()),
            store
                .module_runs
                .iter()
                .find(|module_run| module_run.module_run.task_id == task_id)
                .map(|module_run| module_run.module_run.module_run_id.clone()),
        )
    });
    store.last_request_outcome = Some(RuntimeRequestOutcomeRecord {
        source: route.source.clone(),
        kind: RuntimeRequestOutcomeKind::FirstPartyAction,
        detail: if bridge_turn.failed_reason.is_some() {
            summarize_prompt(&assistant_reply, 220)
        } else {
            store.quick_reply.clone()
        },
        task_id: Some(task_id.to_string()),
        module_run_id: store
            .module_runs
            .iter()
            .find(|module_run| module_run.module_run.task_id == task_id)
            .map(|module_run| module_run.module_run.module_run_id.clone()),
    });

    store.workspace_focus = RuntimeWorkspaceFocus {
        mode: "task".to_string(),
        task_id: Some(task_id.to_string()),
    };

    let _ = (user_prompt, cwd, scope, config_dir, allow_only_this_turn);

    Ok(())
}

fn is_lost_sdk_approval_resume_error(error: &str) -> bool {
    error.contains("has no pending approval")
        || error.contains("no pending approval")
        || error.contains("no longer alive")
}

fn resolve_controlled_terminal_approval(
    store: &mut RuntimeStore,
    approval_request_id: &str,
    task_id: &str,
    request: ControlledTerminalRequest,
) -> Result<(), String> {
    let _ = activate_conversation_for_task(store, task_id)?;
    let replay_surface = active_execution_surface(store, ExecutionSurface::DesktopWorkspaceChat);
    let meta = controlled_terminal_meta_for_request(store, &request, Some(task_id));
    let observations =
        execute_controlled_terminal_request_with_approval(&request, approval_request_id);
    let mut outcome = build_controlled_terminal_execution_outcome(&meta, &request, &observations);
    if let Some(profile) = store.active_agent_profile() {
        personalize_execution_outcome_for_agent(&mut outcome, profile);
    }

    let next_quick_reply = outcome.quick_reply.clone();
    let next_message = outcome.assistant_reply.clone();
    let next_status = tool_invocation_status_from_module_run_status(&outcome.module_run.status);
    let next_error = matches!(
        next_status,
        ToolInvocationStatus::Failed | ToolInvocationStatus::Cancelled
    )
    .then(|| outcome.task_run.summary.clone());

    sync_terminal_approval_projection(store, &meta, &request, &outcome);
    apply_execution_outcome_to_store(store, outcome.clone());
    store.quick_reply = next_quick_reply;
    store.last_run_state = Some(runtime_run_state_from_execution_outcome(
        active_conversation_id(store),
        &outcome,
        &meta,
    ));
    store.last_request_outcome = None;

    append_control_resolution_trace_for_task(
        store,
        replay_surface.clone(),
        task_id,
        Some(approval_request_id),
        "approval granted, resuming the paused terminal run and committing the prepared shell action",
        &next_message,
        "the paused terminal run resumed after approval and committed the guarded shell action",
        next_status,
        next_error,
    )?;

    sync_kernel_approval_resolution(
        store,
        replay_surface,
        task_id,
        approval_request_id,
        "approve",
    )?;

    store.workspace_focus = RuntimeWorkspaceFocus {
        mode: "task".to_string(),
        task_id: Some(task_id.to_string()),
    };

    Ok(())
}

fn resolve_approval(
    store: &mut RuntimeStore,
    approval_request_id: &str,
    decision: &str,
    config_dir: Option<&Path>,
) -> Result<(), String> {
    let normalized_decision = match decision {
        "approve" | "allow_once" => "allow_once",
        "always_allow" => "always_allow",
        "reject" | "deny" => "deny",
        _ => return Err("unsupported approval decision".to_string()),
    };

    let (task_id, machine_context) = {
        let approval = store
            .approval_requests
            .iter_mut()
            .find(|approval| approval.approval_request_id == approval_request_id)
            .ok_or_else(|| "approval request not found".to_string())?;

        if approval.status != "open" {
            return Err("approval request is not open".to_string());
        }

        match normalized_decision {
            "allow_once" | "always_allow" => approval.status = "approved".to_string(),
            "deny" => approval.status = "rejected".to_string(),
            _ => return Err("unsupported approval decision".to_string()),
        }

        (approval.task_id.clone(), approval.machine_context.clone())
    };

    match machine_context.clone() {
        Some(RuntimeApprovalMachineContext::ControlledTerminal { request }) => {
            let scope = controlled_terminal_scope(&request);
            let label = request.plan_summary.clone();
            match normalized_decision {
                "always_allow" => {
                    upsert_terminal_access_rule(
                        config_dir,
                        scope,
                        TerminalAccessDecision::Allow,
                        label,
                    )?;
                    return resolve_controlled_terminal_approval(
                        store,
                        approval_request_id,
                        &task_id,
                        request,
                    );
                }
                "allow_once" => {
                    return resolve_controlled_terminal_approval(
                        store,
                        approval_request_id,
                        &task_id,
                        request,
                    );
                }
                "deny" => {
                    upsert_terminal_access_rule(
                        config_dir,
                        scope,
                        TerminalAccessDecision::Deny,
                        label,
                    )?;
                }
                _ => {}
            }
        }
        Some(RuntimeApprovalMachineContext::SdkBridgeTerminal {
            source,
            surface,
            user_prompt,
            bridge_session_id,
            bridge_request_id,
            scope,
            command,
            cwd,
        }) => match normalized_decision {
            "always_allow" => {
                upsert_terminal_access_rule(
                    config_dir,
                    scope.clone(),
                    TerminalAccessDecision::Allow,
                    terminal_access_label_for_scope(&scope),
                )?;
                return resolve_sdk_bridge_terminal_approval(
                    store,
                    approval_request_id,
                    &task_id,
                    source,
                    surface,
                    user_prompt,
                    bridge_session_id,
                    bridge_request_id,
                    scope,
                    command,
                    cwd,
                    config_dir,
                    TerminalAccessDecision::Allow,
                    false,
                );
            }
            "allow_once" => {
                return resolve_sdk_bridge_terminal_approval(
                    store,
                    approval_request_id,
                    &task_id,
                    source,
                    surface,
                    user_prompt,
                    bridge_session_id,
                    bridge_request_id,
                    scope,
                    command,
                    cwd,
                    config_dir,
                    TerminalAccessDecision::Allow,
                    true,
                );
            }
            "deny" => {
                upsert_terminal_access_rule(
                    config_dir,
                    scope.clone(),
                    TerminalAccessDecision::Deny,
                    terminal_access_label_for_scope(&scope),
                )?;
                return resolve_sdk_bridge_terminal_approval(
                    store,
                    approval_request_id,
                    &task_id,
                    source,
                    surface,
                    user_prompt,
                    bridge_session_id,
                    bridge_request_id,
                    scope,
                    command,
                    cwd,
                    config_dir,
                    TerminalAccessDecision::Deny,
                    false,
                );
            }
            _ => {}
        },
        None => {}
    }

    let _ = activate_conversation_for_task(store, &task_id)?;
    let replay_surface = active_execution_surface(store, ExecutionSurface::DesktopWorkspaceChat);

    let (next_quick_reply, next_message) = match normalized_decision {
        "allow_once" | "always_allow" => (
            "Approved. GeeAgent resumed the paused action and moved the task out of review."
                .to_string(),
            "Approval received. I resumed the paused action and closed the review gate."
                .to_string(),
        ),
        "deny" => (
            "Denied. GeeAgent blocked that terminal access and moved the task back to waiting input."
                .to_string(),
            "Terminal access was denied. I kept the run intact and moved the task back to waiting input."
                .to_string(),
        ),
        _ => return Err("unsupported approval decision".to_string()),
    };

    {
        let task = store
            .tasks
            .iter_mut()
            .find(|task| task.task_id == task_id)
            .ok_or_else(|| "approval task not found".to_string())?;

        match normalized_decision {
            "allow_once" | "always_allow" => {
                task.status = "completed".to_string();
                task.current_stage = "approved_and_resumed".to_string();
                task.progress_percent = 100;
                task.summary =
                    "Approval granted. GeeAgent resumed the paused action and finalized the result."
                        .to_string();
                task.approval_request_id = None;
            }
            "deny" => {
                task.status = "waiting_input".to_string();
                task.current_stage = "rejected_waiting_input".to_string();
                task.progress_percent = 68;
                task.summary =
                    "Terminal access was denied. The paused action is intact and waiting for your next instruction."
                        .to_string();
            }
            _ => {}
        }
    }

    if let Some(module_run) = store
        .module_runs
        .iter_mut()
        .find(|module_run| module_run.module_run.task_id == task_id)
    {
        match normalized_decision {
            "allow_once" | "always_allow" => {
                module_run.module_run.status = ModuleRunStatus::Completed;
                module_run.module_run.stage = ModuleRunStage::Finalized;
                module_run.module_run.result_summary = Some(
                    "Approval granted. The paused action resumed and completed successfully."
                        .to_string(),
                );
                module_run.recoverability = None;
            }
            "deny" => {
                module_run.module_run.status = ModuleRunStatus::Failed;
                module_run.module_run.stage = ModuleRunStage::ReviewPending;
                module_run.module_run.result_summary = Some(
                    "Terminal access was denied. The paused action remains available for revision."
                        .to_string(),
                );
                module_run.recoverability = Some(Recoverability {
                    retry_safe: true,
                    resume_supported: true,
                    hint: Some("Adjust the paused action before retrying.".to_string()),
                });
            }
            _ => {}
        }
        module_run.module_run.updated_at = "now".to_string();
    }

    store.quick_reply = next_quick_reply;
    let conversation_id = active_conversation_id(store);
    store.last_run_state = Some(match normalized_decision {
        "allow_once" | "always_allow" => runtime_run_state(
            conversation_id.clone(),
            "completed",
            "approval_resumed_and_completed",
            "The paused run resumed after approval and completed successfully.",
            false,
            Some(task_id.clone()),
            store
                .module_runs
                .iter()
                .find(|module_run| module_run.module_run.task_id == task_id)
                .map(|module_run| module_run.module_run.module_run_id.clone()),
        ),
        "deny" => runtime_run_state(
            conversation_id,
            "waiting_input",
            "terminal_permission_denied",
            "The paused run remains intact and is waiting for more input after terminal access was denied.",
            true,
            Some(task_id.clone()),
            store
                .module_runs
                .iter()
                .find(|module_run| module_run.module_run.task_id == task_id)
                .map(|module_run| module_run.module_run.module_run_id.clone()),
        ),
        _ => unreachable!(),
    });
    let control_summary = match normalized_decision {
        "allow_once" | "always_allow" => turn_step_summary(
            1,
            "approval granted, resuming the paused run and committing the prepared action",
        ),
        "deny" => turn_step_summary(
            1,
            "terminal access denied, returning the run to waiting input without executing the prepared action",
        ),
        _ => unreachable!(),
    };
    let finalize_reason = match normalized_decision {
        "allow_once" | "always_allow" => {
            turn_finalize_summary(1, "the paused run resumed and completed after approval")
        }
        "deny" => turn_finalize_summary(
            1,
            "the paused run stayed intact and moved back to waiting input after terminal access was denied",
        ),
        _ => unreachable!(),
    };
    append_control_resolution_trace_for_task(
        store,
        replay_surface.clone(),
        &task_id,
        Some(approval_request_id),
        &control_summary,
        &next_message,
        &finalize_reason,
        match normalized_decision {
            "allow_once" | "always_allow" => ToolInvocationStatus::Succeeded,
            "deny" => ToolInvocationStatus::Failed,
            _ => unreachable!(),
        },
        (normalized_decision == "deny").then(|| {
            store
                .tasks
                .iter()
                .find(|task| task.task_id == task_id)
                .map(|task| task.summary.clone())
                .unwrap_or_else(|| {
                    "The paused run stayed intact and is waiting for more input.".to_string()
                })
        }),
    )?;

    sync_kernel_approval_resolution(
        store,
        replay_surface,
        &task_id,
        approval_request_id,
        if normalized_decision == "deny" {
            "reject"
        } else {
            "approve"
        },
    )?;

    store.workspace_focus = RuntimeWorkspaceFocus {
        mode: "task".to_string(),
        task_id: Some(task_id),
    };

    Ok(())
}

fn apply_module_recovery(
    store: &mut RuntimeStore,
    module_run_id: &str,
    action: &str,
) -> Result<(), String> {
    let module_run_index = store
        .module_runs
        .iter()
        .position(|module_run| module_run.module_run.module_run_id == module_run_id)
        .ok_or_else(|| "module run not found".to_string())?;

    let recoverability = store.module_runs[module_run_index]
        .recoverability
        .clone()
        .ok_or_else(|| "module run is not recoverable".to_string())?;
    let task_id = store.module_runs[module_run_index]
        .module_run
        .task_id
        .clone();
    let _ = activate_conversation_for_task(store, &task_id)?;
    let replay_surface = active_execution_surface(store, ExecutionSurface::DesktopWorkspaceChat);
    let (quick_reply, assistant_message) = match action {
        "retry" => {
            if !recoverability.retry_safe {
                return Err("module run is not safe to retry".to_string());
            }

            {
                let module_run_record = &mut store.module_runs[module_run_index];
                module_run_record.module_run.status = ModuleRunStatus::Queued;
                module_run_record.module_run.stage = ModuleRunStage::Preflight;
                module_run_record.module_run.attempt_count =
                    module_run_record.module_run.attempt_count.saturating_add(1);
                module_run_record.module_run.result_summary = Some(
          "Retry requested. GeeAgent queued the module run again and will walk it back through dispatch."
            .to_string(),
        );
                module_run_record.module_run.updated_at = "now".to_string();
                module_run_record.recoverability = Some(Recoverability {
                    retry_safe: false,
                    resume_supported: false,
                    hint: Some("Retry queued. Wait for GeeAgent to refresh this run.".to_string()),
                });
            }

            if let Some(task) = store.tasks.iter_mut().find(|task| task.task_id == task_id) {
                task.status = "queued".to_string();
                task.current_stage = "retry_requested".to_string();
                task.progress_percent = task.progress_percent.min(28).max(18);
                task.approval_request_id = None;
                task.summary =
          "Retry requested. GeeAgent re-queued the module run and is preparing a clean dispatch."
            .to_string();
            }

            for approval in store.approval_requests.iter_mut() {
                if approval.task_id == task_id && approval.status == "open" {
                    approval.status = "expired".to_string();
                }
            }

            store.workspace_focus = RuntimeWorkspaceFocus {
                mode: "task".to_string(),
                task_id: Some(task_id.clone()),
            };

            (
                "Queued a retry for this module run. GeeAgent is preparing a clean dispatch."
                    .to_string(),
                "I queued a retry for this module run and moved it back to preflight.".to_string(),
            )
        }
        "resume" => {
            if !recoverability.resume_supported {
                return Err("module run does not support resume".to_string());
            }

            let is_review_blocked = matches!(
                store.module_runs[module_run_index].module_run.status,
                ModuleRunStatus::WaitingReview
            ) || matches!(
                store.module_runs[module_run_index].module_run.stage,
                ModuleRunStage::ReviewPending
            );

            if is_review_blocked {
                store.workspace_focus = RuntimeWorkspaceFocus {
                    mode: "approval".to_string(),
                    task_id: Some(task_id.clone()),
                };
                (
                    "This run is blocked on review. I reopened the review gate in the workspace."
                        .to_string(),
                    "This module run is review-blocked, so I reopened the review gate for you."
                        .to_string(),
                )
            } else {
                {
                    let module_run_record = &mut store.module_runs[module_run_index];
                    module_run_record.module_run.status = ModuleRunStatus::Running;
                    if matches!(
                        module_run_record.module_run.stage,
                        ModuleRunStage::Finalized
                    ) {
                        module_run_record.module_run.stage = ModuleRunStage::Postprocess;
                    }
                    module_run_record.module_run.result_summary = Some(
            "Resume requested. GeeAgent reattached to the active run and is continuing execution."
              .to_string(),
          );
                    module_run_record.module_run.updated_at = "now".to_string();
                    module_run_record.recoverability = Some(Recoverability {
                        retry_safe: false,
                        resume_supported: false,
                        hint: Some(
                            "Resume requested. Wait for the next module refresh.".to_string(),
                        ),
                    });
                }

                if let Some(task) = store.tasks.iter_mut().find(|task| task.task_id == task_id) {
                    task.status = "running".to_string();
                    task.current_stage = "resume_requested".to_string();
                    task.progress_percent = task.progress_percent.max(52);
                    task.summary =
            "Resume requested. GeeAgent is continuing the interrupted module execution."
              .to_string();
                }

                store.workspace_focus = RuntimeWorkspaceFocus {
                    mode: "task".to_string(),
                    task_id: Some(task_id.clone()),
                };
                (
                    "Resumed this module run. GeeAgent is continuing execution now.".to_string(),
                    "I resumed this module run and moved it back into active execution."
                        .to_string(),
                )
            }
        }
        _ => return Err("unsupported module recovery action".to_string()),
    };

    store.quick_reply = quick_reply;
    let conversation_id = active_conversation_id(store);
    store.last_run_state = Some(match action {
        "retry" => runtime_run_state(
            conversation_id.clone(),
            "queued",
            "module_retry_requested",
            "The module run was re-queued for another attempt.",
            true,
            Some(task_id.clone()),
            Some(module_run_id.to_string()),
        ),
        "resume" => runtime_run_state(
            conversation_id,
            if store.workspace_focus.mode == "approval" {
                "waiting_review"
            } else {
                "running"
            },
            if store.workspace_focus.mode == "approval" {
                "module_resume_waiting_review"
            } else {
                "module_resume_requested"
            },
            assistant_message.clone(),
            true,
            Some(task_id.clone()),
            Some(module_run_id.to_string()),
        ),
        _ => unreachable!(),
    });
    let control_summary = match action {
        "retry" => turn_step_summary(
            1,
            "queuing a retry for the selected module run through the shared turn runner",
        ),
        "resume" => turn_step_summary(
            1,
            "resuming the selected module run through the shared turn runner",
        ),
        _ => unreachable!(),
    };
    let finalize_reason = match action {
        "retry" => turn_finalize_summary(1, "the module run was re-queued for another attempt"),
        "resume" => turn_finalize_summary(1, "the module run was moved back into active execution"),
        _ => unreachable!(),
    };
    record_control_follow_up(
        store,
        replay_surface.clone(),
        &control_summary,
        &assistant_message,
        &finalize_reason,
    )?;

    sync_kernel_module_recovery(store, replay_surface, &task_id, action)?;

    Ok(())
}

#[cfg(test)]
fn record_live_chat_turn_with_steps(
    store: &mut RuntimeStore,
    surface: ExecutionSurface,
    user_content: &str,
    step_details: &[String],
    assistant_reply: &str,
    finalize_reason: &str,
) -> Result<(), String> {
    let mut cursor = begin_turn_replay(store, surface, user_content)?;
    append_turn_steps(&mut cursor, store, step_details);
    append_assistant_message_for_active_conversation(store, &cursor.session_id, assistant_reply)?;
    finalize_turn_replay(store, &cursor, finalize_reason);
    Ok(())
}

fn record_claude_sdk_turn(
    store: &mut RuntimeStore,
    route: &TurnRoute,
    user_content: &str,
    bridge_turn: &ClaudeSdkBridgeTurnResult,
) -> Result<String, String> {
    let cursor = begin_turn_replay(store, route.surface.clone(), user_content)?;
    append_session_state_for_session(
        store,
        &cursor.session_id,
        "delegating this turn into the SDK loop through the Xenodia gateway so the agent can reason and use tools inside one real run",
    );

    for event in &bridge_turn.tool_events {
        match event {
            ClaudeSdkBridgeObservedToolEvent::Invocation {
                invocation_id,
                tool_name,
                input_summary,
            } => {
                store.append_transcript_event(
                    &cursor.session_id,
                    TranscriptEventPayload::ToolInvocation {
                        invocation: ToolInvocation {
                            invocation_id: invocation_id.clone(),
                            session_id: cursor.session_id.clone(),
                            originating_message_id: cursor.user_message_id.clone(),
                            tool_name: tool_name.clone(),
                            input_summary: input_summary.clone(),
                            status: ToolInvocationStatus::Running,
                            approval_request_id: None,
                            created_at: "now".to_string(),
                            updated_at: "now".to_string(),
                        },
                    },
                );
            }
            ClaudeSdkBridgeObservedToolEvent::Result {
                invocation_id,
                status,
                summary,
                error,
            } => {
                store.append_transcript_event(
                    &cursor.session_id,
                    TranscriptEventPayload::ToolResult {
                        invocation_id: invocation_id.clone(),
                        status: status.clone(),
                        summary: summary.clone(),
                        error: error.clone(),
                        artifacts: Vec::new(),
                    },
                );
            }
        }
    }

    if bridge_turn.auto_approved_tools > 0 {
        append_session_state_for_session(
            store,
            &cursor.session_id,
            format!(
                "the host auto-approved {} SDK tool request(s) during this bridge run",
                bridge_turn.auto_approved_tools
            ),
        );
    }

    let assistant_reply = if !bridge_turn.assistant_chunks.is_empty() {
        bridge_turn.assistant_chunks.join("\n\n")
    } else {
        bridge_turn
            .final_result
            .clone()
            .or_else(|| bridge_turn.failed_reason.clone())
            .unwrap_or_else(|| "The SDK completed the turn without a text summary.".to_string())
    };
    append_assistant_message_for_active_conversation(store, &cursor.session_id, &assistant_reply)?;
    let finalize_reason = if bridge_turn.failed_reason.is_some() {
        "the SDK bridge surfaced a real runtime failure and GeeAgent committed that failed turn back into the active conversation"
    } else {
        "the SDK bridge completed the active turn and committed the resulting tool trace back into GeeAgent"
    };
    finalize_turn_replay(store, &cursor, finalize_reason);
    Ok(assistant_reply)
}

fn append_claude_sdk_bridge_follow_up(
    store: &mut RuntimeStore,
    surface: ExecutionSurface,
    control_summary: &str,
    bridge_turn: &ClaudeSdkBridgeTurnResult,
    assistant_reply: &str,
    finalize_reason: &str,
) -> Result<(), String> {
    let session_id = store
        .ensure_execution_session_for_active_conversation(surface)
        .ok_or_else(|| "active conversation not found".to_string())?;
    append_session_state_for_session(store, &session_id, control_summary.to_string());

    for event in &bridge_turn.tool_events {
        match event {
            ClaudeSdkBridgeObservedToolEvent::Invocation {
                invocation_id,
                tool_name,
                input_summary,
            } => {
                store.append_transcript_event(
                    &session_id,
                    TranscriptEventPayload::ToolInvocation {
                        invocation: ToolInvocation {
                            invocation_id: invocation_id.clone(),
                            session_id: session_id.clone(),
                            originating_message_id: format!("approval_follow_up_{invocation_id}"),
                            tool_name: tool_name.clone(),
                            input_summary: input_summary.clone(),
                            status: ToolInvocationStatus::Running,
                            approval_request_id: None,
                            created_at: "now".to_string(),
                            updated_at: "now".to_string(),
                        },
                    },
                );
            }
            ClaudeSdkBridgeObservedToolEvent::Result {
                invocation_id,
                status,
                summary,
                error,
            } => {
                store.append_transcript_event(
                    &session_id,
                    TranscriptEventPayload::ToolResult {
                        invocation_id: invocation_id.clone(),
                        status: status.clone(),
                        summary: summary.clone(),
                        error: error.clone(),
                        artifacts: Vec::new(),
                    },
                );
            }
        }
    }

    append_assistant_message_for_active_conversation(store, &session_id, assistant_reply)?;
    append_session_state_for_session(store, &session_id, finalize_reason.to_string());
    Ok(())
}

fn install_claude_sdk_terminal_approval(
    store: &mut RuntimeStore,
    route: &TurnRoute,
    user_content: &str,
    pending: &ClaudeSdkPendingTerminalApproval,
) -> Result<String, String> {
    let task_id = quick_task_id(store);
    let approval_request_id = next_approval_request_id_for_task(store, &task_id);
    let module_run_id = quick_module_run_id(store);
    let conversation_id = active_conversation_id(store);
    let command_summary = pending
        .input_summary
        .clone()
        .unwrap_or_else(|| summarize_prompt(&pending.command, 160));
    let task_title = format!(
        "Terminal approval: {}",
        summarize_prompt(&pending.command, 44)
    );
    let approval_detail = format!("Terminal approval required: {command_summary}");

    let mut cursor = begin_turn_replay(store, route.surface.clone(), user_content)?;
    append_turn_step(
        &mut cursor,
        store,
        "delegating this turn into the SDK loop through the Xenodia gateway so the agent can reason and request host-reviewed tools",
    );
    append_turn_step(
        &mut cursor,
        store,
        "the SDK loop requested terminal access that GeeAgent has not seen before, so the host stopped for an explicit review choice",
    );
    store.append_transcript_event(
        &cursor.session_id,
        TranscriptEventPayload::ToolInvocation {
            invocation: ToolInvocation {
                invocation_id: format!("toolinv_{approval_request_id}"),
                session_id: cursor.session_id.clone(),
                originating_message_id: cursor.user_message_id.clone(),
                tool_name: "Bash".to_string(),
                input_summary: pending.input_summary.clone(),
                status: ToolInvocationStatus::Running,
                approval_request_id: Some(approval_request_id.clone()),
                created_at: "now".to_string(),
                updated_at: "now".to_string(),
            },
        },
    );
    finalize_turn_replay(
        store,
        &cursor,
        "the SDK loop paused because GeeAgent requires an explicit terminal permission decision before Bash can continue",
    );

    store.tasks.insert(
        0,
        RuntimeTaskRecord {
            task_id: task_id.clone(),
            conversation_id: conversation_id.clone(),
            title: task_title,
            summary: format!("Waiting for terminal review: {command_summary}"),
            current_stage: "review_pending".to_string(),
            status: "waiting_review".to_string(),
            importance_level: "important".to_string(),
            progress_percent: 64,
            artifact_count: 0,
            approval_request_id: Some(approval_request_id.clone()),
        },
    );
    store.module_runs.insert(
        0,
        RuntimeModuleRunRecord {
            module_run: ModuleRun {
                module_run_id: module_run_id.clone(),
                task_id: task_id.clone(),
                module_id: "geeagent.runtime.bridge".to_string(),
                capability_id: "terminal_permission_review".to_string(),
                status: ModuleRunStatus::WaitingReview,
                stage: ModuleRunStage::ReviewPending,
                attempt_count: 1,
                result_summary: Some(format!(
                    "Paused for terminal review before Bash can run: {command_summary}"
                )),
                artifacts: Vec::new(),
                created_at: "now".to_string(),
                updated_at: "now".to_string(),
            },
            recoverability: Some(Recoverability {
                retry_safe: false,
                resume_supported: true,
                hint: Some(
                    "Review this terminal request to let the SDK loop continue.".to_string(),
                ),
            }),
        },
    );
    store.approval_requests.insert(
        0,
        RuntimeApprovalRecord {
            approval_request_id: approval_request_id.clone(),
            task_id: task_id.clone(),
            action_title: format!(
                "Review terminal access: {}",
                summarize_prompt(&pending.command, 72)
            ),
            reason: "This terminal command needs your approval before GeeAgent runs it."
                .to_string(),
            risk_tags: vec![
                "terminal".to_string(),
                "shell".to_string(),
                "permission".to_string(),
            ],
            review_required: true,
            status: "open".to_string(),
            parameters: {
                let mut parameters = vec![RuntimeApprovalParameter {
                    label: "Command".to_string(),
                    value: pending.command.clone(),
                }];
                if let Some(cwd) = pending.cwd.clone() {
                    parameters.push(RuntimeApprovalParameter {
                        label: "Working directory".to_string(),
                        value: cwd,
                    });
                }
                parameters
            },
            machine_context: Some(RuntimeApprovalMachineContext::SdkBridgeTerminal {
                source: route.source.clone(),
                surface: route.surface.clone(),
                user_prompt: user_content.to_string(),
                bridge_session_id: pending.bridge_session_id.clone(),
                bridge_request_id: pending.bridge_request_id.clone(),
                scope: pending.scope.clone(),
                command: pending.command.clone(),
                cwd: pending.cwd.clone(),
            }),
        },
    );

    store.workspace_focus = RuntimeWorkspaceFocus {
        mode: "task".to_string(),
        task_id: Some(task_id.clone()),
    };
    store.quick_reply = "Terminal review needed before Bash can continue.".to_string();
    store.chat_runtime = claude_sdk_chat_runtime_record();
    store.last_run_state = Some(runtime_run_state(
        conversation_id,
        "waiting_review",
        "terminal_permission_review_required",
        "GeeAgent paused the SDK run because this terminal access has no stored permission."
            .to_string(),
        true,
        Some(task_id.clone()),
        Some(module_run_id),
    ));
    store.last_request_outcome = Some(RuntimeRequestOutcomeRecord {
        source: route.source.clone(),
        kind: RuntimeRequestOutcomeKind::TaskHandoff,
        detail: approval_detail,
        task_id: Some(task_id.clone()),
        module_run_id: None,
    });

    Ok(task_id)
}

fn install_follow_up_claude_sdk_terminal_approval(
    store: &mut RuntimeStore,
    route: &TurnRoute,
    task_id: &str,
    user_content: &str,
    bridge_turn: &ClaudeSdkBridgeTurnResult,
    pending: &ClaudeSdkPendingTerminalApproval,
) -> Result<(), String> {
    let _ = activate_conversation_for_task(store, task_id)?;
    let approval_request_id = next_approval_request_id_for_task(store, task_id);
    let conversation_id =
        active_conversation_id(store).unwrap_or_else(|| store.active_conversation_id.clone());
    let module_run_id = store
        .module_runs
        .iter()
        .find(|module_run| module_run.module_run.task_id == task_id)
        .map(|module_run| module_run.module_run.module_run_id.clone());
    let command_summary = pending
        .input_summary
        .clone()
        .unwrap_or_else(|| summarize_prompt(&pending.command, 160));
    let session_id = store
        .ensure_execution_session_for_active_conversation(route.surface.clone())
        .ok_or_else(|| "active conversation not found".to_string())?;

    append_session_state_for_session(
        store,
        &session_id,
        format!(
            "the resumed SDK run reached another terminal approval boundary before completion: {}",
            summarize_prompt(&pending.command, 140)
        ),
    );
    for event in &bridge_turn.tool_events {
        match event {
            ClaudeSdkBridgeObservedToolEvent::Invocation {
                invocation_id,
                tool_name,
                input_summary,
            } => {
                store.append_transcript_event(
                    &session_id,
                    TranscriptEventPayload::ToolInvocation {
                        invocation: ToolInvocation {
                            invocation_id: invocation_id.clone(),
                            session_id: session_id.clone(),
                            originating_message_id: format!("approval_follow_up_{invocation_id}"),
                            tool_name: tool_name.clone(),
                            input_summary: input_summary.clone(),
                            status: ToolInvocationStatus::Running,
                            approval_request_id: None,
                            created_at: "now".to_string(),
                            updated_at: "now".to_string(),
                        },
                    },
                );
            }
            ClaudeSdkBridgeObservedToolEvent::Result {
                invocation_id,
                status,
                summary,
                error,
            } => {
                store.append_transcript_event(
                    &session_id,
                    TranscriptEventPayload::ToolResult {
                        invocation_id: invocation_id.clone(),
                        status: status.clone(),
                        summary: summary.clone(),
                        error: error.clone(),
                        artifacts: Vec::new(),
                    },
                );
            }
        }
    }
    if module_run_id.is_some() {
        let invocation_id = format!("toolinv_{approval_request_id}");
        store.append_transcript_event(
            &session_id,
            TranscriptEventPayload::ToolInvocation {
                invocation: ToolInvocation {
                    invocation_id,
                    session_id: session_id.clone(),
                    originating_message_id: format!("approval_follow_up_{task_id}"),
                    tool_name: "Bash".to_string(),
                    input_summary: pending.input_summary.clone(),
                    status: ToolInvocationStatus::Running,
                    approval_request_id: Some(approval_request_id.clone()),
                    created_at: "now".to_string(),
                    updated_at: "now".to_string(),
                },
            },
        );
    }

    if let Some(task) = store.tasks.iter_mut().find(|task| task.task_id == task_id) {
        task.summary = format!("Waiting for another terminal review: {command_summary}");
        task.current_stage = "review_pending".to_string();
        task.status = "waiting_review".to_string();
        task.progress_percent = task.progress_percent.max(66).min(82);
        task.approval_request_id = Some(approval_request_id.clone());
    }

    if let Some(module_run) = store
        .module_runs
        .iter_mut()
        .find(|module_run| module_run.module_run.task_id == task_id)
    {
        module_run.module_run.status = ModuleRunStatus::WaitingReview;
        module_run.module_run.stage = ModuleRunStage::ReviewPending;
        module_run.module_run.result_summary = Some(format!(
            "Paused for another terminal review before Bash can continue: {command_summary}"
        ));
        module_run.module_run.updated_at = "now".to_string();
        module_run.recoverability = Some(Recoverability {
            retry_safe: false,
            resume_supported: true,
            hint: Some("Review this terminal request to let the SDK loop continue.".to_string()),
        });
    }

    let parameters = {
        let mut parameters = vec![RuntimeApprovalParameter {
            label: "Command".to_string(),
            value: pending.command.clone(),
        }];
        if let Some(cwd) = pending.cwd.clone() {
            parameters.push(RuntimeApprovalParameter {
                label: "Working directory".to_string(),
                value: cwd,
            });
        }
        parameters
    };
    let approval = RuntimeApprovalRecord {
        approval_request_id: approval_request_id.clone(),
        task_id: task_id.to_string(),
        action_title: format!(
            "Review terminal access: {}",
            summarize_prompt(&pending.command, 72)
        ),
        reason:
            "The agent reached another terminal command that needs your approval before it runs."
                .to_string(),
        risk_tags: vec![
            "terminal".to_string(),
            "shell".to_string(),
            "permission".to_string(),
        ],
        review_required: true,
        status: "open".to_string(),
        parameters,
        machine_context: Some(RuntimeApprovalMachineContext::SdkBridgeTerminal {
            source: route.source.clone(),
            surface: route.surface.clone(),
            user_prompt: user_content.to_string(),
            bridge_session_id: pending.bridge_session_id.clone(),
            bridge_request_id: pending.bridge_request_id.clone(),
            scope: pending.scope.clone(),
            command: pending.command.clone(),
            cwd: pending.cwd.clone(),
        }),
    };
    store.approval_requests.insert(0, approval);

    store.workspace_focus = RuntimeWorkspaceFocus {
        mode: "task".to_string(),
        task_id: Some(task_id.to_string()),
    };
    store.quick_reply = "Another terminal review is needed before Bash can continue.".to_string();
    store.chat_runtime = claude_sdk_chat_runtime_record();
    store.last_run_state = Some(runtime_run_state(
        Some(conversation_id),
        "waiting_review",
        "terminal_permission_review_required",
        format!(
            "GeeAgent paused the same SDK run for another terminal permission review: {}",
            summarize_prompt(&pending.command, 180)
        ),
        true,
        Some(task_id.to_string()),
        module_run_id.clone(),
    ));
    store.last_request_outcome = Some(RuntimeRequestOutcomeRecord {
        source: route.source.clone(),
        kind: RuntimeRequestOutcomeKind::TaskHandoff,
        detail: format!("Another terminal approval required: {command_summary}"),
        task_id: Some(task_id.to_string()),
        module_run_id,
    });

    Ok(())
}

fn apply_claude_sdk_terminal_denial(
    store: &mut RuntimeStore,
    route: &TurnRoute,
    user_content: &str,
    reason: &str,
) -> Result<(), String> {
    let assistant_reply = format!(
        "This terminal access request was not executed. GeeAgent's terminal permission file blocked it: {}.",
        summarize_prompt(reason, 220)
    );
    let step_details = vec![
        "delegating this turn into the SDK loop through the Xenodia gateway so the agent can reason about the request".to_string(),
        "the host matched the requested Bash access against GeeAgent's terminal permission file and blocked it before execution".to_string(),
    ];
    record_clarification_turn_with_steps(
        store,
        route.surface.clone(),
        user_content,
        &step_details,
        &assistant_reply,
        "the SDK loop hit a terminal permission deny rule and GeeAgent stopped the turn without executing Bash",
    )?;
    store.quick_reply = format!(
        "Terminal access denied by Gee permissions. {}",
        summarize_prompt(reason, 120)
    );
    store.chat_runtime = claude_sdk_chat_runtime_record();
    store.last_run_state = Some(runtime_run_state(
        active_conversation_id(store),
        "waiting_input",
        "terminal_permission_denied",
        summarize_prompt(reason, 220),
        true,
        None,
        None,
    ));
    store.last_request_outcome = Some(RuntimeRequestOutcomeRecord {
        source: route.source.clone(),
        kind: RuntimeRequestOutcomeKind::ClarifyNeeded,
        detail: assistant_reply,
        task_id: None,
        module_run_id: None,
    });
    Ok(())
}

fn apply_claude_sdk_turn(
    store: &mut RuntimeStore,
    route: &TurnRoute,
    prepared: &PreparedTurnContext,
    text: &str,
    config_dir_override: Option<&Path>,
) -> Result<(), String> {
    if matches!(route.mode, TurnMode::QuickPrompt) && !prepared.should_reuse_active_conversation {
        store.create_conversation(Some(quick_conversation_title(text)));
    }

    let bridge_session_id = execution_session_id_for_conversation(&store.active_conversation_id);
    let mut bridge_turn = match run_agent_runtime_bridge_turn(
        &bridge_session_id,
        route,
        prepared,
        text,
        config_dir_override,
        &[],
    ) {
        Ok(turn) => turn,
        Err(error) => ClaudeSdkBridgeTurnResult {
            assistant_chunks: vec![claude_sdk_failure_assistant_reply(&error)],
            failed_reason: Some(error),
            ..ClaudeSdkBridgeTurnResult::default()
        },
    };
    if let Some(pending) = bridge_turn.pending_terminal_approval.clone() {
        install_claude_sdk_terminal_approval(store, route, text, &pending)?;
        return Ok(());
    }
    if let Some(reason) = bridge_turn.terminal_access_denied_reason.clone() {
        apply_claude_sdk_terminal_denial(store, route, text, &reason)?;
        return Ok(());
    }
    if let Some(reason) = bridge_turn.failed_reason.clone() {
        bridge_turn.assistant_chunks = vec![claude_sdk_failure_assistant_reply(&reason)];
    }
    let assistant_reply = record_claude_sdk_turn(store, route, text, &bridge_turn)?;
    let quick_reply = if let Some(reason) = bridge_turn.failed_reason.as_deref() {
        claude_sdk_failed_quick_reply(reason)
    } else {
        claude_sdk_quick_reply(&assistant_reply, bridge_turn.tool_step_count())
    };

    store.quick_reply = quick_reply.clone();
    store.chat_runtime = if let Some(reason) = bridge_turn.failed_reason.as_deref() {
        claude_sdk_degraded_chat_runtime_record(reason)
    } else {
        claude_sdk_chat_runtime_record()
    };
    store.last_run_state = Some(if let Some(reason) = bridge_turn.failed_reason.as_deref() {
        claude_sdk_failed_run_state(store, reason)
    } else {
        claude_sdk_completed_run_state(store, &assistant_reply)
    });
    store.last_request_outcome = Some(RuntimeRequestOutcomeRecord {
        source: route.source.clone(),
        kind: RuntimeRequestOutcomeKind::ChatReply,
        detail: quick_reply,
        task_id: None,
        module_run_id: None,
    });

    Ok(())
}

fn transient_bridge_session_id(text: &str) -> String {
    let mut hasher = DefaultHasher::new();
    text.hash(&mut hasher);
    current_timestamp_rfc3339().hash(&mut hasher);
    format!("session_quick_transient_{:x}", hasher.finish())
}

fn apply_transient_claude_sdk_quick_turn(
    store: &mut RuntimeStore,
    route: &TurnRoute,
    prepared: &PreparedTurnContext,
    text: &str,
    config_dir_override: Option<&Path>,
) -> Result<(), String> {
    let mut transient_prepared = prepared.clone();
    transient_prepared.workspace_messages.clear();
    transient_prepared.should_reuse_active_conversation = true;
    let bridge_session_id = transient_bridge_session_id(text);
    let mut bridge_turn = match run_agent_runtime_bridge_turn(
        &bridge_session_id,
        route,
        &transient_prepared,
        text,
        config_dir_override,
        &[],
    ) {
        Ok(turn) => turn,
        Err(error) => ClaudeSdkBridgeTurnResult {
            assistant_chunks: vec![claude_sdk_failure_assistant_reply(&error)],
            failed_reason: Some(error),
            ..ClaudeSdkBridgeTurnResult::default()
        },
    };

    if bridge_turn.pending_terminal_approval.is_some()
        || bridge_turn.terminal_access_denied_reason.is_some()
    {
        return apply_claude_sdk_turn(store, route, prepared, text, config_dir_override);
    }

    if let Some(reason) = bridge_turn.failed_reason.clone() {
        bridge_turn.assistant_chunks = vec![claude_sdk_failure_assistant_reply(&reason)];
    }
    let assistant_reply = if !bridge_turn.assistant_chunks.is_empty() {
        bridge_turn.assistant_chunks.join("\n\n")
    } else {
        bridge_turn
            .final_result
            .clone()
            .unwrap_or_else(|| "GeeAgent completed the transient quick reply.".to_string())
    };
    let quick_reply = if let Some(reason) = bridge_turn.failed_reason.as_deref() {
        claude_sdk_failed_quick_reply(reason)
    } else {
        claude_sdk_quick_reply(&assistant_reply, bridge_turn.tool_step_count())
    };

    store.quick_reply = quick_reply.clone();
    store.chat_runtime = if let Some(reason) = bridge_turn.failed_reason.as_deref() {
        claude_sdk_degraded_chat_runtime_record(reason)
    } else {
        claude_sdk_chat_runtime_record()
    };
    store.last_run_state = Some(if let Some(reason) = bridge_turn.failed_reason.as_deref() {
        claude_sdk_failed_run_state(store, reason)
    } else {
        claude_sdk_completed_run_state(store, &assistant_reply)
    });
    store.last_request_outcome = Some(RuntimeRequestOutcomeRecord {
        source: route.source.clone(),
        kind: RuntimeRequestOutcomeKind::ChatReply,
        detail: quick_reply,
        task_id: None,
        module_run_id: None,
    });

    Ok(())
}

#[cfg(test)]
#[allow(dead_code)]
fn record_live_chat_turn(
    store: &mut RuntimeStore,
    surface: ExecutionSurface,
    user_content: &str,
    assistant_reply: &str,
) -> Result<(), String> {
    let step_details = default_direct_reply_turn_steps();
    record_live_chat_turn_with_steps(
        store,
        surface,
        user_content,
        &step_details,
        assistant_reply,
        "the runner produced a direct answer without dispatching a structured action",
    )
}

fn record_control_follow_up(
    store: &mut RuntimeStore,
    surface: ExecutionSurface,
    control_summary: &str,
    assistant_reply: &str,
    finalize_reason: &str,
) -> Result<(), String> {
    let session_id = store
        .ensure_execution_session_for_active_conversation(surface)
        .ok_or_else(|| "active conversation not found".to_string())?;
    append_session_state_for_session(store, &session_id, control_summary.to_string());
    append_assistant_message_for_active_conversation(store, &session_id, assistant_reply)?;
    append_session_state_for_session(store, &session_id, finalize_reason.to_string());
    Ok(())
}

#[cfg(test)]
fn apply_quick_prompt_with_steps(
    store: &mut RuntimeStore,
    surface: ExecutionSurface,
    prompt: &str,
    step_details: &[String],
    assistant_reply: &str,
    quick_reply: &str,
) -> Result<(), String> {
    let trimmed_prompt = prompt.trim();
    if trimmed_prompt.is_empty() {
        return Err("prompt cannot be empty".to_string());
    }

    let should_queue_task = should_queue_quick_prompt_as_task(trimmed_prompt);

    if should_queue_task && !should_reuse_active_conversation(store, trimmed_prompt) {
        store.create_conversation(Some(quick_conversation_title(trimmed_prompt)));
    }
    record_live_chat_turn_with_steps(
        store,
        surface,
        trimmed_prompt,
        step_details,
        assistant_reply,
        "the runner produced a direct answer without dispatching a structured action",
    )?;
    store.quick_reply = quick_reply.to_string();

    if !should_queue_task {
        store.workspace_focus = RuntimeWorkspaceFocus {
            mode: "default".to_string(),
            task_id: None,
        };
        return Ok(());
    }

    let task_id = quick_task_id(store);
    let task_title = format!("Quick request: {}", summarize_prompt(trimmed_prompt, 44));
    store.workspace_focus = RuntimeWorkspaceFocus {
        mode: "task".to_string(),
        task_id: Some(task_id.clone()),
    };
    store.tasks.insert(
    0,
    RuntimeTaskRecord {
      task_id,
      conversation_id: active_conversation_id(store),
      title: task_title,
      summary: "Queued from quick input. GeeAgent is triaging the request before routing it into the main workspace."
        .to_string(),
      current_stage: "triage".to_string(),
      status: "queued".to_string(),
      importance_level: "important".to_string(),
      progress_percent: 12,
      artifact_count: 0,
      approval_request_id: None,
    },
  );
    store.module_runs.insert(
    0,
    RuntimeModuleRunRecord {
      module_run: ModuleRun {
        module_run_id: quick_module_run_id(store),
        task_id: store.tasks[0].task_id.clone(),
        module_id: "geeagent.intent.router".to_string(),
        capability_id: "triage_request".to_string(),
        status: ModuleRunStatus::Queued,
        stage: ModuleRunStage::Preflight,
        attempt_count: 1,
        result_summary: Some(
          "Queued this quick request for triage before routing it into a concrete external capability."
            .to_string(),
        ),
        artifacts: vec![ArtifactEnvelope {
          artifact_id: "artifact_quick_request".to_string(),
          artifact_type: "task_brief".to_string(),
          title: "Quick request brief".to_string(),
          summary: summarize_prompt(trimmed_prompt, 96),
          payload_ref: "memory://quick-request/latest".to_string(),
          inline_preview: None,
          domain_tags: vec!["quick-input".to_string(), "triage".to_string()],
        }],
        created_at: "now".to_string(),
        updated_at: "now".to_string(),
      },
      recoverability: Some(Recoverability {
        retry_safe: true,
        resume_supported: false,
        hint: Some("Wait for GeeAgent to finish triage before retrying this run.".to_string()),
      }),
    },
  );

    Ok(())
}

#[cfg(test)]
#[allow(dead_code)]
fn apply_quick_prompt(
    store: &mut RuntimeStore,
    surface: ExecutionSurface,
    prompt: &str,
    assistant_reply: &str,
    quick_reply: &str,
) -> Result<(), String> {
    let step_details = default_direct_reply_turn_steps();
    apply_quick_prompt_with_steps(
        store,
        surface,
        prompt,
        &step_details,
        assistant_reply,
        quick_reply,
    )
}

#[cfg(test)]
fn workspace_quick_reply(provider_name: &str, content: &str, profile: &AgentProfile) -> String {
    format!(
        "Live reply via {provider_name} as {}. {}",
        agent_display_name(profile),
        summarize_prompt(content, 120)
    )
}

#[cfg(test)]
fn quick_input_reply(provider_name: &str, content: &str, profile: &AgentProfile) -> String {
    format!(
        "Quick reply via {provider_name} as {}. {}",
        agent_display_name(profile),
        summarize_prompt(content, 120)
    )
}

fn runtime_run_state_from_execution_outcome(
    conversation_id: Option<String>,
    outcome: &ExecutionOutcome,
    meta: &ExecutionRequestMeta,
) -> RuntimeRunStateRecord {
    let status = task_status_label(&outcome.task_run.status);
    let resumable = matches!(
        outcome.task_run.status,
        TaskStatus::Queued
            | TaskStatus::Running
            | TaskStatus::WaitingReview
            | TaskStatus::WaitingInput
    );
    let stop_reason = match outcome.task_run.status {
        TaskStatus::Completed => "structured_action_completed",
        TaskStatus::WaitingReview => "waiting_for_approval",
        TaskStatus::WaitingInput => "waiting_for_input",
        TaskStatus::Running => "run_in_progress",
        TaskStatus::Queued => "run_queued",
        TaskStatus::Failed => "structured_action_failed",
        TaskStatus::Cancelled => "structured_action_cancelled",
    };

    runtime_run_state(
        conversation_id,
        status,
        stop_reason,
        outcome.task_run.summary.clone(),
        resumable,
        Some(meta.task_id.clone()),
        Some(meta.module_run_id.clone()),
    )
}

#[cfg(test)]
fn direct_chat_run_state(
    conversation_id: Option<String>,
    chat_runtime_status: &str,
) -> RuntimeRunStateRecord {
    let (stop_reason, detail) = match chat_runtime_status {
        "needs_setup" => (
            "chat_runtime_needs_setup",
            "The previous turn did not start a structured run because live chat is waiting for provider configuration.",
        ),
        "degraded" => (
            "chat_runtime_degraded",
            "The previous turn did not start a structured run because the live chat request failed.",
        ),
        _ => (
            "direct_chat_reply",
            "The previous turn ended as a direct chat reply without starting a structured run.",
        ),
    };
    runtime_run_state(
        conversation_id,
        "idle",
        stop_reason,
        detail,
        false,
        None,
        None,
    )
}

fn workspace_messages_from_store(store: &RuntimeStore) -> Vec<WorkspaceChatMessage> {
    let Some(active_conversation) = store.active_conversation() else {
        return Vec::new();
    };

    active_conversation
        .messages
        .iter()
        .map(|message| WorkspaceChatMessage {
            role: message.role.clone(),
            content: message.content.clone(),
        })
        .collect()
}

#[cfg(test)]
fn update_focused_task_from_workspace_message(store: &mut RuntimeStore, message: &str) {
    let Some(task_id) = store.workspace_focus.task_id.clone() else {
        return;
    };

    let Some(task) = store.tasks.iter_mut().find(|task| task.task_id == task_id) else {
        return;
    };

    if task.status == "completed" {
        return;
    }

    task.summary = format!(
        "Updated from workspace chat: {}",
        summarize_prompt(message, 120)
    );

    match task.status.as_str() {
        "waiting_input" | "failed" => {
            task.status = "queued".to_string();
            task.current_stage = "direction_updated".to_string();
            task.progress_percent = task.progress_percent.min(84);
        }
        "waiting_review" => {
            task.current_stage = "review_pending_with_new_direction".to_string();
        }
        _ => {
            task.current_stage = "direction_updated".to_string();
        }
    }

    if let Some(module_run) = store
        .module_runs
        .iter_mut()
        .find(|module_run| module_run.module_run.task_id == task_id)
    {
        module_run.module_run.status = ModuleRunStatus::Running;
        module_run.module_run.stage = ModuleRunStage::Postprocess;
        module_run.module_run.result_summary = Some(format!(
            "Updated after new workspace direction: {}",
            summarize_prompt(message, 100)
        ));
        module_run.module_run.updated_at = "now".to_string();
    }
}

#[cfg(test)]
fn apply_workspace_message_with_steps(
    store: &mut RuntimeStore,
    surface: ExecutionSurface,
    message: &str,
    step_details: &[String],
    assistant_reply: &str,
    quick_reply: &str,
) -> Result<(), String> {
    let trimmed_message = message.trim();
    if trimmed_message.is_empty() {
        return Err("message cannot be empty".to_string());
    }

    record_live_chat_turn_with_steps(
        store,
        surface,
        trimmed_message,
        step_details,
        assistant_reply,
        "the runner produced a direct answer without dispatching a structured action",
    )?;
    store.quick_reply = quick_reply.to_string();
    update_focused_task_from_workspace_message(store, trimmed_message);

    Ok(())
}

#[cfg(test)]
#[allow(dead_code)]
fn apply_workspace_message(
    store: &mut RuntimeStore,
    surface: ExecutionSurface,
    message: &str,
    assistant_reply: &str,
    quick_reply: &str,
) -> Result<(), String> {
    let step_details = default_direct_reply_turn_steps();
    apply_workspace_message_with_steps(
        store,
        surface,
        message,
        &step_details,
        assistant_reply,
        quick_reply,
    )
}

pub fn native_bridge_get_shell_snapshot_json(
    config_dir_override: Option<PathBuf>,
) -> Result<String, String> {
    let (store, config_dir, _) = load_native_bridge_store(config_dir_override.clone())?;
    let persona_assets_root = resolve_persona_assets_root(config_dir_override.as_deref());
    let snapshot = bridge_snapshot(
        store.snapshot(),
        config_dir.as_deref(),
        persona_assets_root.as_deref(),
    );
    serde_json::to_string(&snapshot).map_err(|error| error.to_string())
}

pub fn native_bridge_list_agent_profiles_json(
    config_dir_override: Option<PathBuf>,
) -> Result<String, String> {
    let (store, config_dir, _) = load_native_bridge_store(config_dir_override.clone())?;
    let persona_assets_root = resolve_persona_assets_root(config_dir_override.as_deref());
    let profiles = store
        .agent_profiles
        .iter()
        .map(|profile| {
            bridge_agent_profile_record(
                profile,
                config_dir.as_deref(),
                persona_assets_root.as_deref(),
            )
        })
        .collect::<Vec<_>>();
    serde_json::to_string(&profiles).map_err(|error| error.to_string())
}

pub fn native_bridge_set_highest_authorization_json(
    enabled: bool,
    config_dir_override: Option<PathBuf>,
) -> Result<String, String> {
    let (store, config_dir, _) = load_native_bridge_store(config_dir_override.clone())?;
    persist_runtime_security_preferences(
        config_dir.as_deref(),
        &RuntimeSecurityPreferences {
            highest_authorization_enabled: enabled,
        },
    )?;
    let persona_assets_root = resolve_persona_assets_root(config_dir_override.as_deref());
    let snapshot = bridge_snapshot(
        store.snapshot(),
        config_dir.as_deref(),
        persona_assets_root.as_deref(),
    );
    serde_json::to_string(&snapshot).map_err(|error| error.to_string())
}

pub fn native_bridge_set_active_agent_profile_json(
    profile_id: &str,
    config_dir_override: Option<PathBuf>,
) -> Result<String, String> {
    let (mut store, config_dir, snapshot_path) =
        load_native_bridge_store(config_dir_override.clone())?;
    store.set_active_agent_profile(profile_id)?;
    let snapshot = store.snapshot();
    persist_native_bridge_store(&store, snapshot_path.as_ref())?;
    let persona_assets_root = resolve_persona_assets_root(config_dir_override.as_deref());
    let bridge_snapshot = bridge_snapshot(
        snapshot,
        config_dir.as_deref(),
        persona_assets_root.as_deref(),
    );
    serde_json::to_string(&bridge_snapshot).map_err(|error| error.to_string())
}

pub fn native_bridge_install_agent_pack_json(
    pack_root: &str,
    config_dir_override: Option<PathBuf>,
) -> Result<String, String> {
    let pack_root = PathBuf::from(pack_root.trim());
    let (mut store, config_dir, snapshot_path) =
        load_native_bridge_store(config_dir_override.clone())?;
    let config_dir = config_dir.ok_or_else(|| {
        "native bridge has no config directory; cannot install an agent definition".to_string()
    })?;
    let persona_assets_root = resolve_persona_assets_root(config_dir_override.as_deref())
        .ok_or_else(|| "could not resolve persona assets root".to_string())?;
    let snapshot =
        install_agent_pack_into_store(&pack_root, &config_dir, &persona_assets_root, &mut store)?;
    persist_native_bridge_store(&store, snapshot_path.as_ref())?;
    let bridge_snapshot = bridge_snapshot(snapshot, Some(&config_dir), Some(&persona_assets_root));
    serde_json::to_string(&bridge_snapshot).map_err(|error| error.to_string())
}

pub fn native_bridge_reload_agent_profile_json(
    profile_id: &str,
    config_dir_override: Option<PathBuf>,
) -> Result<String, String> {
    let (mut store, config_dir, snapshot_path) =
        load_native_bridge_store(config_dir_override.clone())?;
    let config_dir = config_dir.ok_or_else(|| {
        "native bridge has no config directory; cannot reload AgentProfile".to_string()
    })?;
    let persona_assets_root = resolve_persona_assets_root(config_dir_override.as_deref())
        .ok_or_else(|| "could not resolve persona assets root".to_string())?;
    let snapshot =
        reload_agent_profile_into_store(profile_id, &config_dir, &persona_assets_root, &mut store)?;
    persist_native_bridge_store(&store, snapshot_path.as_ref())?;
    let bridge_snapshot = bridge_snapshot(snapshot, Some(&config_dir), Some(&persona_assets_root));
    serde_json::to_string(&bridge_snapshot).map_err(|error| error.to_string())
}

pub fn native_bridge_delete_agent_profile_json(
    profile_id: &str,
    config_dir_override: Option<PathBuf>,
) -> Result<String, String> {
    let (mut store, config_dir, snapshot_path) =
        load_native_bridge_store(config_dir_override.clone())?;
    let config_dir = config_dir.ok_or_else(|| {
        "native bridge has no config directory; cannot delete AgentProfile".to_string()
    })?;
    let persona_assets_root = resolve_persona_assets_root(config_dir_override.as_deref())
        .ok_or_else(|| "could not resolve persona assets root".to_string())?;
    let snapshot =
        delete_agent_profile_from_store(profile_id, &config_dir, &persona_assets_root, &mut store)?;
    persist_native_bridge_store(&store, snapshot_path.as_ref())?;
    let bridge_snapshot = bridge_snapshot(snapshot, Some(&config_dir), Some(&persona_assets_root));
    serde_json::to_string(&bridge_snapshot).map_err(|error| error.to_string())
}

pub fn native_bridge_delete_terminal_access_rule_json(
    rule_id: &str,
    config_dir_override: Option<PathBuf>,
) -> Result<String, String> {
    let (store, config_dir, _) = load_native_bridge_store(config_dir_override.clone())?;
    delete_terminal_access_rule(config_dir.as_deref(), rule_id)?;
    let persona_assets_root = resolve_persona_assets_root(config_dir_override.as_deref());
    let bridge_snapshot = bridge_snapshot(
        store.snapshot(),
        config_dir.as_deref(),
        persona_assets_root.as_deref(),
    );
    serde_json::to_string(&bridge_snapshot).map_err(|error| error.to_string())
}

pub fn native_bridge_get_chat_routing_settings_json(
    config_dir_override: Option<PathBuf>,
) -> Result<String, String> {
    let (_, config_dir, _) = load_native_bridge_store(config_dir_override)?;
    let settings = load_chat_routing_settings(config_dir.as_deref())?;
    serde_json::to_string(&settings).map_err(|error| error.to_string())
}

pub fn native_bridge_save_chat_routing_settings_json(
    settings_json: &str,
    config_dir_override: Option<PathBuf>,
) -> Result<String, String> {
    let settings: ChatRoutingSettings = serde_json::from_str(settings_json)
        .map_err(|error| format!("invalid chat routing settings JSON: {error}"))?;
    let (mut store, config_dir, snapshot_path) =
        load_native_bridge_store(config_dir_override.clone())?;
    let config_dir = config_dir.ok_or_else(|| {
        "native bridge has no config directory; cannot save chat routing settings".to_string()
    })?;

    persist_chat_routing_settings(config_dir.as_path(), &settings)?;
    store.chat_runtime = startup_chat_runtime_record_from_config_dir(Some(config_dir.as_path()));
    let snapshot = store.snapshot();
    persist_native_bridge_store(&store, snapshot_path.as_ref())?;

    let persona_assets_root = resolve_persona_assets_root(config_dir_override.as_deref());
    let bridge_snapshot = bridge_snapshot(
        snapshot,
        Some(config_dir.as_path()),
        persona_assets_root.as_deref(),
    );
    serde_json::to_string(&bridge_snapshot).map_err(|error| error.to_string())
}

/// Plan 4 — Local-control butler bridge entrypoint.
///
/// Accepts a `ToolRequest` as JSON, looks up the active persona's allow-list
/// (to enforce persona gating at the backend, independent of what the frontend
/// passed in), then runs the dispatcher. The returned JSON is a fully-tagged
/// `ToolOutcome` — `{"kind":"completed","tool_id":...,"payload":{...}}` etc.
///
/// The frontend must never trust that it sent `allowed_tool_ids`; it would be
/// trivially defeated by a misbehaving tool call pathway. Always resolve the
/// allow-list from the on-disk active persona.
pub fn native_bridge_invoke_tool_json(
    request_json: &str,
    config_dir_override: Option<PathBuf>,
) -> Result<String, String> {
    let mut request: ToolRequest = serde_json::from_str(request_json)
        .map_err(|error| format!("invalid tool request JSON: {error}"))?;
    let (store, config_dir, _) = load_native_bridge_store(config_dir_override)?;
    let active = store.active_agent_profile();
    request.allowed_tool_ids = active.and_then(|profile| profile.allowed_tool_ids.clone());
    if highest_authorization_enabled(config_dir.as_deref())
        && request
            .approval_token
            .as_deref()
            .map(str::trim)
            .filter(|token| !token.is_empty())
            .is_none()
    {
        request.approval_token = Some("highest_authorization".to_string());
    }
    let outcome: ToolOutcome = invoke_tool(request);
    serde_json::to_string(&outcome).map_err(|error| error.to_string())
}

pub fn native_bridge_create_workspace_conversation_json(
    config_dir_override: Option<PathBuf>,
) -> Result<String, String> {
    let (mut store, _, snapshot_path) = load_native_bridge_store(config_dir_override)?;
    store.create_conversation(None);
    let snapshot = store.snapshot();
    persist_native_bridge_store(&store, snapshot_path.as_ref())?;
    serde_json::to_string(&snapshot).map_err(|error| error.to_string())
}

pub fn native_bridge_set_active_workspace_conversation_json(
    conversation_id: &str,
    config_dir_override: Option<PathBuf>,
) -> Result<String, String> {
    let (mut store, _, snapshot_path) = load_native_bridge_store(config_dir_override)?;
    store.set_active_conversation(conversation_id)?;
    let snapshot = store.snapshot();
    persist_native_bridge_store(&store, snapshot_path.as_ref())?;
    serde_json::to_string(&snapshot).map_err(|error| error.to_string())
}

pub fn native_bridge_delete_workspace_conversation_json(
    conversation_id: &str,
    config_dir_override: Option<PathBuf>,
) -> Result<String, String> {
    let (mut store, _, snapshot_path) = load_native_bridge_store(config_dir_override)?;
    store.delete_conversation(conversation_id)?;
    let snapshot = store.snapshot();
    persist_native_bridge_store(&store, snapshot_path.as_ref())?;
    serde_json::to_string(&snapshot).map_err(|error| error.to_string())
}

pub fn native_bridge_perform_task_action_json(
    task_id: &str,
    action: &str,
    config_dir_override: Option<PathBuf>,
) -> Result<String, String> {
    let (mut store, config_dir, snapshot_path) = load_native_bridge_store(config_dir_override)?;

    match action {
        "approve" | "allow_once" | "always_allow" | "deny" => {
            let approval_request_id = store
                .tasks
                .iter()
                .find(|task| task.task_id == task_id)
                .and_then(|task| task.approval_request_id.clone())
                .ok_or_else(|| "task does not have an open approval request".to_string())?;
            resolve_approval(
                &mut store,
                &approval_request_id,
                action,
                config_dir.as_deref(),
            )?;
        }
        "retry" => {
            let module_run_id = store
                .module_runs
                .iter()
                .find(|module_run| module_run.module_run.task_id == task_id)
                .map(|module_run| module_run.module_run.module_run_id.clone())
                .ok_or_else(|| "task does not have a recoverable module run".to_string())?;
            apply_module_recovery(&mut store, &module_run_id, "retry")?;
        }
        _ => return Err("unsupported task action".to_string()),
    }

    let snapshot = store.snapshot();
    persist_native_bridge_store(&store, snapshot_path.as_ref())?;
    serde_json::to_string(&snapshot).map_err(|error| error.to_string())
}

pub fn native_bridge_submit_workspace_message_json(
    message: &str,
    config_dir_override: Option<PathBuf>,
) -> Result<String, String> {
    let trimmed_message = message.trim().to_string();
    if trimmed_message.is_empty() {
        return Err("message cannot be empty".to_string());
    }

    let (mut store, config_dir, snapshot_path) = load_native_bridge_store(config_dir_override)?;
    let route = TurnRoute {
        mode: TurnMode::WorkspaceMessage,
        source: RuntimeRequestSource::WorkspaceChat,
        surface: ExecutionSurface::CliWorkspaceChat,
    };
    let store_snapshot = store.clone();
    let prepared = prepare_turn_context(&store_snapshot, route.clone(), &trimmed_message);
    apply_claude_sdk_turn(
        &mut store,
        &route,
        &prepared,
        &trimmed_message,
        config_dir.as_deref(),
    )?;
    let snapshot = store.snapshot();
    persist_native_bridge_store(&store, snapshot_path.as_ref())?;
    serde_json::to_string(&snapshot).map_err(|error| error.to_string())
}

pub fn native_bridge_submit_quick_prompt_json(
    prompt: &str,
    config_dir_override: Option<PathBuf>,
) -> Result<String, String> {
    let trimmed_prompt = prompt.trim().to_string();
    if trimmed_prompt.is_empty() {
        return Err("prompt cannot be empty".to_string());
    }

    let (mut store, config_dir, snapshot_path) = load_native_bridge_store(config_dir_override)?;
    let route = TurnRoute {
        mode: TurnMode::QuickPrompt,
        source: RuntimeRequestSource::QuickInput,
        surface: ExecutionSurface::CliQuickInput,
    };
    let routed_conversation = route_quick_prompt_to_best_conversation(&mut store, &trimmed_prompt);
    let is_transient = routed_conversation.is_none() && is_transient_quick_prompt(&trimmed_prompt);
    let store_snapshot = store.clone();
    let prepared = prepare_turn_context(&store_snapshot, route.clone(), &trimmed_prompt);
    if is_transient {
        apply_transient_claude_sdk_quick_turn(
            &mut store,
            &route,
            &prepared,
            &trimmed_prompt,
            config_dir.as_deref(),
        )?;
    } else {
        apply_claude_sdk_turn(
            &mut store,
            &route,
            &prepared,
            &trimmed_prompt,
            config_dir.as_deref(),
        )?;
    }
    let snapshot = store.snapshot();
    persist_native_bridge_store(&store, snapshot_path.as_ref())?;
    serde_json::to_string(&snapshot).map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use super::{
        apply_execution_outcome_to_store, apply_module_recovery, apply_quick_prompt,
        apply_workspace_message, best_quick_prompt_conversation_match,
        build_controlled_terminal_execution_outcome, build_terminal_tool_request,
        claude_sdk_runtime_provider_label, compose_claude_sdk_turn_prompt,
        context_projected_workspace_messages, default_runtime_store,
        detect_first_party_execution_from_store, detect_run_status_follow_up,
        direct_chat_run_state, ensure_workspace_runtime_catalog, execute_controlled_terminal_step,
        grounded_runtime_fact_reply, is_auto_approved_read_only_sdk_tool,
        is_transient_quick_prompt, load_native_bridge_store, load_persisted_store,
        looks_like_runtime_facts_time_request, native_bridge_delete_agent_profile_json,
        native_bridge_delete_terminal_access_rule_json, native_bridge_get_shell_snapshot_json,
        native_bridge_install_agent_pack_json, native_bridge_list_agent_profiles_json,
        native_bridge_perform_task_action_json, native_bridge_reload_agent_profile_json,
        native_bridge_set_active_agent_profile_json, native_bridge_set_highest_authorization_json,
        native_bridge_submit_quick_prompt_json, native_bridge_submit_workspace_message_json,
        normalized_pack_root, persist_store_to_disk, personalize_execution_outcome_for_agent,
        quick_input_reply, record_first_party_turn, resolve_approval,
        route_quick_prompt_to_best_conversation, runtime_run_state, seed_runtime_store,
        terminal_observation_error, upsert_terminal_access_rule, workspace_quick_reply,
        ControlledTerminalObservation, PreparedTurnContext, RuntimeConversationMessageRecord,
        RuntimeRequestOutcomeKind, RuntimeRequestOutcomeRecord, RuntimeRequestSource,
        RuntimeTaskRecord, RuntimeWorkspaceFocus, TerminalAccessDecision, TerminalAccessScope,
        TurnMode, TurnRoute, WorkspaceChatMessage, AGENT_RUNTIME_BRIDGE_MANAGER,
        CONTEXT_AUTO_SUMMARY_TRIGGER_TOKENS, CONTEXT_WINDOW_TOKENS, ITERATIVE_TURN_MAX_STEPS,
    };
    use crate::load_terminal_access_permissions;
    use agent_kernel::{AgentAppearance, AgentProfile, ProfileSource};
    use automation_engine::ScheduleCadence;
    use execution_runtime::{
        parse_local_markdown_request, parse_reminder_automation_request,
        ControlledTerminalPlanKind, ControlledTerminalRequest, ControlledTerminalStep,
        ExecutionRequestMeta, ExecutionRuntime, FirstPartyExecutionIntent, ToolOutcome,
    };
    use runtime_kernel::{
        ExecutionPlanCondition, FirstPartyRoutingDecision, KernelRun, KernelRunStatus,
    };
    use std::{
        fs,
        net::TcpListener,
        path::PathBuf,
        process::Command,
        sync::{Mutex, OnceLock},
    };
    use task_engine::{ExecutionSurface, TaskStatus, ToolInvocationStatus, TranscriptEventPayload};

    static CLAUDE_SDK_BRIDGE_TEST_ENV_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

    struct ScopedEnvOverride {
        key: &'static str,
        original: Option<String>,
    }

    impl ScopedEnvOverride {
        fn set(key: &'static str, value: impl Into<String>) -> Self {
            let original = std::env::var(key).ok();
            unsafe {
                std::env::set_var(key, value.into());
            }
            Self { key, original }
        }
    }

    impl Drop for ScopedEnvOverride {
        fn drop(&mut self) {
            match &self.original {
                Some(value) => unsafe {
                    std::env::set_var(self.key, value);
                },
                None => unsafe {
                    std::env::remove_var(self.key);
                },
            }
        }
    }

    fn with_mock_agent_runtime_bridge<T>(scenario: &str, run: impl FnOnce() -> T) -> T {
        let _guard = CLAUDE_SDK_BRIDGE_TEST_ENV_LOCK
            .get_or_init(|| Mutex::new(()))
            .lock()
            .expect("mock SDK bridge env lock should not be poisoned");
        if let Some(manager) = super::AGENT_RUNTIME_BRIDGE_MANAGER.get() {
            manager
                .lock()
                .expect("mock bridge manager should not be poisoned")
                .sessions
                .clear();
        }
        let fixture_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("src");
        let entrypoint = fixture_dir.join("mock_agent_runtime_bridge.js");
        let _bridge_dir = ScopedEnvOverride::set(
            "GEEAGENT_AGENT_RUNTIME_BRIDGE_DIR",
            fixture_dir.to_string_lossy().to_string(),
        );
        let _bridge_entrypoint = ScopedEnvOverride::set(
            "GEEAGENT_AGENT_RUNTIME_BRIDGE_ENTRYPOINT",
            entrypoint.to_string_lossy().to_string(),
        );
        let _xenodia_key = ScopedEnvOverride::set("XENODIA_API_KEY", "mock-xenodia-key");
        let _scenario =
            ScopedEnvOverride::set("GEEAGENT_MOCK_CLAUDE_SDK_SCENARIO", scenario.to_string());
        let result = run();
        if let Some(manager) = super::AGENT_RUNTIME_BRIDGE_MANAGER.get() {
            manager
                .lock()
                .expect("mock bridge manager should not be poisoned")
                .sessions
                .clear();
        }
        result
    }

    fn native_bridge_result<T>(result: Result<T, String>) -> Result<T, String> {
        result
    }

    fn oversized_workspace_context_messages() -> Vec<WorkspaceChatMessage> {
        (0..20)
            .map(|index| WorkspaceChatMessage {
                role: if index % 2 == 0 {
                    "user".to_string()
                } else {
                    "assistant".to_string()
                },
                content: if index < 8 {
                    format!("older-context-marker-{index} {}", "旧上下文".repeat(12_000))
                } else {
                    format!("recent-context-marker-{index}")
                },
            })
            .collect()
    }

    #[test]
    fn default_runtime_store_starts_as_a_clean_workspace() {
        let store = default_runtime_store();

        assert!(store.tasks.is_empty());
        assert!(store.module_runs.is_empty());
        assert!(store.approval_requests.is_empty());
        assert!(store.automations.is_empty());
        assert_eq!(store.workspace_focus.mode, "default");
        assert_eq!(store.workspace_focus.task_id, None);
        assert_eq!(store.active_conversation_id, "conv_01");
        assert_eq!(store.conversations.len(), 1);
        assert_eq!(store.conversations[0].title, "New Conversation");
        assert_eq!(store.conversations[0].messages.len(), 1);
        assert_eq!(store.active_agent_profile_id, "gee");
        assert_eq!(
            store
                .active_agent_profile()
                .expect("default runtime store should have an active agent profile")
                .id,
            "gee"
        );
    }

    #[test]
    fn runtime_snapshot_includes_the_active_agent_profile() {
        let snapshot = serde_json::to_value(default_runtime_store().snapshot())
            .expect("snapshot should serialize");

        assert_eq!(
            snapshot["active_agent_profile"]["id"],
            serde_json::json!("gee")
        );
        assert_eq!(
            snapshot["active_agent_profile"]["source"],
            serde_json::json!("first_party")
        );
        let profiles = snapshot["agent_profiles"]
            .as_array()
            .expect("snapshot should emit agent_profiles as an array");
        assert!(
            profiles
                .iter()
                .any(|entry| entry["id"] == serde_json::json!("gee")),
            "snapshot agent_profiles should include the bundled gee profile"
        );
    }

    #[test]
    fn quick_prompt_records_execution_session_and_append_only_transcript_events() {
        let mut store = default_runtime_store();

        apply_quick_prompt(
            &mut store,
            ExecutionSurface::DesktopQuickInput,
            "3*7+2 = ?",
            "3*7+2 equals 23.",
            "Ready.",
        )
        .expect("quick prompt should apply");

        assert_eq!(store.execution_sessions.len(), 1);
        assert_eq!(store.execution_sessions[0].session_id, "session_conv_01");
        assert_eq!(store.transcript_events.len(), 5);
        assert_eq!(
            store.transcript_events[0].parent_event_id, None,
            "the first transcript event should start a new append-only chain"
        );
        assert_eq!(
            store.transcript_events[4].parent_event_id.as_deref(),
            Some(store.transcript_events[3].event_id.as_str())
        );
        assert!(matches!(
            &store.transcript_events[0].payload,
            TranscriptEventPayload::UserMessage { content, .. }
                if content.contains("3*7+2")
        ));
        assert!(matches!(
            &store.transcript_events[1].payload,
            TranscriptEventPayload::SessionStateChanged { summary }
                if summary.contains("Turn setup complete")
        ));
        assert!(matches!(
            &store.transcript_events[2].payload,
            TranscriptEventPayload::SessionStateChanged { summary }
                if summary.contains("Step 1/")
        ));
        assert!(matches!(
            &store.transcript_events[3].payload,
            TranscriptEventPayload::AssistantMessage { content, .. }
                if content.contains("23")
        ));
        assert!(matches!(
            &store.transcript_events[4].payload,
            TranscriptEventPayload::SessionStateChanged { summary }
                if summary.contains("Turn finalized")
        ));
    }

    #[test]
    fn first_party_local_execution_records_tool_invocation_and_result_trace() {
        let mut store = default_runtime_store();
        let execution_runtime = ExecutionRuntime::for_local_system();
        let outcome = execution_runtime.execute_first_party(
            &FirstPartyExecutionIntent::CreateReminderAutomation(
                parse_reminder_automation_request("明天8点提醒我上课")
                    .expect("parse should succeed"),
            ),
            &ExecutionRequestMeta {
                task_id: "task_quick_01".to_string(),
                module_run_id: "run_quick_01".to_string(),
                conversation_id: Some("conv_01".to_string()),
                title: "Quick reminder".to_string(),
                prompt: "明天8点提醒我上课".to_string(),
                created_at: "now".to_string(),
                updated_at: "now".to_string(),
            },
        );
        let assistant_reply = outcome.assistant_reply.clone();

        record_first_party_turn(
            &mut store,
            ExecutionSurface::DesktopQuickInput,
            "明天8点提醒我上课",
            &assistant_reply,
            &outcome,
        )
        .expect("first-party turn should record");

        assert_eq!(store.transcript_events.len(), 9);
        assert!(matches!(
            &store.transcript_events[1].payload,
            TranscriptEventPayload::SessionStateChanged { summary }
                if summary.contains("Turn setup complete")
        ));
        assert!(matches!(
            &store.transcript_events[2].payload,
            TranscriptEventPayload::SessionStateChanged { summary }
                if summary.contains("Step 1/")
        ));
        assert!(matches!(
            &store.transcript_events[3].payload,
            TranscriptEventPayload::SessionStateChanged { summary }
                if summary.contains("Step 2/")
        ));
        assert!(matches!(
            &store.transcript_events[4].payload,
            TranscriptEventPayload::SessionStateChanged { summary }
                if summary.contains("Step 3/")
        ));
        assert!(matches!(
            &store.transcript_events[5].payload,
            TranscriptEventPayload::ToolInvocation { invocation }
                if invocation.invocation_id == "toolinv_run_quick_01"
                    && invocation.originating_message_id == "msg_user_02"
                    && invocation.input_summary.as_deref() == Some("明天8点提醒我上课")
        ));
        assert!(matches!(
            &store.transcript_events[6].payload,
            TranscriptEventPayload::ToolResult { summary, artifacts, .. }
                if summary
                    .as_deref()
                    .unwrap_or_default()
                    .contains("Created reminder automation")
                    && !artifacts.is_empty()
        ));
        assert!(matches!(
            &store.transcript_events[7].payload,
            TranscriptEventPayload::AssistantMessage { content, .. }
                if content.contains("提醒")
        ));
        assert!(matches!(
            &store.transcript_events[8].payload,
            TranscriptEventPayload::SessionStateChanged { summary }
                if summary.contains("Turn finalized")
        ));
    }

    #[test]
    fn native_bridge_lists_profiles_and_persists_active_profile_selection() {
        let temp_dir = tempfile::tempdir().expect("tempdir should create");
        let profiles_dir = temp_dir.path().join("agents");
        std::fs::create_dir_all(&profiles_dir).expect("profiles dir should create");
        std::fs::write(
            profiles_dir.join("companion.json"),
            r#"{
                "id": "companion",
                "name": "Companion",
                "tagline": "Warm follow-through",
                "personality_prompt": "Keep track of open ends and offer follow-through.",
                "appearance": { "kind": "abstract" },
                "skills": [{ "id": "workspace.follow_up" }],
                "source": "user_created",
                "version": "1.0.0"
            }"#,
        )
        .expect("profile should write");

        let raw_profiles =
            native_bridge_list_agent_profiles_json(Some(temp_dir.path().to_path_buf()))
                .expect("list agent profiles should return json");
        let profiles: serde_json::Value =
            serde_json::from_str(&raw_profiles).expect("profiles json should parse");

        assert_eq!(
            profiles.as_array().map(|entries| entries.len()),
            Some(2),
            "bundled gee plus the user profile should be listed"
        );
        assert!(profiles
            .as_array()
            .expect("profiles should be an array")
            .iter()
            .any(|entry| entry["id"] == serde_json::json!("gee")));
        assert!(profiles
            .as_array()
            .expect("profiles should be an array")
            .iter()
            .any(|entry| entry["id"] == serde_json::json!("companion")));

        let raw_snapshot = native_bridge_set_active_agent_profile_json(
            "companion",
            Some(temp_dir.path().to_path_buf()),
        )
        .expect("set active profile should return a snapshot");
        let snapshot: serde_json::Value =
            serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");
        assert_eq!(
            snapshot["active_agent_profile"]["id"],
            serde_json::json!("companion")
        );

        let reloaded_snapshot =
            native_bridge_get_shell_snapshot_json(Some(temp_dir.path().to_path_buf()))
                .expect("snapshot reload should succeed");
        let reloaded_snapshot: serde_json::Value =
            serde_json::from_str(&reloaded_snapshot).expect("snapshot json should parse");
        assert_eq!(
            reloaded_snapshot["active_agent_profile"]["id"],
            serde_json::json!("companion")
        );
    }

    #[test]
    fn native_bridge_install_agent_pack_materializes_profile_and_refreshes_snapshot() {
        let temp_dir = tempfile::tempdir().expect("tempdir should create");
        let pack_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../../examples/agent-packs/companion-sora");

        let raw_snapshot = native_bridge_install_agent_pack_json(
            pack_root.to_str().expect("pack root should be utf8"),
            Some(temp_dir.path().to_path_buf()),
        )
        .expect("install should succeed");

        let snapshot: serde_json::Value =
            serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");
        let profiles = snapshot["agent_profiles"]
            .as_array()
            .expect("snapshot should carry agent_profiles");
        assert!(
            profiles
                .iter()
                .any(|profile| profile["id"] == serde_json::json!("companion-sora")),
            "installed snapshot should include the imported pack profile"
        );

        let installed_profile_path = temp_dir.path().join("agents/companion-sora.json");
        assert!(
            installed_profile_path.is_file(),
            "install should materialize a runtime profile json under config_dir/agents"
        );

        let workspace_root = temp_dir.path().join("Personas/companion-sora");
        assert!(workspace_root.join("agent.json").is_file());
        assert!(workspace_root.join("identity-prompt.md").is_file());
        assert!(workspace_root.join("soul.md").is_file());
        assert!(workspace_root.join("playbook.md").is_file());
        assert!(workspace_root.join("appearance/hero.png").is_file());

        let imported_profile = profiles
            .iter()
            .find(|profile| profile["id"] == serde_json::json!("companion-sora"))
            .expect("installed profile should be listed");
        assert_eq!(
            imported_profile["file_state"]["soul_path"],
            serde_json::json!(workspace_root.join("soul.md").to_string_lossy().to_string())
        );
        assert_eq!(
            imported_profile["file_state"]["playbook_path"],
            serde_json::json!(workspace_root
                .join("playbook.md")
                .to_string_lossy()
                .to_string())
        );
    }

    #[test]
    fn normalized_pack_root_ignores_macos_metadata_entries() {
        let temp_dir = tempfile::tempdir().expect("tempdir should create");
        let wrapper_root = temp_dir.path().join("wrapped-pack");
        std::fs::create_dir_all(&wrapper_root).expect("wrapper dir");
        std::fs::create_dir_all(temp_dir.path().join("__MACOSX")).expect("metadata dir");
        std::fs::write(wrapper_root.join("agent.json"), "{}").expect("manifest");
        std::fs::write(temp_dir.path().join(".DS_Store"), b"junk").expect("ds store");

        let normalized =
            normalized_pack_root(temp_dir.path()).expect("wrapper dir should normalize");
        assert_eq!(normalized, wrapper_root);
    }

    #[test]
    fn native_bridge_install_agent_pack_accepts_zip_archives() {
        let temp_dir = tempfile::tempdir().expect("tempdir should create");
        let pack_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../../examples/agent-packs/companion-sora");
        let zip_path = temp_dir.path().join("companion-sora.zip");

        let output = Command::new("/usr/bin/ditto")
            .arg("-c")
            .arg("-k")
            .arg("--keepParent")
            .arg(&pack_root)
            .arg(&zip_path)
            .output()
            .expect("ditto should spawn");
        assert!(
            output.status.success(),
            "zip build failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );

        let raw_snapshot = native_bridge_install_agent_pack_json(
            zip_path.to_str().expect("zip path should be utf8"),
            Some(temp_dir.path().to_path_buf()),
        )
        .expect("zip install should succeed");

        let snapshot: serde_json::Value =
            serde_json::from_str(&raw_snapshot).expect("snapshot should parse");
        assert!(snapshot["agent_profiles"]
            .as_array()
            .expect("profiles array")
            .iter()
            .any(|profile| profile["id"] == serde_json::json!("companion-sora")));
    }

    #[test]
    fn native_bridge_reload_agent_profile_rebuilds_runtime_json_from_workspace() {
        let temp_dir = tempfile::tempdir().expect("tempdir should create");
        let pack_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../../examples/agent-packs/companion-sora");

        native_bridge_install_agent_pack_json(
            pack_root.to_str().expect("pack root should be utf8"),
            Some(temp_dir.path().to_path_buf()),
        )
        .expect("install should succeed");

        let workspace_prompt = temp_dir
            .path()
            .join("Personas/companion-sora/identity-prompt.md");
        std::fs::write(
            &workspace_prompt,
            "You are a reloaded local persona definition.\n",
        )
        .expect("prompt should update");

        native_bridge_reload_agent_profile_json(
            "companion-sora",
            Some(temp_dir.path().to_path_buf()),
        )
        .expect("reload should succeed");

        let runtime_profile: serde_json::Value = serde_json::from_str(
            &std::fs::read_to_string(temp_dir.path().join("agents/companion-sora.json"))
                .expect("runtime profile should exist"),
        )
        .expect("runtime profile json should parse");
        let personality_prompt = runtime_profile["personality_prompt"]
            .as_str()
            .expect("compiled prompt should be a string");
        assert!(personality_prompt.contains("[IDENTITY]"));
        assert!(personality_prompt.contains("You are a reloaded local persona definition."));
        assert!(personality_prompt.contains("[SOUL]"));
        assert!(personality_prompt.contains("[PLAYBOOK]"));
    }

    #[test]
    fn native_bridge_install_agent_pack_rejects_legacy_v1_manifests() {
        let temp_dir = tempfile::tempdir().expect("tempdir should create");
        let legacy_root = temp_dir.path().join("legacy-pack");
        std::fs::create_dir_all(legacy_root.join("appearance")).expect("appearance");
        std::fs::write(
            legacy_root.join("agent.json"),
            r#"{
                "pack_version": "1",
                "id": "legacy",
                "name": "Legacy",
                "tagline": "Old format",
                "identity_prompt_path": "identity-prompt.md",
                "appearance": { "kind": "static_image", "asset_path": "appearance/hero.png" },
                "source": "module_pack",
                "version": "1.0.0"
            }"#,
        )
        .expect("manifest");
        std::fs::write(legacy_root.join("identity-prompt.md"), "legacy").expect("identity");
        std::fs::write(legacy_root.join("appearance/hero.png"), b"png").expect("hero");

        let error = native_bridge_install_agent_pack_json(
            legacy_root.to_str().expect("legacy root should be utf8"),
            Some(temp_dir.path().to_path_buf()),
        )
        .expect_err("legacy packs should be rejected");
        assert!(
            error.contains("[pack.missing_definition_version]"),
            "unexpected error: {error}"
        );
    }

    #[test]
    fn native_bridge_delete_agent_profile_removes_workspace_and_runtime_copy() {
        let temp_dir = tempfile::tempdir().expect("tempdir should create");
        let pack_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../../examples/agent-packs/companion-sora");

        native_bridge_install_agent_pack_json(
            pack_root.to_str().expect("pack root should be utf8"),
            Some(temp_dir.path().to_path_buf()),
        )
        .expect("install should succeed");

        native_bridge_set_active_agent_profile_json(
            "companion-sora",
            Some(temp_dir.path().to_path_buf()),
        )
        .expect("active profile should switch");

        let raw_snapshot = native_bridge_delete_agent_profile_json(
            "companion-sora",
            Some(temp_dir.path().to_path_buf()),
        )
        .expect("delete should succeed");

        let snapshot: serde_json::Value =
            serde_json::from_str(&raw_snapshot).expect("snapshot should parse");
        assert_eq!(
            snapshot["active_agent_profile"]["id"],
            serde_json::json!("gee")
        );
        assert!(!temp_dir.path().join("agents/companion-sora.json").exists());
        assert!(!temp_dir.path().join("Personas/companion-sora").exists());
    }

    #[test]
    fn runtime_snapshot_carries_workspace_catalogs_from_the_facade() {
        let snapshot = serde_json::to_value(default_runtime_store().snapshot())
            .expect("snapshot should serialize");

        assert_eq!(
            snapshot["workspace_runtime"]["sections"],
            serde_json::json!(["home", "chat", "tasks", "automations", "apps", "settings"])
        );
        assert_eq!(
            snapshot["workspace_runtime"]["apps"][0]["app_id"],
            serde_json::json!("media.library")
        );
        assert_eq!(
            snapshot["workspace_runtime"]["apps"]
                .as_array()
                .unwrap()
                .len(),
            1
        );
        assert_eq!(
            snapshot["workspace_runtime"]["agent_skins"][0]["skin_id"],
            serde_json::json!("default.operator")
        );
    }

    #[test]
    fn workspace_catalog_reconciles_persisted_stores_with_new_builtin_apps() {
        let mut store = default_runtime_store();
        store
            .workspace_runtime
            .as_mut()
            .expect("workspace runtime should exist")
            .apps
            .retain(|app| app.app_id == "media.playlists");

        ensure_workspace_runtime_catalog(&mut store);

        let snapshot = serde_json::to_value(store.snapshot()).expect("snapshot should serialize");
        assert_eq!(
            snapshot["workspace_runtime"]["apps"]
                .as_array()
                .unwrap()
                .len(),
            1
        );
        assert_eq!(
            snapshot["workspace_runtime"]["apps"][0]["app_id"],
            serde_json::json!("media.library")
        );
        assert_eq!(
            snapshot["workspace_runtime"]["apps"][0]["display_mode"],
            serde_json::json!("full_canvas")
        );
    }

    #[test]
    fn runtime_snapshot_exposes_desktop_interaction_capabilities() {
        let snapshot = serde_json::to_value(default_runtime_store().snapshot())
            .expect("snapshot should serialize");

        assert_eq!(
            snapshot["interaction_capabilities"]["surface"],
            serde_json::json!("desktop_live")
        );
        assert_eq!(
            snapshot["interaction_capabilities"]["can_send_messages"],
            serde_json::json!(true)
        );
        assert_eq!(
            snapshot["interaction_capabilities"]["can_use_quick_input"],
            serde_json::json!(true)
        );
        assert_eq!(
            snapshot["interaction_capabilities"]["can_mutate_runtime"],
            serde_json::json!(true)
        );
        assert_eq!(
            snapshot["interaction_capabilities"]["can_run_first_party_actions"],
            serde_json::json!(true)
        );
        assert_eq!(snapshot["last_request_outcome"], serde_json::Value::Null);
    }

    #[test]
    fn runtime_snapshot_serializes_structured_request_outcomes() {
        let mut store = default_runtime_store();
        store.last_request_outcome = Some(RuntimeRequestOutcomeRecord {
            source: RuntimeRequestSource::QuickInput,
            kind: RuntimeRequestOutcomeKind::FirstPartyAction,
            detail: "Created 123.md on the Desktop.".to_string(),
            task_id: Some("task_local_md".to_string()),
            module_run_id: Some("run_local_md".to_string()),
        });

        let snapshot = serde_json::to_value(store.snapshot()).expect("snapshot should serialize");

        assert_eq!(
            snapshot["last_request_outcome"]["source"],
            serde_json::json!("quick_input")
        );
        assert_eq!(
            snapshot["last_request_outcome"]["kind"],
            serde_json::json!("first_party_action")
        );
        assert_eq!(
            snapshot["last_request_outcome"]["task_id"],
            serde_json::json!("task_local_md")
        );
        assert_eq!(
            snapshot["last_request_outcome"]["module_run_id"],
            serde_json::json!("run_local_md")
        );
    }

    #[test]
    fn run_status_follow_up_reports_when_no_real_run_exists() {
        let mut store = default_runtime_store();
        store.last_run_state = Some(direct_chat_run_state(
            Some(store.active_conversation_id.clone()),
            "live",
        ));

        let follow_up = detect_run_status_follow_up(&store, "结果如何？")
            .expect("status follow-up should be detected");

        assert!(follow_up
            .assistant_reply
            .contains("did not start a local run"));
        assert_eq!(follow_up.run_state.stop_reason, "no_active_run");
        assert!(!follow_up.run_state.resumable);
    }

    #[test]
    fn run_status_follow_up_uses_real_task_state_when_available() {
        let mut store = seed_runtime_store().expect("fixture should parse");
        store.last_run_state = Some(runtime_run_state(
            Some(store.active_conversation_id.clone()),
            "running",
            "run_in_progress",
            "The upstream module accepted the run and is still processing the request.",
            true,
            Some("task_digest_youtube".to_string()),
            Some("run_digest_01".to_string()),
        ));

        let follow_up = detect_run_status_follow_up(&store, "进展如何？")
            .expect("status follow-up should be detected");

        assert!(follow_up.assistant_reply.contains("still in progress"));
        assert_eq!(
            follow_up.run_state.task_id.as_deref(),
            Some("task_digest_youtube")
        );
        assert!(follow_up.run_state.resumable);
    }

    #[test]
    fn run_status_follow_up_prefers_kernel_truth_over_stale_projection() {
        let mut store = default_runtime_store();
        store.tasks.push(RuntimeTaskRecord {
            task_id: "task_kernel_demo".to_string(),
            conversation_id: Some("conv_01".to_string()),
            title: "Inspect local docker state".to_string(),
            summary: "Kernel-backed terminal inspection is still running.".to_string(),
            current_stage: "dispatch".to_string(),
            status: "running".to_string(),
            importance_level: "important".to_string(),
            progress_percent: 48,
            artifact_count: 0,
            approval_request_id: None,
        });
        store.last_run_state = Some(runtime_run_state(
            Some("conv_01".to_string()),
            "idle",
            "direct_chat_reply",
            "This stale projection should not win over kernel truth.",
            false,
            None,
            None,
        ));

        let session_id = store
            .ensure_kernel_session_for_active_conversation(ExecutionSurface::DesktopWorkspaceChat)
            .expect("active conversation should exist");
        let runtime = store
            .kernel_session_runtime_mut(&session_id)
            .expect("kernel runtime should exist");
        runtime.start_run(
            KernelRun {
                run_id: "krun_task_kernel_demo".to_string(),
                session_id: session_id.clone(),
                origin_message_id: "msg_user_01".to_string(),
                status: KernelRunStatus::Running,
                started_at: "now".to_string(),
                updated_at: "now".to_string(),
                step_count: 0,
                max_steps: ITERATIVE_TURN_MAX_STEPS as u32,
                run_kind: Some("controlled_terminal".to_string()),
                active_step_id: None,
                parent_run_id: None,
                interrupt_id: None,
                stop_reason: Some("kernel_run_in_progress".to_string()),
                final_output_ref: None,
                error_summary: None,
            },
            "kevent_test_run_created",
        );

        let follow_up = detect_run_status_follow_up(&store, "结果如何？")
            .expect("status follow-up should be detected");

        assert!(follow_up.assistant_reply.contains("still in progress"));
        assert_eq!(
            follow_up.run_state.task_id.as_deref(),
            Some("task_kernel_demo")
        );
        assert_eq!(follow_up.run_state.status, "running");
    }

    #[test]
    fn run_status_follow_up_does_not_bleed_into_a_new_conversation() {
        let mut store = default_runtime_store();
        store.last_run_state = Some(runtime_run_state(
            Some(store.active_conversation_id.clone()),
            "running",
            "run_in_progress",
            "A local run is still active in the original conversation.",
            true,
            Some("task_demo".to_string()),
            Some("run_demo".to_string()),
        ));

        store.create_conversation(Some("Fresh thread".to_string()));

        let follow_up = detect_run_status_follow_up(&store, "结果如何？")
            .expect("status follow-up should be detected");

        assert_eq!(follow_up.run_state.stop_reason, "no_active_run");
        assert!(follow_up
            .assistant_reply
            .contains("There is no ongoing local run"));
    }

    #[test]
    fn runtime_fact_reply_follow_up_stays_grounded() {
        let mut store = default_runtime_store();
        store.last_run_state = Some(runtime_run_state(
            Some(store.active_conversation_id.clone()),
            "idle",
            "runtime_fact_reply",
            "The previous turn answered directly from turn setup runtime facts.",
            false,
            None,
            None,
        ));

        let follow_up = detect_run_status_follow_up(&store, "结果如何？")
            .expect("status follow-up should be detected");

        assert_eq!(follow_up.run_state.stop_reason, "runtime_fact_reply");
        assert!(follow_up
            .assistant_reply
            .contains("The previous turn answered directly from turn setup runtime facts"));
    }

    #[test]
    fn quick_prompt_adds_messages_and_creates_a_new_task() {
        let mut store = seed_runtime_store().expect("fixture should parse");
        let original_message_count = store
            .active_conversation()
            .map(|conversation| conversation.messages.len())
            .unwrap_or_default();
        let original_task_count = store.tasks.len();

        apply_quick_prompt(
            &mut store,
            ExecutionSurface::DesktopQuickInput,
            "Review the latest MKBHD upload and tell me if it should become a saved note.",
            "I captured that request, opened a fresh task in the workspace, and will call you back if it needs review.",
            &quick_input_reply(
                "xenodia",
                "I captured that request, opened a fresh task in the workspace, and will call you back if it needs review.",
                &crate::default_runtime_agent_profile(),
            ),
        )
        .expect("quick prompt should apply");

        assert_eq!(
            store
                .active_conversation()
                .map(|conversation| conversation.messages.len())
                .unwrap_or_default(),
            original_message_count + 2
        );
        assert_eq!(store.tasks.len(), original_task_count + 1);
        assert_eq!(store.tasks[0].status, "queued");
        assert_eq!(store.workspace_focus.mode, "task");
        assert_eq!(
            store.workspace_focus.task_id.as_deref(),
            Some("task_quick_05")
        );
        assert_eq!(store.module_runs.len(), 3);
        assert_eq!(store.module_runs[0].module_run.task_id, "task_quick_05");
        assert_eq!(
            store.module_runs[0].module_run.status,
            module_gateway::ModuleRunStatus::Queued
        );
        assert!(store.quick_reply.contains("Quick reply via xenodia"));
    }

    #[test]
    fn quick_prompt_keeps_simple_answers_out_of_the_task_board() {
        let mut store = seed_runtime_store().expect("fixture should parse");
        let original_task_count = store.tasks.len();

        apply_quick_prompt(
            &mut store,
            ExecutionSurface::DesktopQuickInput,
            "3*7+2 = ?",
            "3*7+2 equals 23.",
            &quick_input_reply(
                "xenodia",
                "3*7+2 equals 23.",
                &crate::default_runtime_agent_profile(),
            ),
        )
        .expect("quick prompt should apply");

        assert_eq!(store.tasks.len(), original_task_count);
        assert_eq!(store.workspace_focus.mode, "default");
        assert_eq!(store.workspace_focus.task_id, None);
        assert!(store.quick_reply.contains("23"));
    }

    #[test]
    fn quick_prompt_turns_chinese_reminders_into_tasks() {
        let mut store = seed_runtime_store().expect("fixture should parse");
        let original_task_count = store.tasks.len();

        apply_quick_prompt(
            &mut store,
            ExecutionSurface::DesktopQuickInput,
            "明天8点通知我吃药💊",
            "好的，我会为你安排一个提醒任务。",
            &quick_input_reply(
                "xenodia",
                "好的，我会为你安排一个提醒任务。",
                &crate::default_runtime_agent_profile(),
            ),
        )
        .expect("quick prompt should apply");

        assert_eq!(store.tasks.len(), original_task_count + 1);
        assert_eq!(store.tasks[0].status, "queued");
        assert_eq!(store.workspace_focus.mode, "task");
        assert!(store.tasks[0].title.contains("明天8点通知我吃药"));
    }

    #[test]
    fn local_markdown_request_creates_a_desktop_file_in_the_target_directory() {
        let request = parse_local_markdown_request("在桌面创建一个md文档，空白内容，名称123")
            .expect("request should parse");
        let temp_dir = tempfile::tempdir().expect("tempdir should create");
        let runtime = ExecutionRuntime::with_desktop_directory(temp_dir.path().join("Desktop"));
        let outcome = runtime.execute_first_party(
            &FirstPartyExecutionIntent::CreateDesktopMarkdown(request),
            &ExecutionRequestMeta {
                task_id: "task_01".to_string(),
                module_run_id: "run_01".to_string(),
                conversation_id: Some("conv_01".to_string()),
                title: "Quick request: 在桌面创建一个md文档，空白内容，名称123".to_string(),
                prompt: "在桌面创建一个md文档，空白内容，名称123".to_string(),
                created_at: "now".to_string(),
                updated_at: "now".to_string(),
            },
        );

        assert_eq!(outcome.task_run.status, task_engine::TaskStatus::Completed);
        assert!(
            temp_dir.path().join("Desktop").join("123.md").exists(),
            "expected markdown file to be created"
        );
    }

    #[test]
    fn personalize_execution_outcome_prefixes_the_active_agent_name() {
        let profile = AgentProfile {
            id: "nyko".to_string(),
            name: "Nyko".to_string(),
            tagline: "Playful follow-through".to_string(),
            personality_prompt: "Stay playful but finish the task.".to_string(),
            appearance: AgentAppearance::Abstract,
            skills: Vec::new(),
            allowed_tool_ids: None,
            source: ProfileSource::UserCreated,
            version: "2".to_string(),
        };
        let request = parse_local_markdown_request("在桌面创建一个md文档，空白内容，名称123")
            .expect("request should parse");
        let temp_dir = tempfile::tempdir().expect("tempdir should create");
        let runtime = ExecutionRuntime::with_desktop_directory(temp_dir.path().join("Desktop"));
        let mut outcome = runtime.execute_first_party(
            &FirstPartyExecutionIntent::CreateDesktopMarkdown(request),
            &ExecutionRequestMeta {
                task_id: "task_01".to_string(),
                module_run_id: "run_01".to_string(),
                conversation_id: Some("conv_01".to_string()),
                title: "Quick request: 在桌面创建一个md文档，空白内容，名称123".to_string(),
                prompt: "在桌面创建一个md文档，空白内容，名称123".to_string(),
                created_at: "now".to_string(),
                updated_at: "now".to_string(),
            },
        );

        personalize_execution_outcome_for_agent(&mut outcome, &profile);

        assert!(outcome
            .assistant_reply
            .starts_with("Nyko handled that locally."));
        assert!(outcome.quick_reply.starts_with("Nyko · "));
    }

    #[test]
    fn affirmation_reuses_the_recent_local_markdown_request_from_conversation_context() {
        let mut store = default_runtime_store();
        store.create_conversation(Some("Desktop test".to_string()));
        if let Some(active_conversation) = store.active_conversation_mut() {
            active_conversation
                .messages
                .push(RuntimeConversationMessageRecord {
                    message_id: "msg_user_01".to_string(),
                    role: "user".to_string(),
                    content: "在桌面创建一个md文档，空白内容，名称123".to_string(),
                    timestamp: "now".to_string(),
                });
        }
        store.tasks.push(RuntimeTaskRecord {
            task_id: "task_local_md".to_string(),
            conversation_id: Some(store.active_conversation_id.clone()),
            title: "Quick request: 在桌面创建一个md文档，空白内容，名称123".to_string(),
            summary: "Ready to execute a local markdown write.".to_string(),
            current_stage: "awaiting_execution".to_string(),
            status: "waiting_input".to_string(),
            importance_level: "important".to_string(),
            progress_percent: 52,
            artifact_count: 0,
            approval_request_id: None,
        });
        store.workspace_focus = RuntimeWorkspaceFocus {
            mode: "task".to_string(),
            task_id: Some("task_local_md".to_string()),
        };

        let plan = detect_first_party_execution_from_store(&store, "可以，执行吧")
            .expect("affirmation should resolve into a local markdown action plan");

        match plan {
            FirstPartyRoutingDecision::Execute(plan) => {
                assert_eq!(plan.target_task_id.as_deref(), Some("task_local_md"));
                match plan.steps.as_slice() {
                    [runtime_kernel::ExecutionPlanStep {
                        intent: FirstPartyExecutionIntent::CreateDesktopMarkdown(request),
                        condition: ExecutionPlanCondition::Always,
                    }] => {
                        assert_eq!(request.file_name, "123.md");
                    }
                    _ => panic!("expected local markdown intent"),
                }
            }
            _ => panic!("expected execution plan"),
        }
    }

    #[test]
    fn reminder_execution_outcome_adds_an_automation_to_the_store() {
        let mut store = default_runtime_store();
        let runtime = ExecutionRuntime::for_local_system();
        let outcome = runtime.execute_first_party(
            &FirstPartyExecutionIntent::CreateReminderAutomation(
                parse_reminder_automation_request("明天8点通知我吃药💊")
                    .expect("reminder request should parse"),
            ),
            &ExecutionRequestMeta {
                task_id: "task_reminder_01".to_string(),
                module_run_id: "run_reminder_01".to_string(),
                conversation_id: Some("conv_01".to_string()),
                title: "Quick request: 明天8点通知我吃药💊".to_string(),
                prompt: "明天8点通知我吃药💊".to_string(),
                created_at: "now".to_string(),
                updated_at: "now".to_string(),
            },
        );

        apply_execution_outcome_to_store(&mut store, outcome);

        assert_eq!(store.automations.len(), 1);
        assert_eq!(store.automations[0].cadence, ScheduleCadence::Once);
        assert_eq!(store.automations[0].time_of_day, "08:00");
        assert_eq!(
            store.automations[0].schedule_hint.as_deref(),
            Some("Tomorrow")
        );
        assert_eq!(store.tasks[0].status, "completed");
        assert_eq!(
            store.module_runs[0].module_run.module_id,
            "geeagent.local.automation"
        );
    }

    #[test]
    fn reminder_request_is_detected_as_first_party_execution() {
        let store = default_runtime_store();
        let plan = detect_first_party_execution_from_store(&store, "明天8点通知我吃药💊")
            .expect("reminder prompt should resolve");

        match plan {
            FirstPartyRoutingDecision::Execute(plan) => match plan.steps.as_slice() {
                [runtime_kernel::ExecutionPlanStep {
                    intent: FirstPartyExecutionIntent::CreateReminderAutomation(request),
                    condition: ExecutionPlanCondition::Always,
                }] => {
                    assert_eq!(request.time_of_day, "08:00");
                }
                _ => panic!("expected reminder automation intent"),
            },
            _ => panic!("expected reminder execution decision"),
        }
    }

    #[test]
    fn reminder_clarification_is_detected_from_store() {
        let store = default_runtime_store();
        let decision = detect_first_party_execution_from_store(&store, "创建一个任务，提醒我吃药")
            .expect("reminder prompt should ask for clarification");

        match decision {
            FirstPartyRoutingDecision::Clarify(clarification) => {
                assert!(clarification.assistant_reply.contains("缺少时间"));
                assert!(clarification.quick_reply.contains("needs a time"));
            }
            _ => panic!("expected clarification decision"),
        }
    }

    #[test]
    fn reminder_follow_up_from_store_becomes_first_party_execution() {
        let mut store = default_runtime_store();
        if let Some(active_conversation) = store.active_conversation_mut() {
            active_conversation
                .messages
                .push(RuntimeConversationMessageRecord {
                    message_id: "msg_user_01".to_string(),
                    role: "user".to_string(),
                    content: "创建一个任务，提醒我吃药".to_string(),
                    timestamp: "now".to_string(),
                });
        }

        let decision = detect_first_party_execution_from_store(&store, "今天12点")
            .expect("follow-up should resolve the pending reminder");

        match decision {
            FirstPartyRoutingDecision::Execute(plan) => match plan.steps.as_slice() {
                [runtime_kernel::ExecutionPlanStep {
                    intent: FirstPartyExecutionIntent::CreateReminderAutomation(request),
                    condition: ExecutionPlanCondition::Always,
                }] => {
                    assert_eq!(request.time_of_day, "12:00");
                    assert_eq!(request.name, "提醒：吃药");
                }
                _ => panic!("expected reminder automation intent"),
            },
            _ => panic!("expected reminder execution plan"),
        }
    }

    #[test]
    fn current_time_request_is_answered_from_runtime_facts() {
        let store = default_runtime_store();
        assert!(looks_like_runtime_facts_time_request("现在是几点"));
        let reply = grounded_runtime_fact_reply(
            &store,
            ExecutionSurface::DesktopWorkspaceChat,
            &crate::default_runtime_agent_profile(),
        );

        assert_eq!(reply.run_state.stop_reason, "runtime_fact_reply");
        assert!(reply.quick_reply.contains("Current local time"));
    }

    #[test]
    fn controlled_terminal_steps_ignore_persona_allow_lists_and_still_run_guarded_shell() {
        let restrictive_profile = AgentProfile {
            allowed_tool_ids: Some(vec!["navigate.*".to_string()]),
            ..crate::default_runtime_agent_profile()
        };
        let step = ControlledTerminalStep {
            title: "Read the current working directory".to_string(),
            command: "pwd".to_string(),
            args: Vec::new(),
            condition: execution_runtime::ControlledTerminalStepCondition::Always,
            cwd: None,
        };

        let request = build_terminal_tool_request(&step, None);
        assert_eq!(request.allowed_tool_ids, None);

        let observation = execute_controlled_terminal_step(&step, None);
        assert!(
            matches!(observation.outcome, ToolOutcome::Completed { .. }),
            "controlled terminal lane should be gated by runtime policy, not persona allow-lists"
        );

        // Keep the profile in scope so this test documents the policy boundary:
        // a restrictive persona must not disable the system-run terminal lane.
        assert_eq!(
            restrictive_profile.allowed_tool_ids,
            Some(vec!["navigate.*".to_string()])
        );
    }

    #[test]
    fn controlled_terminal_non_zero_exit_marks_the_run_failed() {
        let meta = ExecutionRequestMeta {
            task_id: "task_terminal_demo".to_string(),
            module_run_id: "run_terminal_demo".to_string(),
            conversation_id: Some("conv_demo".to_string()),
            title: "Terminal request: docker demo".to_string(),
            prompt: "你看下本机docker里面有什么可启动的容器".to_string(),
            created_at: "now".to_string(),
            updated_at: "now".to_string(),
        };
        let request = ControlledTerminalRequest {
            goal: "你看下本机docker里面有什么可启动的容器".to_string(),
            plan_summary: "Inspect local Docker containers.".to_string(),
            kind: ControlledTerminalPlanKind::DockerContainers {
                only_startable: true,
            },
            steps: vec![ControlledTerminalStep {
                title: "List local Docker containers with status".to_string(),
                command: "docker".to_string(),
                args: vec!["ps".to_string(), "-a".to_string()],
                condition: execution_runtime::ControlledTerminalStepCondition::Always,
                cwd: None,
            }],
        };
        let observations = vec![ControlledTerminalObservation {
            step: request.steps[0].clone(),
            outcome: ToolOutcome::Completed {
                tool_id: "shell.run".to_string(),
                payload: serde_json::json!({
                    "command": "docker",
                    "args": ["ps", "-a"],
                    "exit_code": 1,
                    "stdout": "",
                    "stderr": "Cannot connect to the Docker daemon",
                }),
            },
        }];

        let outcome = build_controlled_terminal_execution_outcome(&meta, &request, &observations);
        assert_eq!(outcome.task_run.status, TaskStatus::Failed);
        assert!(outcome.assistant_reply.contains("failed"));
        assert!(outcome
            .module_run
            .result_summary
            .as_deref()
            .unwrap_or_default()
            .contains("terminal inspection failed"));
    }

    #[test]
    fn port_check_request_is_detected_as_controlled_terminal_execution() {
        let store = default_runtime_store();
        let plan = detect_first_party_execution_from_store(&store, "你看看3000端口有没有被占用")
            .expect("port-check prompt should resolve");

        match plan {
            FirstPartyRoutingDecision::Execute(plan) => match plan.steps.as_slice() {
                [runtime_kernel::ExecutionPlanStep {
                    intent: FirstPartyExecutionIntent::RunControlledTerminal(request),
                    condition: ExecutionPlanCondition::Always,
                }] => {
                    assert!(matches!(
                        request.kind,
                        ControlledTerminalPlanKind::HostDiagnostics {
                            include_current_time: false
                        }
                    ));
                    assert_eq!(request.steps[0].command, "lsof");
                }
                _ => panic!("expected controlled terminal intent"),
            },
            _ => panic!("expected controlled terminal execution decision"),
        }
    }

    #[test]
    fn python_service_inspection_is_detected_as_controlled_terminal_execution() {
        let store = default_runtime_store();
        let decision =
            detect_first_party_execution_from_store(&store, "你看看现在有什么正在运行的python服务")
                .expect("python-service request should resolve");

        match decision {
            FirstPartyRoutingDecision::Execute(plan) => match plan.steps.as_slice() {
                [runtime_kernel::ExecutionPlanStep {
                    intent: FirstPartyExecutionIntent::RunControlledTerminal(request),
                    condition: ExecutionPlanCondition::Always,
                }] => {
                    assert!(matches!(
                        request.kind,
                        ControlledTerminalPlanKind::HostDiagnostics {
                            include_current_time: false
                        }
                    ));
                    assert_eq!(request.steps[0].command, "ps");
                }
                _ => panic!("expected controlled terminal intent"),
            },
            _ => panic!("expected execution decision"),
        }
    }

    #[test]
    fn fresh_python_service_request_beats_status_follow_up_routing() {
        let mut store = default_runtime_store();
        store.last_run_state = Some(runtime_run_state(
            Some(store.active_conversation_id.clone()),
            "idle",
            "no_active_run",
            "No prior local run is active.",
            false,
            None,
            None,
        ));

        let decision =
            detect_first_party_execution_from_store(&store, "怎么样？你看了本地python服务吗")
                .expect("fresh actionable request should resolve");

        match decision {
            FirstPartyRoutingDecision::Execute(plan) => match plan.steps.as_slice() {
                [runtime_kernel::ExecutionPlanStep {
                    intent: FirstPartyExecutionIntent::RunControlledTerminal(request),
                    condition: ExecutionPlanCondition::Always,
                }] => {
                    assert!(matches!(
                        request.kind,
                        ControlledTerminalPlanKind::HostDiagnostics { .. }
                    ));
                }
                _ => panic!("expected controlled terminal intent"),
            },
            _ => panic!("expected execution decision"),
        }
    }

    #[test]
    fn fresh_docker_terminal_request_beats_status_follow_up_routing() {
        let mut store = default_runtime_store();
        store.last_run_state = Some(runtime_run_state(
            Some(store.active_conversation_id.clone()),
            "running",
            "run_in_progress",
            "A prior run is still active.",
            true,
            Some("task_demo".to_string()),
            Some("run_demo".to_string()),
        ));

        let decision = detect_first_party_execution_from_store(
            &store,
            "怎么样？你看下本机docker里面有什么可启动的容器",
        )
        .expect("fresh docker request should resolve");

        match decision {
            FirstPartyRoutingDecision::Execute(plan) => match plan.steps.as_slice() {
                [runtime_kernel::ExecutionPlanStep {
                    intent: FirstPartyExecutionIntent::RunControlledTerminal(request),
                    condition: ExecutionPlanCondition::Always,
                }] => {
                    assert!(matches!(
                        request.kind,
                        execution_runtime::ControlledTerminalPlanKind::DockerContainers {
                            only_startable: true
                        }
                    ));
                }
                _ => panic!("expected controlled terminal intent"),
            },
            _ => panic!("expected execution decision"),
        }
    }

    #[test]
    fn quick_prompt_reuses_the_active_conversation_when_context_overlaps() {
        let mut store = seed_runtime_store().expect("fixture should parse");
        let original_active_conversation_id = store.active_conversation_id.clone();
        let original_message_count = store
            .active_conversation()
            .map(|conversation| conversation.messages.len())
            .unwrap_or_default();

        apply_quick_prompt(
            &mut store,
            ExecutionSurface::DesktopQuickInput,
            "Review the newest creator upload and tell me if it should be saved.",
            "I kept this in the current creator ops thread and opened a task in the workspace.",
            &quick_input_reply(
                "xenodia",
                "I kept this in the current creator ops thread and opened a task in the workspace.",
                &crate::default_runtime_agent_profile(),
            ),
        )
        .expect("quick prompt should apply");

        assert_eq!(
            store.active_conversation_id,
            original_active_conversation_id
        );
        assert_eq!(
            store
                .active_conversation()
                .map(|conversation| conversation.messages.len())
                .unwrap_or_default(),
            original_message_count + 2
        );
    }

    #[test]
    fn quick_prompt_router_selects_matching_topic_conversation() {
        let mut store = default_runtime_store();
        let english_conversation_id = store.active_conversation_id.clone();
        {
            let conversation = store
                .active_conversation_mut()
                .expect("default active conversation should exist");
            conversation.title = "English translation".to_string();
            conversation
                .messages
                .push(RuntimeConversationMessageRecord {
                    message_id: "msg_translation_topic".to_string(),
                    role: "user".to_string(),
                    content: "banana 的英文单词是什么？".to_string(),
                    timestamp: "2026-04-24T00:00:00Z".to_string(),
                });
        }

        let axonchain_conversation_id =
            store.create_conversation(Some("Axonchain local development".to_string()));
        store
            .active_conversation_mut()
            .expect("axonchain conversation should be active")
            .messages
            .push(RuntimeConversationMessageRecord {
                message_id: "msg_axonchain_topic".to_string(),
                role: "user".to_string(),
                content: "cd /Volumes/video_bucket/documents/allpower-axonchain/tools/axon-viewer"
                    .to_string(),
                timestamp: "2026-04-24T00:00:00Z".to_string(),
            });
        store
            .set_active_conversation(&english_conversation_id)
            .expect("translation conversation should activate");

        let routed =
            route_quick_prompt_to_best_conversation(&mut store, "axonchain的官方网址是什么？")
                .expect("axonchain should match the axonchain topic");

        assert_eq!(routed, axonchain_conversation_id);
        assert_eq!(store.active_conversation_id, axonchain_conversation_id);
    }

    #[test]
    fn quick_prompt_router_matches_chinese_topic_keywords() {
        let mut store = default_runtime_store();
        let default_conversation_id = store.active_conversation_id.clone();
        let poetry_conversation_id = store.create_conversation(Some("诗歌创作讨论".to_string()));
        store
            .active_conversation_mut()
            .expect("poetry conversation should be active")
            .messages
            .push(RuntimeConversationMessageRecord {
                message_id: "msg_poetry_topic".to_string(),
                role: "user".to_string(),
                content: "帮我调整这首诗歌的意象和节奏".to_string(),
                timestamp: "2026-04-24T00:00:00Z".to_string(),
            });
        store
            .set_active_conversation(&default_conversation_id)
            .expect("default conversation should activate");

        let routed = route_quick_prompt_to_best_conversation(&mut store, "这首诗歌还能怎么改？")
            .expect("poetry should match the existing Chinese topic");

        assert_eq!(routed, poetry_conversation_id);
        assert_eq!(store.active_conversation_id, poetry_conversation_id);
    }

    #[test]
    fn quick_prompt_router_ignores_generic_website_words() {
        let mut store = default_runtime_store();
        store
            .active_conversation_mut()
            .expect("default active conversation should exist")
            .messages
            .push(RuntimeConversationMessageRecord {
                message_id: "msg_generic_website".to_string(),
                role: "assistant".to_string(),
                content: "The official website URL was checked.".to_string(),
                timestamp: "2026-04-24T00:00:00Z".to_string(),
            });

        assert_eq!(
            best_quick_prompt_conversation_match(&store, "官方网址是什么？"),
            None
        );
    }

    #[test]
    fn transient_quick_prompt_detector_catches_simple_math_and_translation() {
        assert!(is_transient_quick_prompt("23 * (7 + 5) 等于多少？"));
        assert!(is_transient_quick_prompt("苹果的英文单词是什么？"));
        assert!(!is_transient_quick_prompt("这首诗歌还能怎么改？"));
        assert!(!is_transient_quick_prompt("检查本机 3000 端口是否被占用"));
    }

    #[test]
    fn quick_prompt_creates_a_new_conversation_when_request_is_unrelated() {
        let mut store = seed_runtime_store().expect("fixture should parse");
        let original_conversation_count = store.conversations.len();
        let original_active_conversation_id = store.active_conversation_id.clone();

        apply_quick_prompt(
            &mut store,
            ExecutionSurface::DesktopQuickInput,
            "Design a quiet macOS automation palette for local terminal themes.",
            "I opened a fresh thread for this unrelated workspace request and created a task.",
            &quick_input_reply(
                "xenodia",
                "I opened a fresh thread for this unrelated workspace request and created a task.",
                &crate::default_runtime_agent_profile(),
            ),
        )
        .expect("quick prompt should apply");

        assert_eq!(store.conversations.len(), original_conversation_count + 1);
        assert_ne!(
            store.active_conversation_id,
            original_active_conversation_id
        );
        assert!(store
            .active_conversation()
            .expect("active conversation should exist")
            .title
            .contains("quiet macOS automation palette"));
    }

    #[test]
    fn quick_prompt_rejects_empty_input() {
        let mut store = seed_runtime_store().expect("fixture should parse");
        let error = apply_quick_prompt(
            &mut store,
            ExecutionSurface::DesktopQuickInput,
            "   ",
            "ok",
            "ok",
        )
        .expect_err("empty prompt should fail");

        assert!(error.contains("empty"));
    }

    #[test]
    fn resolve_approval_marks_the_task_completed_when_approved() {
        let mut store = seed_runtime_store().expect("fixture should parse");
        let original_transcript_count = store.transcript_events.len();

        resolve_approval(&mut store, "apr_01", "approve", None).expect("approval should resolve");

        assert_eq!(store.approval_requests[0].status, "approved");
        assert_eq!(store.tasks[0].status, "completed");
        assert_eq!(
            store.module_runs[0].module_run.status,
            module_gateway::ModuleRunStatus::Completed
        );
        assert!(store.quick_reply.contains("Approved"));
        assert_eq!(store.transcript_events.len(), original_transcript_count + 5);
        assert!(matches!(
            &store.transcript_events[original_transcript_count].payload,
            TranscriptEventPayload::SessionStateChanged { summary }
                if summary.contains("approval granted")
        ));
        assert!(matches!(
            &store.transcript_events[original_transcript_count + 1].payload,
            TranscriptEventPayload::ToolInvocation { invocation }
                if invocation.invocation_id == "toolinv_run_publish_01"
                    && invocation.approval_request_id.as_deref() == Some("apr_01")
        ));
        assert!(matches!(
            &store.transcript_events[original_transcript_count + 2].payload,
            TranscriptEventPayload::ToolResult { invocation_id, status, .. }
                if invocation_id == "toolinv_run_publish_01"
                    && matches!(status, ToolInvocationStatus::Succeeded)
        ));
        assert!(matches!(
            &store.transcript_events[original_transcript_count + 3].payload,
            TranscriptEventPayload::AssistantMessage { content, .. }
                if content.contains("Approval received")
        ));
    }

    #[test]
    fn resolve_approval_switches_back_to_the_task_conversation() {
        let mut store = seed_runtime_store().expect("fixture should parse");
        store
            .set_active_conversation("conv_notes")
            .expect("seed conversation should exist");

        resolve_approval(&mut store, "apr_01", "approve", None).expect("approval should resolve");

        assert_eq!(store.active_conversation_id, "conv_creator_ops");
        assert!(store
            .active_conversation()
            .expect("active conversation should exist")
            .messages
            .iter()
            .any(|message| message.role == "assistant"
                && message.content.contains("Approval received")));
    }

    #[test]
    fn resolve_approval_updates_kernel_run_when_present() {
        let mut store = seed_runtime_store().expect("fixture should parse");
        let session_id = store.ensure_kernel_session_for_conversation(
            "conv_creator_ops",
            ExecutionSurface::DesktopWorkspaceChat,
        );
        let runtime = store
            .kernel_session_runtime_mut(&session_id)
            .expect("kernel runtime should exist");
        runtime.start_run(
            KernelRun {
                run_id: "krun_task_review_publish".to_string(),
                session_id: session_id.clone(),
                origin_message_id: "msg_user_01".to_string(),
                status: KernelRunStatus::Running,
                started_at: "now".to_string(),
                updated_at: "now".to_string(),
                step_count: 0,
                max_steps: ITERATIVE_TURN_MAX_STEPS as u32,
                run_kind: Some("controlled_terminal".to_string()),
                active_step_id: None,
                parent_run_id: None,
                interrupt_id: Some("kinterrupt_task_review_publish".to_string()),
                stop_reason: None,
                final_output_ref: None,
                error_summary: None,
            },
            "kevent_test_run_created",
        );
        runtime.open_interruption(
            runtime_kernel::RunInterruption {
                interrupt_id: "kinterrupt_task_review_publish".to_string(),
                run_id: "krun_task_review_publish".to_string(),
                reason: runtime_kernel::RunInterruptReason::ApprovalRequired,
                status: runtime_kernel::RunInterruptStatus::Open,
                created_at: "now".to_string(),
                approval_request_ref: Some("apr_01".to_string()),
                requested_action_summary: Some("Publish the prepared creator update".to_string()),
                resume_token: Some("resume_task_review_publish".to_string()),
                policy_tags: vec!["terminal".to_string()],
                default_resolution: Some("reject".to_string()),
            },
            "kevent_test_interrupt_opened",
        );

        resolve_approval(&mut store, "apr_01", "approve", None).expect("approval should resolve");

        let runtime = store
            .kernel_sessions
            .iter()
            .find(|session| session.session.session_id == session_id)
            .expect("kernel runtime should still exist");
        assert_eq!(
            runtime
                .runs
                .get("krun_task_review_publish")
                .expect("kernel run should exist")
                .status,
            KernelRunStatus::Completed
        );
        assert_eq!(
            runtime
                .interruptions
                .get("kinterrupt_task_review_publish")
                .expect("kernel interruption should exist")
                .status,
            runtime_kernel::RunInterruptStatus::Resolved
        );
    }

    #[test]
    fn resolve_approval_returns_the_task_to_waiting_input_when_rejected() {
        let mut store = seed_runtime_store().expect("fixture should parse");
        let original_transcript_count = store.transcript_events.len();

        resolve_approval(&mut store, "apr_01", "reject", None).expect("rejection should resolve");

        assert_eq!(store.approval_requests[0].status, "rejected");
        assert_eq!(store.tasks[0].status, "waiting_input");
        assert!(store.quick_reply.contains("Denied"));
        assert!(matches!(
            &store.transcript_events[original_transcript_count + 2].payload,
            TranscriptEventPayload::ToolResult { invocation_id, status, error, .. }
                if invocation_id == "toolinv_run_publish_01"
                    && matches!(status, ToolInvocationStatus::Failed)
                    && error
                        .as_deref()
                        .unwrap_or_default()
                        .contains("Terminal access was denied")
        ));
    }

    #[test]
    fn recover_module_run_can_requeue_a_retryable_run() {
        let mut store = seed_runtime_store().expect("fixture should parse");
        let original_transcript_count = store.transcript_events.len();

        apply_module_recovery(&mut store, "run_publish_01", "retry")
            .expect("retryable run should requeue");

        assert_eq!(
            store.module_runs[0].module_run.status,
            module_gateway::ModuleRunStatus::Queued
        );
        assert_eq!(store.module_runs[0].module_run.attempt_count, 2);
        assert_eq!(store.tasks[0].status, "queued");
        assert_eq!(store.tasks[0].approval_request_id, None);
        assert_eq!(store.approval_requests[0].status, "expired");
        assert!(store.quick_reply.contains("retry"));
        assert_eq!(store.transcript_events.len(), original_transcript_count + 3);
    }

    #[test]
    fn recover_module_run_can_resume_a_review_blocked_run() {
        let mut store = seed_runtime_store().expect("fixture should parse");
        let original_transcript_count = store.transcript_events.len();

        apply_module_recovery(&mut store, "run_publish_01", "resume")
            .expect("review-blocked run should resume into the review flow");

        assert_eq!(store.workspace_focus.mode, "approval");
        assert_eq!(
            store.workspace_focus.task_id.as_deref(),
            Some("task_review_publish")
        );
        assert!(store.quick_reply.contains("review"));
        assert_eq!(store.transcript_events.len(), original_transcript_count + 3);
    }

    #[test]
    fn recover_module_run_switches_back_to_the_task_conversation() {
        let mut store = seed_runtime_store().expect("fixture should parse");
        store
            .set_active_conversation("conv_notes")
            .expect("seed conversation should exist");

        apply_module_recovery(&mut store, "run_publish_01", "resume")
            .expect("resume should re-open the task conversation");

        assert_eq!(store.active_conversation_id, "conv_creator_ops");
    }

    #[test]
    fn workspace_message_updates_the_conversation_without_creating_a_new_task() {
        let mut store = seed_runtime_store().expect("fixture should parse");
        let original_message_count = store
            .active_conversation()
            .map(|conversation| conversation.messages.len())
            .unwrap_or_default();
        let original_task_count = store.tasks.len();

        apply_workspace_message(
            &mut store,
            ExecutionSurface::DesktopWorkspaceChat,
            "Keep this methodology thread in the current chat and tighten the summary.",
            "I kept the methodology thread in the active conversation and tightened the summary.",
            &workspace_quick_reply(
                "xenodia",
                "I kept the methodology thread in the active conversation and tightened the summary.",
                &crate::default_runtime_agent_profile(),
            ),
        )
        .expect("workspace message should apply");

        assert_eq!(
            store
                .active_conversation()
                .map(|conversation| conversation.messages.len())
                .unwrap_or_default(),
            original_message_count + 2
        );
        assert_eq!(store.tasks.len(), original_task_count);
        assert!(store.quick_reply.contains("Live reply via xenodia"));
    }

    #[test]
    fn workspace_message_updates_the_focused_task_when_direction_changes() {
        let mut store = seed_runtime_store().expect("fixture should parse");
        store.active_conversation_id = "conv_notes".to_string();
        store.workspace_focus = RuntimeWorkspaceFocus {
            mode: "task".to_string(),
            task_id: Some("task_waiting_note".to_string()),
        };

        apply_workspace_message(
            &mut store,
            ExecutionSurface::DesktopWorkspaceChat,
            "Turn this note into an actionable checklist and keep it private for now.",
            "I updated the current note task and kept it inside the active conversation.",
            &workspace_quick_reply(
                "xenodia",
                "I updated the current note task and kept it inside the active conversation.",
                &crate::default_runtime_agent_profile(),
            ),
        )
        .expect("workspace message should apply");

        let updated_task = store
            .tasks
            .iter()
            .find(|task| task.task_id == "task_waiting_note")
            .expect("focused task should still exist");

        assert_eq!(updated_task.status, "queued");
        assert_eq!(updated_task.current_stage, "direction_updated");
        assert!(updated_task
            .summary
            .contains("Turn this note into an actionable checklist"));
    }

    #[test]
    fn persisted_snapshot_round_trips_to_disk() {
        let store = seed_runtime_store().expect("fixture should parse");
        let snapshot_path =
            std::env::temp_dir().join(format!("geeagent-snapshot-{}.json", std::process::id()));

        persist_store_to_disk(&store, &snapshot_path).expect("snapshot should persist");
        let loaded = load_persisted_store(&snapshot_path)
            .expect("snapshot should load")
            .expect("snapshot should exist");

        assert_eq!(loaded.quick_reply, store.quick_reply);
        let _ = std::fs::remove_file(snapshot_path);
    }

    #[test]
    fn native_bridge_quick_prompt_routes_through_the_agent_runtime_bridge() {
        with_mock_agent_runtime_bridge("direct", || {
            let temp_dir = tempfile::tempdir().expect("tempdir should create");

            let raw_snapshot = native_bridge_result(native_bridge_submit_quick_prompt_json(
                "Reply with READY.",
                Some(temp_dir.path().to_path_buf()),
            ))
            .expect("native quick prompt should return a snapshot");
            let snapshot: serde_json::Value =
                serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");

            assert_eq!(
                snapshot["chat_runtime"]["status"],
                serde_json::json!("live")
            );
            assert_eq!(
                snapshot["chat_runtime"]["active_provider"],
                serde_json::json!(claude_sdk_runtime_provider_label())
            );
            assert_eq!(
                snapshot["last_request_outcome"]["kind"],
                serde_json::json!("chat_reply")
            );

            let (store, _, _) = load_native_bridge_store(Some(temp_dir.path().to_path_buf()))
                .expect("mock bridge snapshot should load");
            let assistant_reply = store
                .active_conversation()
                .and_then(|conversation| conversation.messages.last())
                .map(|message| message.content.clone())
                .unwrap_or_default();

            assert!(assistant_reply.contains("Mock bridge completed the turn directly."));
            assert!(store
                .quick_reply
                .contains("Mock bridge completed the turn directly."));
            assert!(!store.quick_reply.contains("Agent run completed through"));
            assert!(store.transcript_events.iter().any(|event| matches!(
                &event.payload,
                TranscriptEventPayload::SessionStateChanged { summary }
                    if summary.contains("SDK loop through the Xenodia gateway")
            )));
        });
    }

    #[test]
    fn native_bridge_transient_quick_prompt_does_not_create_a_conversation() {
        with_mock_agent_runtime_bridge("direct", || {
            let temp_dir = tempfile::tempdir().expect("tempdir should create");
            let before_raw =
                native_bridge_get_shell_snapshot_json(Some(temp_dir.path().to_path_buf()))
                    .expect("snapshot should load");
            let before: serde_json::Value =
                serde_json::from_str(&before_raw).expect("snapshot json should parse");
            let before_count = before["conversations"]
                .as_array()
                .expect("conversations should be present")
                .len();

            let raw_snapshot = native_bridge_result(native_bridge_submit_quick_prompt_json(
                "23 * (7 + 5) 等于多少？",
                Some(temp_dir.path().to_path_buf()),
            ))
            .expect("transient quick prompt should return a snapshot");
            let snapshot: serde_json::Value =
                serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");

            assert_eq!(
                snapshot["conversations"]
                    .as_array()
                    .expect("conversations should be present")
                    .len(),
                before_count,
                "transient quick prompts should not create persistent conversations"
            );
            assert_eq!(
                snapshot["last_request_outcome"]["kind"],
                serde_json::json!("chat_reply")
            );
        });
    }

    #[test]
    fn native_bridge_workspace_message_records_tool_trace_from_the_agent_runtime_bridge() {
        with_mock_agent_runtime_bridge("tool", || {
            let temp_dir = tempfile::tempdir().expect("tempdir should create");

            let raw_snapshot = native_bridge_result(native_bridge_submit_workspace_message_json(
                "Use a tool and finish the task.",
                Some(temp_dir.path().to_path_buf()),
            ))
            .expect("native workspace message should return a snapshot");
            let snapshot: serde_json::Value =
                serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");

            assert_eq!(
                snapshot["last_request_outcome"]["kind"],
                serde_json::json!("chat_reply")
            );

            let (store, _, _) = load_native_bridge_store(Some(temp_dir.path().to_path_buf()))
                .expect("mock bridge snapshot should load");
            assert!(store.quick_reply.contains("1 tool step"));
            assert!(store.transcript_events.iter().any(|event| matches!(
                &event.payload,
                TranscriptEventPayload::ToolInvocation { invocation }
                    if invocation.tool_name == "Bash"
            )));
            assert!(store.transcript_events.iter().any(|event| matches!(
                &event.payload,
                TranscriptEventPayload::ToolResult { summary, status, .. }
                    if matches!(status, ToolInvocationStatus::Succeeded)
                        && summary
                            .as_deref()
                            .unwrap_or_default()
                            .contains("Printed the current working directory")
            )));
        });
    }

    #[test]
    fn native_bridge_task_action_resumes_paused_sdk_bridge_approval() {
        with_mock_agent_runtime_bridge("approval", || {
            let temp_dir = tempfile::tempdir().expect("tempdir should create");

            let raw_snapshot = native_bridge_result(native_bridge_submit_workspace_message_json(
                "Run an approval-gated Bash check.",
                Some(temp_dir.path().to_path_buf()),
            ))
            .expect("approval-gated workspace message should return a snapshot");
            let snapshot: serde_json::Value =
                serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");
            let task_id = snapshot["tasks"][0]["task_id"]
                .as_str()
                .expect("approval task id should exist")
                .to_string();

            assert_eq!(
                snapshot["tasks"][0]["status"],
                serde_json::json!("waiting_review")
            );
            assert_eq!(
                snapshot["approval_requests"][0]["status"],
                serde_json::json!("open")
            );
            let approval_chatter = snapshot["active_conversation"]["messages"]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(|message| message["content"].as_str())
                .any(|content| content.contains("This step needs your approval"));
            assert!(
                !approval_chatter,
                "approval cards should not be duplicated by explanatory assistant chat"
            );

            let raw_snapshot = native_bridge_perform_task_action_json(
                &task_id,
                "allow_once",
                Some(temp_dir.path().to_path_buf()),
            )
            .expect("allow once should resume the paused SDK bridge run");
            let snapshot: serde_json::Value =
                serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");

            assert_eq!(
                snapshot["tasks"][0]["status"],
                serde_json::json!("completed")
            );
            assert_eq!(
                snapshot["approval_requests"][0]["status"],
                serde_json::json!("approved")
            );

            let (store, _, _) = load_native_bridge_store(Some(temp_dir.path().to_path_buf()))
                .expect("mock bridge snapshot should load");
            let assistant_reply = store
                .active_conversation()
                .and_then(|conversation| conversation.messages.last())
                .map(|message| message.content.clone())
                .unwrap_or_default();
            assert!(
                assistant_reply.contains("Mock bridge resumed after approval"),
                "approval should continue the already-paused SDK bridge session"
            );
        });
    }

    #[test]
    fn native_bridge_task_action_keeps_waiting_when_sdk_requests_follow_up_approval() {
        with_mock_agent_runtime_bridge("approval-chain", || {
            let temp_dir = tempfile::tempdir().expect("tempdir should create");

            let raw_snapshot = native_bridge_result(native_bridge_submit_workspace_message_json(
                "Run an approval-gated multi-step Bash check.",
                Some(temp_dir.path().to_path_buf()),
            ))
            .expect("approval-gated workspace message should return a snapshot");
            let snapshot: serde_json::Value =
                serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");
            let task_id = snapshot["tasks"][0]["task_id"]
                .as_str()
                .expect("approval task id should exist")
                .to_string();

            assert_eq!(
                snapshot["tasks"][0]["status"],
                serde_json::json!("waiting_review")
            );
            assert!(snapshot["approval_requests"][0]["parameters"][0]["value"]
                .as_str()
                .unwrap_or_default()
                .contains("echo first"));

            let raw_snapshot = native_bridge_perform_task_action_json(
                &task_id,
                "allow_once",
                Some(temp_dir.path().to_path_buf()),
            )
            .expect(
                "first allow should keep the same SDK bridge run waiting for follow-up approval",
            );
            let snapshot: serde_json::Value =
                serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");

            assert_eq!(
                snapshot["tasks"][0]["status"],
                serde_json::json!("waiting_review")
            );
            assert_eq!(
                snapshot["approval_requests"][0]["status"],
                serde_json::json!("open")
            );
            assert!(snapshot["approval_requests"][0]["parameters"][0]["value"]
                .as_str()
                .unwrap_or_default()
                .contains("echo second"));
            assert_eq!(
                snapshot["approval_requests"][1]["status"],
                serde_json::json!("approved")
            );
            assert!(snapshot["approval_requests"][1]["parameters"][0]["value"]
                .as_str()
                .unwrap_or_default()
                .contains("echo first"));
            assert_ne!(
                snapshot["approval_requests"][0]["approval_request_id"],
                snapshot["approval_requests"][1]["approval_request_id"],
                "follow-up approvals should append a new approval row instead of refreshing the prior one"
            );
            assert_eq!(
                snapshot["last_request_outcome"]["kind"],
                serde_json::json!("task_handoff")
            );

            let (store, _, _) = load_native_bridge_store(Some(temp_dir.path().to_path_buf()))
                .expect("mock bridge snapshot should load");
            let approval_invocation_count = store
                .transcript_events
                .iter()
                .filter(|event| {
                    matches!(
                        &event.payload,
                        TranscriptEventPayload::ToolInvocation { invocation }
                            if invocation.approval_request_id.is_some()
                    )
                })
                .count();
            assert_eq!(
                approval_invocation_count, 2,
                "each approval boundary should be represented by its own tool invocation"
            );

            let raw_snapshot = native_bridge_perform_task_action_json(
                &task_id,
                "allow_once",
                Some(temp_dir.path().to_path_buf()),
            )
            .expect("second allow should complete the same SDK bridge run");
            let snapshot: serde_json::Value =
                serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");

            assert_eq!(
                snapshot["tasks"][0]["status"],
                serde_json::json!("completed")
            );
            let assistant_reply = snapshot["active_conversation"]["messages"]
                .as_array()
                .and_then(|messages| messages.last())
                .and_then(|message| message["content"].as_str())
                .unwrap_or_default();
            assert!(
                assistant_reply.contains("Mock bridge resumed after approval"),
                "the chained approval should continue instead of surfacing a fatal error"
            );
        });
    }

    #[test]
    fn native_bridge_task_action_marks_degraded_when_sdk_pending_approval_was_lost() {
        with_mock_agent_runtime_bridge("approval", || {
            let temp_dir = tempfile::tempdir().expect("tempdir should create");

            let raw_snapshot = native_bridge_result(native_bridge_submit_workspace_message_json(
                "Run an approval-gated Bash check.",
                Some(temp_dir.path().to_path_buf()),
            ))
            .expect("approval-gated workspace message should return a snapshot");
            let snapshot: serde_json::Value =
                serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");
            let task_id = snapshot["tasks"][0]["task_id"]
                .as_str()
                .expect("approval task id should exist")
                .to_string();

            if let Some(manager) = AGENT_RUNTIME_BRIDGE_MANAGER.get() {
                manager
                    .lock()
                    .expect("bridge manager should lock")
                    .sessions
                    .clear();
            }

            let raw_snapshot = native_bridge_perform_task_action_json(
                &task_id,
                "allow_once",
                Some(temp_dir.path().to_path_buf()),
            )
            .expect("allow once should commit a degraded state when pending approval is stale");
            let snapshot: serde_json::Value =
                serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");

            assert_eq!(snapshot["tasks"][0]["status"], serde_json::json!("failed"));
            assert_eq!(
                snapshot["approval_requests"][0]["status"],
                serde_json::json!("approved")
            );
            assert_eq!(
                snapshot["chat_runtime"]["status"],
                serde_json::json!("degraded")
            );
            assert_eq!(
                snapshot["last_run_state"]["stop_reason"],
                serde_json::json!("terminal_approval_resume_failed")
            );
            let assistant_reply = snapshot["active_conversation"]["messages"]
                .as_array()
                .and_then(|messages| messages.last())
                .and_then(|message| message["content"].as_str())
                .unwrap_or_default();
            assert!(
                assistant_reply.contains("no longer alive"),
                "lost approval sessions should be surfaced as degraded instead of replayed"
            );
        });
    }

    #[test]
    fn sdk_bridge_always_allow_persists_terminal_permission_rule() {
        with_mock_agent_runtime_bridge("approval", || {
            let temp_dir = tempfile::tempdir().expect("tempdir should create");

            let raw_snapshot = native_bridge_result(native_bridge_submit_workspace_message_json(
                "Run an approval-gated Bash check.",
                Some(temp_dir.path().to_path_buf()),
            ))
            .expect("approval-gated workspace message should return a snapshot");
            let snapshot: serde_json::Value =
                serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");
            let task_id = snapshot["tasks"][0]["task_id"]
                .as_str()
                .expect("approval task id should exist")
                .to_string();

            native_bridge_perform_task_action_json(
                &task_id,
                "always_allow",
                Some(temp_dir.path().to_path_buf()),
            )
            .expect("always allow should resume and persist terminal permission");

            let permissions = load_terminal_access_permissions(Some(temp_dir.path()));
            assert!(permissions.rules.iter().any(|rule| {
                rule.decision == TerminalAccessDecision::Allow
                    && matches!(
                        &rule.scope,
                        TerminalAccessScope::SdkBridgeBash { command, cwd }
                            if command == "echo approved"
                                && cwd.as_deref() == Some("/tmp/geeagent-mock")
                    )
            }));
        });
    }

    #[test]
    fn terminal_permission_rules_are_visible_and_removable_from_bridge_snapshot() {
        let temp_dir = tempfile::tempdir().expect("tempdir should create");
        let scope = TerminalAccessScope::SdkBridgeBash {
            command: "python3 -m http.server 3000".to_string(),
            cwd: Some("/tmp/geeagent-test".to_string()),
        };

        upsert_terminal_access_rule(
            Some(temp_dir.path()),
            scope,
            TerminalAccessDecision::Allow,
            "python server test",
        )
        .expect("permission rule should persist");

        let raw_snapshot =
            native_bridge_get_shell_snapshot_json(Some(temp_dir.path().to_path_buf()))
                .expect("snapshot should serialize saved terminal permission rules");
        let snapshot: serde_json::Value =
            serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");
        let rules = snapshot["terminal_access_rules"]
            .as_array()
            .expect("terminal access rules should be an array");
        assert_eq!(rules.len(), 1);
        assert_eq!(rules[0]["decision"], serde_json::json!("allow"));
        assert_eq!(
            rules[0]["command"],
            serde_json::json!("python3 -m http.server 3000")
        );

        let rule_id = rules[0]["rule_id"]
            .as_str()
            .expect("terminal permission rule id should exist")
            .to_string();
        let raw_snapshot = native_bridge_delete_terminal_access_rule_json(
            &rule_id,
            Some(temp_dir.path().to_path_buf()),
        )
        .expect("delete should remove saved permission rule");
        let snapshot: serde_json::Value =
            serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");
        assert_eq!(snapshot["terminal_access_rules"], serde_json::json!([]));
        assert!(load_terminal_access_permissions(Some(temp_dir.path()))
            .rules
            .is_empty());
    }

    #[test]
    fn highest_authorization_preference_auto_approves_sdk_bridge_requests() {
        with_mock_agent_runtime_bridge("approval", || {
            let temp_dir = tempfile::tempdir().expect("tempdir should create");
            let raw_snapshot = native_bridge_set_highest_authorization_json(
                true,
                Some(temp_dir.path().to_path_buf()),
            )
            .expect("highest authorization preference should persist");
            let snapshot: serde_json::Value =
                serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");
            assert_eq!(
                snapshot["security_preferences"]["highest_authorization_enabled"],
                serde_json::json!(true)
            );

            let raw_snapshot = native_bridge_result(native_bridge_submit_workspace_message_json(
                "Run an approval-gated Bash check.",
                Some(temp_dir.path().to_path_buf()),
            ))
            .expect("highest authorization should auto-approve the bridge request");
            let snapshot: serde_json::Value =
                serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");

            assert!(
                snapshot["approval_requests"]
                    .as_array()
                    .map(|approvals| approvals.is_empty())
                    .unwrap_or(true),
                "highest authorization should not surface a user approval card"
            );
            let assistant_reply = snapshot["active_conversation"]["messages"]
                .as_array()
                .and_then(|messages| messages.last())
                .and_then(|message| message["content"].as_str())
                .unwrap_or_default();
            assert!(
                assistant_reply.contains("Mock bridge resumed after approval"),
                "highest authorization should let the bridge continue inside the same run"
            );
        });
    }

    #[test]
    fn sdk_bridge_deny_persists_terminal_permission_rule_without_execution() {
        with_mock_agent_runtime_bridge("approval", || {
            let temp_dir = tempfile::tempdir().expect("tempdir should create");

            let raw_snapshot = native_bridge_result(native_bridge_submit_workspace_message_json(
                "Run an approval-gated Bash check.",
                Some(temp_dir.path().to_path_buf()),
            ))
            .expect("approval-gated workspace message should return a snapshot");
            let snapshot: serde_json::Value =
                serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");
            let task_id = snapshot["tasks"][0]["task_id"]
                .as_str()
                .expect("approval task id should exist")
                .to_string();

            let raw_snapshot = native_bridge_perform_task_action_json(
                &task_id,
                "deny",
                Some(temp_dir.path().to_path_buf()),
            )
            .expect("deny should resolve the paused SDK bridge run without execution");
            let snapshot: serde_json::Value =
                serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");

            assert_eq!(
                snapshot["tasks"][0]["status"],
                serde_json::json!("waiting_input")
            );
            assert_eq!(
                snapshot["approval_requests"][0]["status"],
                serde_json::json!("rejected")
            );

            let permissions = load_terminal_access_permissions(Some(temp_dir.path()));
            assert!(permissions.rules.iter().any(|rule| {
                rule.decision == TerminalAccessDecision::Deny
                    && matches!(
                        &rule.scope,
                        TerminalAccessScope::SdkBridgeBash { command, cwd }
                            if command == "echo approved"
                                && cwd.as_deref() == Some("/tmp/geeagent-mock")
                    )
            }));
        });
    }

    #[test]
    fn sdk_bridge_auto_approves_read_only_web_tools() {
        assert!(is_auto_approved_read_only_sdk_tool("WebSearch"));
        assert!(is_auto_approved_read_only_sdk_tool("WebFetch"));
        assert!(!is_auto_approved_read_only_sdk_tool("Write"));
        assert!(!is_auto_approved_read_only_sdk_tool("Bash"));
    }

    #[test]
    fn sdk_bridge_allows_websearch_without_terminal_approval() {
        with_mock_agent_runtime_bridge("websearch", || {
            let temp_dir = tempfile::tempdir().expect("tempdir should create");

            let raw_snapshot = native_bridge_result(native_bridge_submit_workspace_message_json(
                "Search the web for the AxonChain official website.",
                Some(temp_dir.path().to_path_buf()),
            ))
            .expect("web search should complete through the SDK bridge");
            let snapshot: serde_json::Value =
                serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");

            assert_eq!(
                snapshot["last_request_outcome"]["kind"],
                serde_json::json!("chat_reply")
            );
            assert!(
                snapshot["approval_requests"]
                    .as_array()
                    .expect("approval requests should be an array")
                    .is_empty(),
                "read-only web tools should not create terminal approvals"
            );

            let (store, _, _) = load_native_bridge_store(Some(temp_dir.path().to_path_buf()))
                .expect("mock bridge snapshot should load");
            assert!(store.transcript_events.iter().any(|event| matches!(
                &event.payload,
                TranscriptEventPayload::ToolInvocation { invocation }
                    if invocation.tool_name == "WebSearch"
            )));
            assert!(store.transcript_events.iter().any(|event| matches!(
                &event.payload,
                TranscriptEventPayload::ToolResult { summary, status, .. }
                    if matches!(status, ToolInvocationStatus::Succeeded)
                        && summary
                            .as_deref()
                            .unwrap_or_default()
                            .contains("candidate official AxonChain website")
            )));
        });
    }

    #[test]
    fn sdk_bridge_denies_unknown_non_bash_tools_by_default() {
        with_mock_agent_runtime_bridge("nonbash", || {
            let temp_dir = tempfile::tempdir().expect("tempdir should create");

            let raw_snapshot = native_bridge_result(native_bridge_submit_workspace_message_json(
                "Try an unsupported non-Bash file mutation.",
                Some(temp_dir.path().to_path_buf()),
            ))
            .expect("non-Bash tool request should return a snapshot");
            let snapshot: serde_json::Value =
                serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");

            assert_eq!(
                snapshot["last_request_outcome"]["kind"],
                serde_json::json!("chat_reply")
            );
            assert!(
                snapshot["approval_requests"]
                    .as_array()
                    .expect("approval requests should be an array")
                    .is_empty(),
                "unknown non-Bash tools should not create terminal approvals"
            );

            let (store, _, _) = load_native_bridge_store(Some(temp_dir.path().to_path_buf()))
                .expect("mock bridge snapshot should load");
            let assistant_reply = store
                .active_conversation()
                .and_then(|conversation| conversation.messages.last())
                .map(|message| message.content.clone())
                .unwrap_or_default();
            assert!(
                assistant_reply.contains("accepted the host denial for Write"),
                "GeeAgent should deny non-Bash host approvals instead of silently allowing them"
            );
        });
    }

    #[test]
    fn native_bridge_quick_prompt_surfaces_agent_runtime_bridge_failures_without_faking_completion()
    {
        with_mock_agent_runtime_bridge("error", || {
            let temp_dir = tempfile::tempdir().expect("tempdir should create");

            let raw_snapshot = native_bridge_result(native_bridge_submit_quick_prompt_json(
                "fail this turn",
                Some(temp_dir.path().to_path_buf()),
            ))
            .expect("native quick prompt should still return a snapshot");
            let snapshot: serde_json::Value =
                serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");

            assert_eq!(
                snapshot["chat_runtime"]["status"],
                serde_json::json!("degraded")
            );
            assert_eq!(
                snapshot["last_request_outcome"]["kind"],
                serde_json::json!("chat_reply")
            );

            let (store, _, _) = load_native_bridge_store(Some(temp_dir.path().to_path_buf()))
                .expect("mock bridge snapshot should load");
            let assistant_reply = store
                .active_conversation()
                .and_then(|conversation| conversation.messages.last())
                .map(|message| message.content.clone())
                .unwrap_or_default();

            assert!(store.quick_reply.contains("could not complete this run"));
            assert_eq!(
                store
                    .last_run_state
                    .as_ref()
                    .map(|state| state.status.as_str()),
                Some("failed")
            );
            assert!(assistant_reply.contains("I did not present it as completed"));
        });
    }

    #[test]
    #[ignore = "legacy pre-SDK bridge behavior; replace with phase-2 bridge tests"]
    fn native_bridge_quick_prompt_can_queue_a_task_handoff() {
        let temp_dir = tempfile::tempdir().expect("tempdir should create");

        let raw_snapshot = native_bridge_result(native_bridge_submit_quick_prompt_json(
            "Design a quiet macOS automation palette for local terminal themes.",
            Some(temp_dir.path().to_path_buf()),
        ))
        .expect("native quick prompt should return a snapshot");
        let snapshot: serde_json::Value =
            serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");

        assert_eq!(
            snapshot["last_request_outcome"]["kind"],
            serde_json::json!("task_handoff")
        );
        assert_eq!(snapshot["tasks"][0]["status"], serde_json::json!("queued"));
    }

    #[test]
    #[ignore = "legacy pre-SDK bridge behavior; replace with phase-2 bridge tests"]
    fn native_bridge_quick_prompt_can_execute_first_party_reminders() {
        let temp_dir = tempfile::tempdir().expect("tempdir should create");

        let raw_snapshot = native_bridge_result(native_bridge_submit_quick_prompt_json(
            "明天8点通知我吃药💊",
            Some(temp_dir.path().to_path_buf()),
        ))
        .expect("native quick prompt should return a snapshot");
        let snapshot: serde_json::Value =
            serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");

        assert_eq!(
            snapshot["last_request_outcome"]["kind"],
            serde_json::json!("first_party_action")
        );
        assert_eq!(
            snapshot["automations"][0]["time_of_day"],
            serde_json::json!("08:00")
        );
    }

    #[test]
    #[ignore = "legacy pre-SDK bridge behavior; replace with phase-2 bridge tests"]
    fn native_bridge_quick_prompt_can_answer_current_time_from_runtime_facts() {
        let temp_dir = tempfile::tempdir().expect("tempdir should create");

        let raw_snapshot = native_bridge_result(native_bridge_submit_quick_prompt_json(
            "现在是几点",
            Some(temp_dir.path().to_path_buf()),
        ))
        .expect("native quick prompt should return a snapshot");
        let snapshot: serde_json::Value =
            serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");

        assert_eq!(
            snapshot["last_request_outcome"]["kind"],
            serde_json::json!("chat_reply")
        );
        assert!(snapshot["tasks"]
            .as_array()
            .expect("tasks should be an array")
            .is_empty());
        assert!(snapshot["module_runs"]
            .as_array()
            .expect("module runs should be an array")
            .is_empty());
        assert!(snapshot["active_conversation"]["messages"]
            .as_array()
            .expect("messages should be an array")
            .iter()
            .any(|message| message["role"] == serde_json::json!("assistant")
                && message["content"]
                    .as_str()
                    .unwrap_or_default()
                    .contains("本地时间")));
    }

    #[test]
    #[ignore = "legacy pre-SDK bridge behavior; replace with phase-2 bridge tests"]
    fn native_bridge_workspace_message_executes_wrapped_reminder_task_request() {
        let temp_dir = tempfile::tempdir().expect("tempdir should create");

        let raw_snapshot = native_bridge_result(native_bridge_submit_workspace_message_json(
            "创建一个任务，在12点设定一个提醒我吃药的任务",
            Some(temp_dir.path().to_path_buf()),
        ))
        .expect("native workspace message should return a snapshot");
        let snapshot: serde_json::Value =
            serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");

        assert_eq!(
            snapshot["last_request_outcome"]["kind"],
            serde_json::json!("first_party_action")
        );
        assert_eq!(
            snapshot["automations"][0]["time_of_day"],
            serde_json::json!("12:00")
        );
        assert_eq!(
            snapshot["tasks"][0]["status"],
            serde_json::json!("completed")
        );
    }

    #[test]
    #[ignore = "legacy pre-SDK bridge behavior; replace with phase-2 bridge tests"]
    fn native_bridge_workspace_message_routes_port_checks_through_terminal() {
        let temp_dir = tempfile::tempdir().expect("tempdir should create");
        let listener = TcpListener::bind("127.0.0.1:0").expect("listener should bind");
        let port = listener
            .local_addr()
            .expect("listener should expose local addr")
            .port();

        let raw_snapshot = native_bridge_result(native_bridge_submit_workspace_message_json(
            &format!("你看看{port}端口有没有被占用"),
            Some(temp_dir.path().to_path_buf()),
        ))
        .expect("native workspace message should return a snapshot");
        let snapshot: serde_json::Value =
            serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");

        assert_eq!(
            snapshot["last_request_outcome"]["kind"],
            serde_json::json!("first_party_action")
        );
        assert_eq!(
            snapshot["tasks"][0]["status"],
            serde_json::json!("completed")
        );
        assert_eq!(
            snapshot["module_runs"][0]["module_run"]["module_id"],
            serde_json::json!("geeagent.local.terminal")
        );
        assert_eq!(
            snapshot["module_runs"][0]["module_run"]["capability_id"],
            serde_json::json!("controlled_terminal")
        );
        assert!(snapshot["active_conversation"]["messages"][2]["content"]
            .as_str()
            .expect("assistant reply should be a string")
            .contains(&port.to_string()));
    }

    #[test]
    #[ignore = "legacy pre-SDK bridge behavior; replace with phase-2 bridge tests"]
    fn native_bridge_workspace_message_can_complete_a_terminal_host_diagnostics_request() {
        let temp_dir = tempfile::tempdir().expect("tempdir should create");

        let raw_snapshot = native_bridge_result(native_bridge_submit_workspace_message_json(
            "获取现在的本地时间，告诉我此时此刻本地有哪些python程序在运行",
            Some(temp_dir.path().to_path_buf()),
        ))
        .expect("compound local ops request should return a snapshot");
        let snapshot: serde_json::Value =
            serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");

        assert_eq!(
            snapshot["last_request_outcome"]["kind"],
            serde_json::json!("first_party_action")
        );
        assert_eq!(
            snapshot["tasks"][0]["status"],
            serde_json::json!("completed")
        );
        assert_eq!(
            snapshot["module_runs"][0]["module_run"]["module_id"],
            serde_json::json!("geeagent.local.terminal")
        );
        let assistant_reply = snapshot["active_conversation"]["messages"][2]["content"]
            .as_str()
            .expect("assistant reply should be a string");
        assert!(assistant_reply.contains("本地时间"));
        assert!(assistant_reply.contains("python"));
    }

    #[test]
    #[ignore = "legacy pre-SDK bridge behavior; replace with phase-2 bridge tests"]
    fn native_bridge_workspace_message_can_run_the_controlled_terminal_lane_for_docker() {
        let temp_dir = tempfile::tempdir().expect("tempdir should create");

        let raw_snapshot = native_bridge_result(native_bridge_submit_workspace_message_json(
            "你看下本机docker里面有什么可启动的容器",
            Some(temp_dir.path().to_path_buf()),
        ))
        .expect("native workspace message should return a snapshot");
        let snapshot: serde_json::Value =
            serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");

        assert_eq!(
            snapshot["last_request_outcome"]["kind"],
            serde_json::json!("first_party_action")
        );
        assert_eq!(
            snapshot["module_runs"][0]["module_run"]["module_id"],
            serde_json::json!("geeagent.local.terminal")
        );
        assert_eq!(
            snapshot["module_runs"][0]["module_run"]["capability_id"],
            serde_json::json!("controlled_terminal")
        );
        assert_eq!(snapshot["tasks"][0]["status"], serde_json::json!("failed"));
        assert_eq!(
            snapshot["kernel_sessions"][0]["session"]["current_run_id"],
            serde_json::Value::Null
        );
        assert_eq!(
            snapshot["kernel_sessions"][0]["runs"]["krun_task_quick_01"]["status"],
            serde_json::json!("failed")
        );
        assert_eq!(
            snapshot["kernel_sessions"][0]["steps"]["kstep_task_quick_01_01"]["phase"],
            serde_json::json!("dispatch")
        );
        assert_eq!(
            snapshot["kernel_sessions"][0]["event_log"]["events"][0]["payload"]["kind"],
            serde_json::json!("run_created")
        );
        assert!(snapshot["active_conversation"]["messages"][2]["content"]
            .as_str()
            .expect("assistant reply should be a string")
            .contains("失败"));
    }

    #[test]
    #[ignore = "legacy pre-SDK bridge behavior; replace with phase-2 bridge tests"]
    fn native_bridge_workspace_message_can_confirm_and_execute_a_script_plan() {
        let temp_dir = tempfile::tempdir().expect("tempdir should create");
        let app_dir = temp_dir.path().join("demo-app");
        fs::create_dir_all(&app_dir).expect("demo app directory should exist");
        fs::write(
            app_dir.join("run.sh"),
            "#!/bin/sh\necho booted\ntouch ran.marker\n",
        )
        .expect("run script should be written");

        let initial_prompt = format!("cd {} 需要运行的文件是 run.sh", app_dir.display());
        let initial_snapshot = native_bridge_result(native_bridge_submit_workspace_message_json(
            &initial_prompt,
            Some(temp_dir.path().to_path_buf()),
        ))
        .expect("initial script request should return a snapshot");
        let initial_snapshot: serde_json::Value =
            serde_json::from_str(&initial_snapshot).expect("initial snapshot json should parse");

        assert_eq!(
            initial_snapshot["last_request_outcome"]["kind"],
            serde_json::json!("first_party_action")
        );
        assert_eq!(
            initial_snapshot["tasks"][0]["status"],
            serde_json::json!("waiting_review")
        );
        assert_eq!(
            initial_snapshot["approval_requests"][0]["status"],
            serde_json::json!("open")
        );
        assert!(
            initial_snapshot["active_conversation"]["messages"][2]["content"]
                .as_str()
                .expect("approval prompt should be a string")
                .contains("需要你的确认")
        );

        let raw_snapshot = native_bridge_result(native_bridge_submit_workspace_message_json(
            "执行",
            Some(temp_dir.path().to_path_buf()),
        ))
        .expect("confirmation should continue the same script run");
        let snapshot: serde_json::Value =
            serde_json::from_str(&raw_snapshot).expect("follow-up snapshot json should parse");

        assert_eq!(
            snapshot["last_request_outcome"]["kind"],
            serde_json::json!("first_party_action")
        );
        assert_eq!(
            snapshot["tasks"][0]["status"],
            serde_json::json!("completed")
        );
        assert_eq!(
            snapshot["module_runs"][0]["module_run"]["status"],
            serde_json::json!("completed")
        );
        assert_eq!(
            snapshot["approval_requests"][0]["status"],
            serde_json::json!("approved")
        );
        assert_eq!(
            snapshot["kernel_sessions"][0]["runs"]["krun_task_quick_01"]["status"],
            serde_json::json!("completed")
        );
        assert!(snapshot["active_conversation"]["messages"][4]["content"]
            .as_str()
            .expect("assistant reply should be a string")
            .contains("booted"));
        assert!(
            app_dir.join("ran.marker").exists(),
            "the confirmed script should actually run"
        );
    }

    #[test]
    #[ignore = "legacy pre-SDK bridge behavior; replace with phase-2 bridge tests"]
    fn native_bridge_workspace_message_returns_clarify_needed_for_partial_reminder() {
        let temp_dir = tempfile::tempdir().expect("tempdir should create");

        let raw_snapshot = native_bridge_result(native_bridge_submit_workspace_message_json(
            "创建一个任务，提醒我吃药",
            Some(temp_dir.path().to_path_buf()),
        ))
        .expect("native workspace message should return a snapshot");
        let snapshot: serde_json::Value =
            serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");

        assert_eq!(
            snapshot["last_request_outcome"]["kind"],
            serde_json::json!("clarify_needed")
        );
        assert_eq!(
            snapshot["automations"].as_array().map(|items| items.len()),
            Some(0)
        );
        assert!(snapshot["active_conversation"]["messages"][2]["content"]
            .as_str()
            .expect("assistant clarification should be a string")
            .contains("缺少时间"));
    }

    #[test]
    #[ignore = "legacy pre-SDK bridge behavior; replace with phase-2 bridge tests"]
    fn native_bridge_follow_up_completes_a_pending_reminder_clarification() {
        let temp_dir = tempfile::tempdir().expect("tempdir should create");

        let initial_snapshot = native_bridge_result(native_bridge_submit_workspace_message_json(
            "创建一个任务，提醒我吃药",
            Some(temp_dir.path().to_path_buf()),
        ))
        .expect("initial reminder request should return a snapshot");
        let initial_snapshot: serde_json::Value =
            serde_json::from_str(&initial_snapshot).expect("initial snapshot json should parse");
        assert_eq!(
            initial_snapshot["last_request_outcome"]["kind"],
            serde_json::json!("clarify_needed")
        );

        let raw_snapshot = native_bridge_result(native_bridge_submit_workspace_message_json(
            "今天12点",
            Some(temp_dir.path().to_path_buf()),
        ))
        .expect("follow-up reminder request should return a snapshot");
        let snapshot: serde_json::Value =
            serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");

        assert_eq!(
            snapshot["last_request_outcome"]["kind"],
            serde_json::json!("first_party_action")
        );
        assert_eq!(
            snapshot["automations"][0]["time_of_day"],
            serde_json::json!("12:00")
        );
        assert_eq!(
            snapshot["tasks"][0]["status"],
            serde_json::json!("completed")
        );
    }

    #[test]
    fn native_bridge_task_action_can_approve_a_review_blocked_task() {
        let temp_dir = tempfile::tempdir().expect("tempdir should create");
        let snapshot_path = temp_dir.path().join("runtime-store.json");
        let store = seed_runtime_store().expect("fixture should parse");
        persist_store_to_disk(&store, &snapshot_path).expect("seed store should persist");

        let raw_snapshot = native_bridge_perform_task_action_json(
            "task_review_publish",
            "approve",
            Some(temp_dir.path().to_path_buf()),
        )
        .expect("native task action should return a snapshot");
        let snapshot: serde_json::Value =
            serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");

        assert_eq!(
            snapshot["tasks"][0]["status"],
            serde_json::json!("completed")
        );
        assert_eq!(
            snapshot["last_request_outcome"],
            serde_json::Value::Null,
            "task action should mutate state without fabricating a request outcome"
        );
    }

    #[test]
    #[ignore = "legacy controlled-terminal path; phase-2 SDK approval resume is covered by native_bridge_task_action_resumes_paused_sdk_bridge_approval"]
    fn native_bridge_task_action_can_approve_and_execute_a_terminal_plan() {
        let temp_dir = tempfile::tempdir().expect("tempdir should create");
        let app_dir = temp_dir.path().join("demo-app");
        fs::create_dir_all(&app_dir).expect("demo app directory should exist");
        fs::write(
            app_dir.join("run.sh"),
            "#!/bin/sh\necho booted-from-approval\ntouch approval.marker\n",
        )
        .expect("run script should be written");

        let initial_prompt = format!("cd {} 需要运行的文件是 run.sh", app_dir.display());
        let initial_snapshot = native_bridge_result(native_bridge_submit_workspace_message_json(
            &initial_prompt,
            Some(temp_dir.path().to_path_buf()),
        ))
        .expect("initial script request should return a snapshot");
        let initial_snapshot: serde_json::Value =
            serde_json::from_str(&initial_snapshot).expect("initial snapshot json should parse");
        let task_id = initial_snapshot["tasks"][0]["task_id"]
            .as_str()
            .expect("task id should exist")
            .to_string();

        let raw_snapshot = native_bridge_perform_task_action_json(
            &task_id,
            "approve",
            Some(temp_dir.path().to_path_buf()),
        )
        .expect("terminal approval should execute the stored plan");
        let snapshot: serde_json::Value =
            serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");

        assert_eq!(
            snapshot["tasks"][0]["status"],
            serde_json::json!("completed")
        );
        assert_eq!(
            snapshot["module_runs"][0]["module_run"]["status"],
            serde_json::json!("completed")
        );
        assert_eq!(
            snapshot["approval_requests"][0]["status"],
            serde_json::json!("approved")
        );
        assert_eq!(
            snapshot["kernel_sessions"][0]["runs"]["krun_task_quick_01"]["status"],
            serde_json::json!("completed")
        );
        assert!(
            app_dir.join("approval.marker").exists(),
            "approving from the task panel should actually execute the stored shell plan"
        );
    }

    #[test]
    fn native_bridge_task_action_can_retry_a_recoverable_task() {
        let temp_dir = tempfile::tempdir().expect("tempdir should create");
        let snapshot_path = temp_dir.path().join("runtime-store.json");
        let store = seed_runtime_store().expect("fixture should parse");
        persist_store_to_disk(&store, &snapshot_path).expect("seed store should persist");

        let raw_snapshot = native_bridge_perform_task_action_json(
            "task_review_publish",
            "retry",
            Some(temp_dir.path().to_path_buf()),
        )
        .expect("native task action should return a snapshot");
        let snapshot: serde_json::Value =
            serde_json::from_str(&raw_snapshot).expect("snapshot json should parse");

        assert_eq!(snapshot["tasks"][0]["status"], serde_json::json!("queued"));
        assert_eq!(
            snapshot["approval_requests"][0]["status"],
            serde_json::json!("expired")
        );
    }

    #[test]
    fn runtime_store_can_create_and_activate_a_new_conversation() {
        let mut store = seed_runtime_store().expect("fixture should parse");

        let conversation_id = store.create_conversation(Some("Research Notes".to_string()));
        let derived_snapshot = store.snapshot();

        assert_eq!(
            derived_snapshot.active_conversation.conversation_id,
            conversation_id
        );
        assert_eq!(derived_snapshot.active_conversation.title, "Research Notes");
        assert!(derived_snapshot.conversations.iter().any(|conversation| {
            conversation.conversation_id == conversation_id && conversation.is_active
        }));
    }

    #[test]
    fn switching_conversations_resets_workspace_focus() {
        let mut store = seed_runtime_store().expect("fixture should parse");
        store.workspace_focus = RuntimeWorkspaceFocus {
            mode: "task".to_string(),
            task_id: Some("task_digest_youtube".to_string()),
        };

        store
            .set_active_conversation("conv_notes")
            .expect("known conversation should activate");

        assert_eq!(store.workspace_focus.mode, "default");
        assert_eq!(store.workspace_focus.task_id, None);
    }

    #[test]
    fn deleting_the_active_conversation_promotes_another_thread() {
        let mut store = seed_runtime_store().expect("fixture should parse");

        store
            .delete_conversation("conv_creator_ops")
            .expect("active conversation should delete");

        assert_eq!(store.active_conversation_id, "conv_notes");
        assert_eq!(store.workspace_focus.mode, "default");
        assert!(store.quick_reply.contains("Deleted"));
    }

    #[test]
    fn deleting_the_last_conversation_creates_a_fresh_replacement() {
        let mut store = seed_runtime_store().expect("fixture should parse");
        store.conversations = vec![store
            .active_conversation()
            .cloned()
            .expect("seed should have an active conversation")];
        store.active_conversation_id = "conv_creator_ops".to_string();

        store
            .delete_conversation("conv_creator_ops")
            .expect("last conversation should delete with replacement");

        assert_eq!(store.conversations.len(), 1);
        assert_ne!(store.active_conversation_id, "conv_creator_ops");
        assert_eq!(
            store
                .active_conversation()
                .expect("replacement conversation should exist")
                .messages
                .len(),
            1
        );
    }

    #[test]
    fn claude_sdk_turn_prompt_preserves_full_history_before_context_threshold() {
        let store = default_runtime_store();
        let active_agent_profile = store
            .active_agent_profile()
            .expect("default store should have an active profile")
            .clone();
        let workspace_messages = (0..16)
            .map(|index| WorkspaceChatMessage {
                role: if index % 2 == 0 {
                    "user".to_string()
                } else {
                    "assistant".to_string()
                },
                content: format!("short-history-marker-{index}"),
            })
            .collect::<Vec<_>>();
        let route = TurnRoute {
            mode: TurnMode::WorkspaceMessage,
            source: RuntimeRequestSource::WorkspaceChat,
            surface: ExecutionSurface::DesktopWorkspaceChat,
        };
        let prepared = PreparedTurnContext {
            active_agent_profile,
            workspace_messages,
            should_reuse_active_conversation: true,
        };

        let prompt = compose_claude_sdk_turn_prompt(&route, &prepared, "latest request marker");

        assert!(
            prompt.contains("short-history-marker-0"),
            "history below the 95% context threshold should not be truncated to the latest turns"
        );
        assert!(prompt.contains("short-history-marker-15"));
        assert!(prompt.contains("latest request marker"));
    }

    #[test]
    fn context_projection_summarizes_older_turns_at_the_95_percent_threshold() {
        let messages = oversized_workspace_context_messages();

        let (projected, compacted_messages_count, projected_tokens) =
            context_projected_workspace_messages(&messages);

        assert_eq!(compacted_messages_count, 8);
        assert_eq!(projected.len(), 13);
        assert!(projected
            .first()
            .expect("summary message should be first")
            .content
            .contains("[AUTO CONTEXT SUMMARY]"));
        assert!(projected
            .iter()
            .any(|message| message.content.contains("recent-context-marker-19")));
        assert!(
            projected_tokens < CONTEXT_AUTO_SUMMARY_TRIGGER_TOKENS,
            "compacted prompt should fall back below the summary trigger"
        );
    }

    #[test]
    fn runtime_snapshot_reports_a_256k_context_budget_and_summary_state() {
        let mut store = default_runtime_store();
        let active_conversation = store
            .active_conversation_mut()
            .expect("default store should have an active conversation");
        active_conversation.messages.clear();
        for (index, message) in oversized_workspace_context_messages()
            .into_iter()
            .enumerate()
        {
            active_conversation
                .messages
                .push(RuntimeConversationMessageRecord {
                    message_id: format!("msg_context_budget_{index}"),
                    role: message.role,
                    content: message.content,
                    timestamp: "2026-04-24T00:00:00Z".to_string(),
                });
        }

        let budget = store.snapshot().context_budget;

        assert_eq!(budget.max_tokens, CONTEXT_WINDOW_TOKENS);
        assert_eq!(budget.summary_state, "summarized");
        assert_eq!(budget.compacted_messages_count, 8);
        assert!(budget.used_tokens > 0);
        assert!(budget.usage_ratio < 0.95);
    }

    #[test]
    fn grep_no_match_is_not_treated_as_terminal_failure() {
        let observation = ControlledTerminalObservation {
            step: ControlledTerminalStep {
                title: "Extract package name lines".to_string(),
                command: "grep".to_string(),
                args: vec!["^name".to_string(), "Cargo.toml".to_string()],
                condition: execution_runtime::ControlledTerminalStepCondition::Always,
                cwd: None,
            },
            outcome: ToolOutcome::Completed {
                tool_id: "shell.run".to_string(),
                payload: serde_json::json!({
                    "command": "grep",
                    "args": ["^name", "Cargo.toml"],
                    "cwd": null,
                    "exit_code": 1,
                    "stdout": "",
                    "stderr": "",
                }),
            },
        };

        assert!(terminal_observation_error(&observation).is_none());
    }
}
