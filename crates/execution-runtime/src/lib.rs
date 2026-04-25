pub mod tool;

pub use tool::{
    SHELL_ALLOW_LIST, ToolBlastRadius, ToolOutcome, ToolRequest, ToolSpec, V1_TOOL_CATALOG,
    allow_list_matches, catalog_as_json, persona_allows, run_tool, spec_for,
};

use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    fs,
    path::{Path, PathBuf},
    process::Command,
};
use time::{Duration, PrimitiveDateTime, macros::format_description};

use automation_engine::{AutomationStatus, LockPolicy, ScheduleCadence, TriggerKind};
use module_gateway::{
    ArtifactEnvelope, ModuleRun, ModuleRunStage, ModuleRunStatus, Recoverability,
};
use task_engine::{ImportanceLevel, TaskRun, TaskStage, TaskStatus, TaskType};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LocalMarkdownRequest {
    pub file_name: String,
    pub content: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReminderAutomationRequest {
    pub name: String,
    pub goal_prompt: String,
    pub cadence: ScheduleCadence,
    pub time_of_day: String,
    pub schedule_hint: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReminderAutomationClarification {
    pub extracted_time_of_day: Option<String>,
    pub extracted_reminder_body: Option<String>,
    pub missing_time_of_day: bool,
    pub missing_reminder_body: bool,
    pub assistant_reply: String,
    pub quick_reply: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ReminderAutomationParseResult {
    Complete(ReminderAutomationRequest),
    Clarify(ReminderAutomationClarification),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LocalOpsRequest {
    pub action: LocalOpsAction,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LocalOpsPlanStep {
    pub request: LocalOpsRequest,
    pub condition: LocalOpsConditionHint,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LocalOpsConditionHint {
    Always,
    IfNoPythonProcessesFound,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ControlledTerminalRequest {
    pub goal: String,
    pub plan_summary: String,
    pub kind: ControlledTerminalPlanKind,
    pub steps: Vec<ControlledTerminalStep>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ControlledTerminalPlanKind {
    DockerContainers { only_startable: bool },
    GitStatus,
    DirectoryListing,
    HostDiagnostics { include_current_time: bool },
    GenericShell { subject: String },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ControlledTerminalStep {
    pub title: String,
    pub command: String,
    pub args: Vec<String>,
    #[serde(default)]
    pub condition: ControlledTerminalStepCondition,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cwd: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum ControlledTerminalStepCondition {
    #[default]
    Always,
    IfPreviousPythonInspectionEmpty,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LocalOpsAction {
    ReadCurrentTime,
    InspectListeningPort(ListeningPortRequest),
    InspectPythonProcesses(PythonProcessInspectionRequest),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ListeningPortRequest {
    pub port: u16,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PythonProcessInspectionRequest {
    pub include_listening_ports: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ExecutionObservation {
    CurrentTime {
        local_time: String,
    },
    ListeningPortInspection {
        port: u16,
        listener_count: usize,
        listeners: Vec<String>,
    },
    PythonProcessInspection {
        process_count: usize,
        listening_count: usize,
        processes: Vec<String>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HostRuntimeFacts {
    pub local_time: String,
    pub time_zone: String,
    pub cwd: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FirstPartyExecutionIntent {
    CreateDesktopMarkdown(LocalMarkdownRequest),
    CreateReminderAutomation(ReminderAutomationRequest),
    RunLocalOps(LocalOpsRequest),
    RunControlledTerminal(ControlledTerminalRequest),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExecutionAutomationDraft {
    pub name: String,
    pub status: AutomationStatus,
    pub trigger_kind: TriggerKind,
    pub goal_prompt: String,
    pub lock_policy: LockPolicy,
    pub cadence: ScheduleCadence,
    pub time_of_day: String,
    pub schedule_hint: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExecutionRequestMeta {
    pub task_id: String,
    pub module_run_id: String,
    pub conversation_id: Option<String>,
    pub title: String,
    pub prompt: String,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExecutionOutcome {
    pub task_run: TaskRun,
    pub module_run: ModuleRun,
    pub recoverability: Option<Recoverability>,
    pub automation_drafts: Vec<ExecutionAutomationDraft>,
    pub observation: Option<ExecutionObservation>,
    pub assistant_reply: String,
    pub quick_reply: String,
}

#[derive(Debug, Clone, Default)]
pub struct ExecutionRuntime {
    desktop_directory_override: Option<PathBuf>,
}

impl ExecutionRuntime {
    pub fn for_local_system() -> Self {
        Self {
            desktop_directory_override: None,
        }
    }

    pub fn with_desktop_directory(path: PathBuf) -> Self {
        Self {
            desktop_directory_override: Some(path),
        }
    }

    pub fn execute_first_party(
        &self,
        intent: &FirstPartyExecutionIntent,
        meta: &ExecutionRequestMeta,
    ) -> ExecutionOutcome {
        match intent {
            FirstPartyExecutionIntent::CreateDesktopMarkdown(request) => {
                self.execute_local_markdown(request, meta)
            }
            FirstPartyExecutionIntent::CreateReminderAutomation(request) => {
                self.execute_reminder_automation(request, meta)
            }
            FirstPartyExecutionIntent::RunLocalOps(request) => {
                self.execute_local_ops(request, meta)
            }
            FirstPartyExecutionIntent::RunControlledTerminal(request) => {
                self.execute_deferred_controlled_terminal(request, meta)
            }
        }
    }

    fn execute_deferred_controlled_terminal(
        &self,
        request: &ControlledTerminalRequest,
        meta: &ExecutionRequestMeta,
    ) -> ExecutionOutcome {
        let task_run = TaskRun {
            task_id: meta.task_id.clone(),
            conversation_id: meta.conversation_id.clone(),
            task_type: TaskType::AbilityRun,
            title: meta.title.clone(),
            status: TaskStatus::Failed,
            current_stage: TaskStage::Finalized,
            summary:
                "Controlled terminal requests must be dispatched through the shared turn runner."
                    .to_string(),
            progress_percent: Some(0),
            importance_level: ImportanceLevel::Important,
            approval_request_id: None,
        };

        let module_run = ModuleRun {
            module_run_id: meta.module_run_id.clone(),
            task_id: meta.task_id.clone(),
            module_id: "geeagent.local.terminal".to_string(),
            capability_id: "controlled_terminal".to_string(),
            status: ModuleRunStatus::Failed,
            stage: ModuleRunStage::Finalized,
            attempt_count: 1,
            result_summary: Some(format!(
                "Deferred terminal goal '{}' was sent to ExecutionRuntime instead of the shared turn runner.",
                request.goal
            )),
            artifacts: Vec::new(),
            created_at: meta.created_at.clone(),
            updated_at: meta.updated_at.clone(),
        };

        ExecutionOutcome {
            task_run,
            module_run,
            recoverability: None,
            automation_drafts: Vec::new(),
            observation: None,
            assistant_reply: "Internal runtime error: controlled terminal requests must stay inside the shared runner."
                .to_string(),
            quick_reply: "Controlled terminal dispatch was misrouted.".to_string(),
        }
    }

    fn execute_local_markdown(
        &self,
        request: &LocalMarkdownRequest,
        meta: &ExecutionRequestMeta,
    ) -> ExecutionOutcome {
        let result = self.desktop_directory().and_then(|desktop_directory| {
            execute_local_markdown_request_in_directory(request, &desktop_directory)
        });

        let artifacts = result
            .as_ref()
            .map(|path| local_markdown_artifacts(&request.file_name, path, &meta.prompt))
            .unwrap_or_default();
        let artifact_count = artifacts.len() as u32;

        let (task_status, task_stage, task_summary, task_progress_percent) = match &result {
            Ok(path) => (
                TaskStatus::Completed,
                TaskStage::Finalized,
                format!(
                    "Created {} on the Desktop at {}.",
                    request.file_name,
                    path.display()
                ),
                Some(100),
            ),
            Err(error) => (
                TaskStatus::Failed,
                TaskStage::Finalized,
                format!(
                    "Failed to create {} on the Desktop. {}",
                    request.file_name, error
                ),
                Some(68),
            ),
        };

        let (module_status, module_stage, module_summary, recoverability) = match &result {
            Ok(_) => (
                ModuleRunStatus::Completed,
                ModuleRunStage::Finalized,
                Some(format!(
                    "Created {} on the Desktop and finalized the workspace result.",
                    request.file_name
                )),
                None,
            ),
            Err(error) => (
                ModuleRunStatus::Failed,
                ModuleRunStage::Finalized,
                Some(format!(
                    "Desktop markdown creation failed for {}. {}",
                    request.file_name, error
                )),
                Some(Recoverability {
                    retry_safe: true,
                    resume_supported: false,
                    hint: Some(
                        "Fix the filename or Desktop path issue, then retry this local write."
                            .to_string(),
                    ),
                }),
            ),
        };

        let task_run = TaskRun {
            task_id: meta.task_id.clone(),
            conversation_id: meta.conversation_id.clone(),
            task_type: TaskType::AbilityRun,
            title: meta.title.clone(),
            status: task_status,
            current_stage: task_stage,
            summary: task_summary,
            progress_percent: task_progress_percent,
            importance_level: ImportanceLevel::Important,
            approval_request_id: None,
        };

        let module_run = ModuleRun {
            module_run_id: meta.module_run_id.clone(),
            task_id: meta.task_id.clone(),
            module_id: "geeagent.local.filesystem".to_string(),
            capability_id: "create_desktop_markdown".to_string(),
            status: module_status,
            stage: module_stage,
            attempt_count: 1,
            result_summary: module_summary,
            artifacts,
            created_at: meta.created_at.clone(),
            updated_at: meta.updated_at.clone(),
        };

        let (assistant_reply, quick_reply) = match &result {
            Ok(path) => local_markdown_success_reply(path, request),
            Err(error) => local_markdown_failure_reply(request, error),
        };

        debug_assert_eq!(artifact_count, module_run.artifacts.len() as u32);

        ExecutionOutcome {
            task_run,
            module_run,
            recoverability,
            automation_drafts: Vec::new(),
            observation: None,
            assistant_reply,
            quick_reply,
        }
    }

    fn execute_reminder_automation(
        &self,
        request: &ReminderAutomationRequest,
        meta: &ExecutionRequestMeta,
    ) -> ExecutionOutcome {
        let schedule_label = reminder_schedule_label(request);
        let artifacts = reminder_automation_artifacts(request, &meta.prompt);
        let task_run = TaskRun {
            task_id: meta.task_id.clone(),
            conversation_id: meta.conversation_id.clone(),
            task_type: TaskType::ScheduledRun,
            title: meta.title.clone(),
            status: TaskStatus::Completed,
            current_stage: TaskStage::Finalized,
            summary: format!("Created reminder automation {}.", schedule_label),
            progress_percent: Some(100),
            importance_level: ImportanceLevel::Important,
            approval_request_id: None,
        };
        let module_run = ModuleRun {
            module_run_id: meta.module_run_id.clone(),
            task_id: meta.task_id.clone(),
            module_id: "geeagent.local.automation".to_string(),
            capability_id: "create_reminder_automation".to_string(),
            status: ModuleRunStatus::Completed,
            stage: ModuleRunStage::Finalized,
            attempt_count: 1,
            result_summary: Some(format!(
                "Created reminder automation {} and finalized the workspace result.",
                schedule_label
            )),
            artifacts,
            created_at: meta.created_at.clone(),
            updated_at: meta.updated_at.clone(),
        };
        let automation_draft = ExecutionAutomationDraft {
            name: request.name.clone(),
            status: AutomationStatus::Active,
            trigger_kind: TriggerKind::Schedule,
            goal_prompt: request.goal_prompt.clone(),
            lock_policy: LockPolicy::SkipIfRunning,
            cadence: request.cadence.clone(),
            time_of_day: request.time_of_day.clone(),
            schedule_hint: request.schedule_hint.clone(),
        };
        let (assistant_reply, quick_reply) = reminder_automation_replies(request);

        ExecutionOutcome {
            task_run,
            module_run,
            recoverability: None,
            automation_drafts: vec![automation_draft],
            observation: None,
            assistant_reply,
            quick_reply,
        }
    }

    fn execute_local_ops(
        &self,
        request: &LocalOpsRequest,
        meta: &ExecutionRequestMeta,
    ) -> ExecutionOutcome {
        let result = match &request.action {
            LocalOpsAction::ReadCurrentTime => execute_read_current_time(),
            LocalOpsAction::InspectListeningPort(port_request) => {
                execute_inspect_listening_port(port_request.port)
            }
            LocalOpsAction::InspectPythonProcesses(process_request) => {
                execute_inspect_python_processes(process_request)
            }
        };

        let task_run = TaskRun {
            task_id: meta.task_id.clone(),
            conversation_id: meta.conversation_id.clone(),
            task_type: TaskType::AbilityRun,
            title: meta.title.clone(),
            status: result.task_status,
            current_stage: TaskStage::Finalized,
            summary: result.task_summary,
            progress_percent: Some(
                if matches!(result.module_status, ModuleRunStatus::Completed) {
                    100
                } else {
                    68
                },
            ),
            importance_level: ImportanceLevel::Important,
            approval_request_id: None,
        };

        let module_run = ModuleRun {
            module_run_id: meta.module_run_id.clone(),
            task_id: meta.task_id.clone(),
            module_id: "geeagent.local.ops".to_string(),
            capability_id: local_ops_capability_id(&request.action).to_string(),
            status: result.module_status,
            stage: ModuleRunStage::Finalized,
            attempt_count: 1,
            result_summary: Some(result.result_summary),
            artifacts: result.artifacts,
            created_at: meta.created_at.clone(),
            updated_at: meta.updated_at.clone(),
        };

        ExecutionOutcome {
            task_run,
            module_run,
            recoverability: result.recoverability,
            automation_drafts: Vec::new(),
            observation: result.observation,
            assistant_reply: result.assistant_reply,
            quick_reply: result.quick_reply,
        }
    }

    fn desktop_directory(&self) -> Result<PathBuf, String> {
        if let Some(path) = &self.desktop_directory_override {
            return Ok(path.clone());
        }
        default_desktop_directory()
    }
}

pub fn default_desktop_directory() -> Result<PathBuf, String> {
    let home = std::env::var_os("HOME")
        .ok_or_else(|| "HOME is not available in this runtime.".to_string())?;
    Ok(PathBuf::from(home).join("Desktop"))
}

pub fn take_filename_token(input: &str) -> Option<String> {
    let mut token = String::new();

    for ch in input.trim().chars() {
        if ch.is_whitespace() || "，。,.;；:：!?！？()（）[]【】<>《》".contains(ch) {
            break;
        }

        token.push(ch);
    }

    let trimmed = token
        .trim()
        .trim_matches(|ch| matches!(ch, '"' | '\'' | '`' | '“' | '”' | '‘' | '’'))
        .trim()
        .to_string();

    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed)
    }
}

pub fn sanitize_markdown_filename(raw_name: &str) -> Option<String> {
    let mut normalized = raw_name
        .trim()
        .trim_matches(|ch| matches!(ch, '"' | '\'' | '`' | '“' | '”' | '‘' | '’'))
        .trim()
        .to_string();

    if normalized.is_empty() {
        return None;
    }

    normalized = normalized
        .chars()
        .filter(|ch| !matches!(ch, '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|'))
        .collect::<String>()
        .trim()
        .to_string();

    if normalized.is_empty() {
        return None;
    }

    if !normalized.to_ascii_lowercase().ends_with(".md") {
        normalized.push_str(".md");
    }

    Some(normalized)
}

pub fn parse_local_markdown_request(text: &str) -> Option<LocalMarkdownRequest> {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return None;
    }

    let lowered = trimmed.to_ascii_lowercase();
    let asks_for_create = ["创建", "新建", "生成", "create", "make"]
        .iter()
        .any(|keyword| trimmed.contains(keyword) || lowered.contains(keyword));
    let references_desktop = trimmed.contains("桌面") || lowered.contains("desktop");
    let references_markdown = trimmed.contains("md")
        || lowered.contains(".md")
        || trimmed.contains("markdown")
        || lowered.contains("markdown")
        || trimmed.contains("文档");

    if !(asks_for_create && references_desktop && references_markdown) {
        return None;
    }

    let markers = ["名称", "名为", "文件名", "叫做", "叫", "named", "name"];
    let mut raw_name = None;

    for marker in markers {
        if let Some(index) = trimmed.find(marker) {
            let remainder = trimmed[index + marker.len()..].trim_start_matches(|ch: char| {
                ch.is_whitespace() || matches!(ch, ':' | '：' | '"' | '\'' | '`' | '“' | '”')
            });
            raw_name = take_filename_token(remainder);
            if raw_name.is_some() {
                break;
            }
        }
    }

    if raw_name.is_none() {
        if let Some(index) = lowered.find(".md") {
            let original = trimmed
                .char_indices()
                .take_while(|(offset, _)| *offset < index)
                .map(|(_, ch)| ch)
                .collect::<String>();
            let stem = original
                .chars()
                .rev()
                .take_while(|ch| ch.is_alphanumeric() || *ch == '_' || *ch == '-' || !ch.is_ascii())
                .collect::<String>()
                .chars()
                .rev()
                .collect::<String>();
            if !stem.trim().is_empty() {
                raw_name = Some(format!("{}.md", stem.trim()));
            }
        }
    }

    let file_name = sanitize_markdown_filename(raw_name.as_deref().unwrap_or("untitled"))?;
    let content = if ["空白", "空内容", "blank", "empty"]
        .iter()
        .any(|keyword| trimmed.contains(keyword) || lowered.contains(keyword))
    {
        String::new()
    } else {
        String::new()
    };

    Some(LocalMarkdownRequest { file_name, content })
}

pub fn parse_local_ops_requests(text: &str) -> Vec<LocalOpsRequest> {
    let mut requests = Vec::new();

    if let Some(request) = parse_current_time_request(text) {
        requests.push(request);
    }

    requests
}

pub fn parse_local_ops_plan_steps(text: &str) -> Vec<LocalOpsPlanStep> {
    parse_current_time_request(text)
        .map(|request| {
            vec![LocalOpsPlanStep {
                request,
                condition: LocalOpsConditionHint::Always,
            }]
        })
        .unwrap_or_default()
}

pub fn capture_host_runtime_facts() -> HostRuntimeFacts {
    HostRuntimeFacts {
        local_time: read_current_time_label().unwrap_or_else(|_| "unknown".to_string()),
        time_zone: read_shell_fact(&["+%Z"]).unwrap_or_else(|| "local".to_string()),
        cwd: std::env::current_dir()
            .ok()
            .map(|path| path.display().to_string())
            .unwrap_or_else(|| ".".to_string()),
    }
}

pub fn classify_reminder_automation_request_with_facts(
    text: &str,
    facts: &HostRuntimeFacts,
) -> Option<ReminderAutomationParseResult> {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return None;
    }

    if !looks_like_reminder_request(trimmed) {
        return None;
    }

    let (cadence, extracted_schedule_hint) = extract_reminder_schedule(trimmed);
    let relative_time = (cadence == ScheduleCadence::Once)
        .then(|| extract_relative_reminder_time(trimmed, facts))
        .flatten();
    let time_of_day = extract_time_of_day(trimmed).or_else(|| {
        relative_time
            .as_ref()
            .map(|resolved| resolved.time_of_day.clone())
    });
    let schedule_hint = relative_time
        .as_ref()
        .map(|resolved| resolved.schedule_hint.clone())
        .unwrap_or(extracted_schedule_hint);
    let reminder_body = extract_reminder_body(trimmed);

    match (time_of_day, reminder_body) {
        (Some(time_of_day), Some(reminder_body)) => Some(ReminderAutomationParseResult::Complete(
            build_reminder_request(&reminder_body, cadence, &time_of_day, schedule_hint),
        )),
        (time_of_day, reminder_body) => {
            let clarification = reminder_automation_clarification(
                time_of_day,
                reminder_body,
                cadence,
                schedule_hint,
            );
            Some(ReminderAutomationParseResult::Clarify(clarification))
        }
    }
}

pub fn classify_reminder_automation_request(text: &str) -> Option<ReminderAutomationParseResult> {
    let facts = capture_host_runtime_facts();
    classify_reminder_automation_request_with_facts(text, &facts)
}

pub fn parse_reminder_automation_request_with_facts(
    text: &str,
    facts: &HostRuntimeFacts,
) -> Option<ReminderAutomationRequest> {
    match classify_reminder_automation_request_with_facts(text, facts)? {
        ReminderAutomationParseResult::Complete(request) => Some(request),
        ReminderAutomationParseResult::Clarify(_) => None,
    }
}

pub fn parse_reminder_automation_request(text: &str) -> Option<ReminderAutomationRequest> {
    let facts = capture_host_runtime_facts();
    parse_reminder_automation_request_with_facts(text, &facts)
}

pub fn complete_reminder_automation_request_from_follow_up_with_facts(
    prior_text: &str,
    follow_up_text: &str,
    facts: &HostRuntimeFacts,
) -> Option<ReminderAutomationRequest> {
    let prior_classification = classify_reminder_automation_request_with_facts(prior_text, facts)?;
    let ReminderAutomationParseResult::Clarify(prior_clarification) = prior_classification else {
        return None;
    };

    let trimmed_follow_up = follow_up_text.trim();
    if trimmed_follow_up.is_empty() {
        return None;
    }

    let relative_time = extract_relative_reminder_time(trimmed_follow_up, facts);
    let time_of_day = prior_clarification
        .extracted_time_of_day
        .clone()
        .or_else(|| extract_time_of_day(trimmed_follow_up))
        .or_else(|| {
            relative_time
                .as_ref()
                .map(|resolved| resolved.time_of_day.clone())
        });
    let reminder_body = prior_clarification
        .extracted_reminder_body
        .clone()
        .or_else(|| extract_reminder_body(trimmed_follow_up))
        .or_else(|| extract_follow_up_reminder_body(trimmed_follow_up));
    let (cadence, schedule_hint) = extract_reminder_schedule(prior_text);
    let (follow_up_cadence, follow_up_schedule_hint) = extract_reminder_schedule(trimmed_follow_up);
    let follow_up_has_explicit_schedule =
        has_explicit_reminder_schedule(trimmed_follow_up) || relative_time.is_some();
    let cadence = if follow_up_has_explicit_schedule {
        follow_up_cadence
    } else {
        cadence
    };
    let schedule_hint = if let Some(relative_time) = relative_time {
        relative_time.schedule_hint
    } else if follow_up_has_explicit_schedule {
        follow_up_schedule_hint
    } else {
        schedule_hint
    };

    match (time_of_day, reminder_body) {
        (Some(time_of_day), Some(reminder_body)) => Some(build_reminder_request(
            &reminder_body,
            cadence,
            &time_of_day,
            schedule_hint,
        )),
        _ => None,
    }
}

pub fn complete_reminder_automation_request_from_follow_up(
    prior_text: &str,
    follow_up_text: &str,
) -> Option<ReminderAutomationRequest> {
    let facts = capture_host_runtime_facts();
    complete_reminder_automation_request_from_follow_up_with_facts(
        prior_text,
        follow_up_text,
        &facts,
    )
}

pub fn looks_like_affirmation(text: &str) -> bool {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return false;
    }

    let lowered = trimmed.to_ascii_lowercase();
    [
        "可以",
        "好的",
        "执行",
        "好，执行吧",
        "执行吧",
        "继续执行",
        "确认",
        "开始吧",
        "可以，执行吧",
        "ok",
        "okay",
        "yes",
        "go ahead",
        "do it",
        "execute",
        "run it",
        "please do",
    ]
    .iter()
    .any(|keyword| trimmed.contains(keyword) || lowered.contains(keyword))
}

pub fn summarize_prompt(prompt: &str, max_len: usize) -> String {
    let mut summary = prompt.trim().to_string();
    if summary.chars().count() <= max_len {
        return summary;
    }

    summary = summary.chars().take(max_len.saturating_sub(1)).collect();
    format!("{summary}…")
}

fn extract_time_of_day(text: &str) -> Option<String> {
    let chars: Vec<char> = text.chars().collect();

    for start in 0..chars.len() {
        if !chars[start].is_ascii_digit() {
            continue;
        }

        let mut end = start;
        while end < chars.len() && chars[end].is_ascii_digit() && end - start < 2 {
            end += 1;
        }

        let hour_str: String = chars[start..end].iter().collect();
        let hour = hour_str.parse::<u8>().ok()?;
        if hour > 23 || end >= chars.len() {
            continue;
        }

        let separator = chars[end];
        let minute = if separator == ':' || separator == '：' {
            let minute_start = end + 1;
            let mut minute_end = minute_start;
            while minute_end < chars.len()
                && chars[minute_end].is_ascii_digit()
                && minute_end - minute_start < 2
            {
                minute_end += 1;
            }
            if minute_end == minute_start {
                continue;
            }
            chars[minute_start..minute_end]
                .iter()
                .collect::<String>()
                .parse::<u8>()
                .ok()?
        } else if separator == '点' || separator == '时' {
            let mut minute = 0;
            let mut cursor = end + 1;
            if cursor < chars.len() && chars[cursor] == '半' {
                minute = 30;
            } else {
                let minute_start = cursor;
                while cursor < chars.len()
                    && chars[cursor].is_ascii_digit()
                    && cursor - minute_start < 2
                {
                    cursor += 1;
                }
                if cursor > minute_start {
                    minute = chars[minute_start..cursor]
                        .iter()
                        .collect::<String>()
                        .parse::<u8>()
                        .ok()?;
                }
            }
            minute
        } else {
            continue;
        };

        if minute < 60 {
            return Some(format!("{hour:02}:{minute:02}"));
        }
    }

    None
}

fn extract_reminder_body(text: &str) -> Option<String> {
    let markers = ["提醒我", "通知我", "叫我", "提醒", "通知"];

    for marker in markers {
        if let Some(index) = text.find(marker) {
            let remainder = text[index + marker.len()..]
                .trim()
                .trim_matches(|ch: char| matches!(ch, '，' | ',' | '。' | '.' | ':' | '：'))
                .trim();
            if let Some(normalized) = normalize_reminder_body(remainder) {
                return Some(normalized);
            }
        }
    }

    None
}

fn looks_like_reminder_request(text: &str) -> bool {
    let lowered = text.to_ascii_lowercase();
    ["提醒", "通知", "叫我", "remind", "reminder", "notify"]
        .iter()
        .any(|keyword| text.contains(keyword) || lowered.contains(keyword))
}

fn has_explicit_reminder_schedule(text: &str) -> bool {
    text.contains("每天")
        || text.contains("每日")
        || text.contains("工作日")
        || text.contains("周一到周五")
        || text.contains("每周")
        || text.contains("每星期")
        || text.contains("明天")
        || text.contains("今天")
}

fn extract_reminder_schedule(text: &str) -> (ScheduleCadence, Option<String>) {
    let cadence = if text.contains("每天") || text.contains("每日") {
        ScheduleCadence::Daily
    } else if text.contains("工作日") || text.contains("周一到周五") {
        ScheduleCadence::Weekdays
    } else if text.contains("每周") || text.contains("每星期") {
        ScheduleCadence::Weekly
    } else {
        ScheduleCadence::Once
    };

    let schedule_hint = if cadence == ScheduleCadence::Once {
        if text.contains("明天") {
            Some("Tomorrow".to_string())
        } else if text.contains("今天") {
            Some("Today".to_string())
        } else {
            Some("One time".to_string())
        }
    } else {
        None
    };

    (cadence, schedule_hint)
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ResolvedRelativeReminderTime {
    time_of_day: String,
    schedule_hint: Option<String>,
}

fn extract_relative_reminder_time(
    text: &str,
    facts: &HostRuntimeFacts,
) -> Option<ResolvedRelativeReminderTime> {
    let relative_offset = extract_relative_reminder_offset(text)?;
    let now = parse_local_runtime_datetime(&facts.local_time)?;
    let resolved = now.checked_add(relative_offset)?;
    let time_of_day = format!("{:02}:{:02}", resolved.hour(), resolved.minute());

    Some(ResolvedRelativeReminderTime {
        time_of_day,
        schedule_hint: Some(relative_schedule_hint(now, resolved)),
    })
}

fn extract_relative_reminder_offset(text: &str) -> Option<Duration> {
    let lowered = text.to_ascii_lowercase();
    let has_relative_marker = text.contains("后")
        || text.contains("之后")
        || lowered.contains("later")
        || lowered.contains("from now")
        || lowered.contains("in ");
    if !has_relative_marker {
        return None;
    }

    let hour_markers = [
        "个半小时",
        "个小时",
        "小时",
        "hr",
        "hrs",
        "hour",
        "hours",
        "h",
    ];
    let minute_markers = ["分钟", "mins", "min", "minute", "minutes", "m"];

    let mut total_minutes = 0i64;
    let mut matched = false;

    if text.contains("半小时") || lowered.contains("half hour") {
        total_minutes += 30;
        matched = true;
    }

    if let Some(hours) = extract_number_before_any_marker(text, &lowered, &hour_markers) {
        total_minutes += i64::from(hours) * 60;
        matched = true;
    }

    if let Some(minutes) = extract_number_before_any_marker(text, &lowered, &minute_markers) {
        total_minutes += i64::from(minutes);
        matched = true;
    }

    if matched && total_minutes > 0 {
        Some(Duration::minutes(total_minutes))
    } else {
        None
    }
}

fn extract_number_before_any_marker(
    original: &str,
    lowered: &str,
    markers: &[&str],
) -> Option<u16> {
    for marker in markers {
        if let Some(value) = extract_number_before_marker(original, marker) {
            return Some(value);
        }
        if *marker != marker.to_ascii_lowercase() {
            continue;
        }
        if let Some(value) = extract_number_before_marker(lowered, marker) {
            return Some(value);
        }
    }

    None
}

fn extract_number_before_marker(text: &str, marker: &str) -> Option<u16> {
    for (index, _) in text.match_indices(marker) {
        let prefix = text[..index].trim_end();
        let digits = prefix
            .chars()
            .rev()
            .skip_while(|ch| ch.is_whitespace())
            .take_while(|ch| ch.is_ascii_digit())
            .collect::<String>()
            .chars()
            .rev()
            .collect::<String>();
        if digits.is_empty() {
            continue;
        }
        if let Ok(value) = digits.parse::<u16>() {
            return Some(value);
        }
    }

    None
}

fn parse_local_runtime_datetime(label: &str) -> Option<PrimitiveDateTime> {
    let timestamp = label.get(..19)?;
    PrimitiveDateTime::parse(
        timestamp,
        &format_description!("[year]-[month]-[day] [hour]:[minute]:[second]"),
    )
    .ok()
}

fn relative_schedule_hint(base: PrimitiveDateTime, resolved: PrimitiveDateTime) -> String {
    let day_delta = (resolved.date() - base.date()).whole_days();
    match day_delta {
        0 => "Today".to_string(),
        1 => "Tomorrow".to_string(),
        _ => format!(
            "{:04}-{:02}-{:02}",
            resolved.year(),
            u8::from(resolved.month()),
            resolved.day()
        ),
    }
}

fn normalize_reminder_body(text: &str) -> Option<String> {
    let mut normalized = text.trim().to_string();

    for suffix in ["的任务", "任务", "这件事"] {
        if normalized.ends_with(suffix) {
            normalized = normalized
                .trim_end_matches(suffix)
                .trim()
                .trim_end_matches(|ch: char| matches!(ch, '，' | ',' | '。' | '.'))
                .trim()
                .to_string();
            break;
        }
    }

    if normalized.is_empty()
        || matches!(
            normalized.as_str(),
            "我" | "我一下" | "一下" | "一下我" | "一下吧" | "我吧"
        )
    {
        None
    } else {
        Some(normalized)
    }
}

fn extract_follow_up_reminder_body(text: &str) -> Option<String> {
    let trimmed = text
        .trim()
        .trim_matches(|ch: char| matches!(ch, '，' | ',' | '。' | '.' | ':' | '：'))
        .trim();
    if trimmed.is_empty() {
        return None;
    }

    if looks_like_affirmation(trimmed) {
        return None;
    }

    if extract_time_of_day(trimmed).is_some() && trimmed.chars().count() <= 12 {
        return None;
    }

    for prefix in ["内容是", "提醒内容是", "就写", "写", "是"] {
        if let Some(stripped) = trimmed.strip_prefix(prefix) {
            return normalize_reminder_body(stripped);
        }
    }

    normalize_reminder_body(trimmed)
}

fn build_reminder_request(
    reminder_body: &str,
    cadence: ScheduleCadence,
    time_of_day: &str,
    schedule_hint: Option<String>,
) -> ReminderAutomationRequest {
    let name = format!("提醒：{}", summarize_prompt(reminder_body, 18));
    let goal_prompt = match cadence {
        ScheduleCadence::Daily => format!("Remind me every day to {}.", reminder_body),
        ScheduleCadence::Weekdays => format!("Remind me every weekday to {}.", reminder_body),
        ScheduleCadence::Weekly => format!("Remind me every week to {}.", reminder_body),
        ScheduleCadence::Once => format!("Send a one-time reminder to {}.", reminder_body),
    };

    ReminderAutomationRequest {
        name,
        goal_prompt,
        cadence,
        time_of_day: time_of_day.to_string(),
        schedule_hint,
    }
}

pub fn canonicalize_reminder_automation_request(request: &ReminderAutomationRequest) -> String {
    let schedule_phrase = match request.cadence {
        ScheduleCadence::Daily => format!("每天 {}", request.time_of_day),
        ScheduleCadence::Weekdays => format!("工作日 {}", request.time_of_day),
        ScheduleCadence::Weekly => format!("每周 {}", request.time_of_day),
        ScheduleCadence::Once => match request.schedule_hint.as_deref() {
            Some("Today") => format!("今天 {}", request.time_of_day),
            Some("Tomorrow") => format!("明天 {}", request.time_of_day),
            Some(schedule_hint) if !schedule_hint.is_empty() && schedule_hint != "One time" => {
                format!("{schedule_hint} {}", request.time_of_day)
            }
            _ => request.time_of_day.clone(),
        },
    };

    format!("{schedule_phrase} 提醒我{}", reminder_body_summary(request))
}

fn parse_current_time_request(text: &str) -> Option<LocalOpsRequest> {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return None;
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
    let asks_for_current_time = explicit_patterns
        .iter()
        .any(|pattern| trimmed.contains(pattern))
        || lowered.contains("current time")
        || lowered.contains("what time")
        || lowered.contains("current date")
        || lowered.contains("what date");

    if asks_for_current_time {
        return Some(LocalOpsRequest {
            action: LocalOpsAction::ReadCurrentTime,
        });
    }

    let mentions_now = [
        "现在",
        "当前",
        "此刻",
        "这会",
        "now",
        "current",
        "right now",
    ]
    .iter()
    .any(|keyword| trimmed.contains(keyword) || lowered.contains(keyword));
    let mentions_time = [
        "几点",
        "时间",
        "日期",
        "几号",
        "星期几",
        "time",
        "date",
        "clock",
    ]
    .iter()
    .any(|keyword| trimmed.contains(keyword) || lowered.contains(keyword));

    if mentions_now && mentions_time {
        Some(LocalOpsRequest {
            action: LocalOpsAction::ReadCurrentTime,
        })
    } else {
        None
    }
}

fn reminder_automation_clarification(
    extracted_time_of_day: Option<String>,
    extracted_reminder_body: Option<String>,
    _cadence: ScheduleCadence,
    schedule_hint: Option<String>,
) -> ReminderAutomationClarification {
    let missing_time_of_day = extracted_time_of_day.is_none();
    let missing_reminder_body = extracted_reminder_body.is_none();
    let schedule_label = schedule_hint.as_deref().unwrap_or("one-time");

    let assistant_reply = match (missing_time_of_day, missing_reminder_body) {
        (true, true) => {
            "我可以直接帮你创建提醒，但还缺少时间和提醒内容。直接回复例如：今天 12:00 提醒我吃药。"
                .to_string()
        }
        (true, false) => format!(
            "我可以直接帮你创建提醒“{}”，但还缺少时间。直接回复例如：今天 12:00，或者每天 08:30。",
            extracted_reminder_body.as_deref().unwrap_or("这件事")
        ),
        (false, true) => format!(
            "我已经拿到时间 {}（{}），但还缺少提醒内容。直接回复例如：吃药。",
            extracted_time_of_day.as_deref().unwrap_or("--:--"),
            schedule_label
        ),
        (false, false) => "我还需要你补充一点信息后才能创建这个提醒。".to_string(),
    };
    let quick_reply = match (missing_time_of_day, missing_reminder_body) {
        (true, true) => "Reminder needs a time and a reminder body.".to_string(),
        (true, false) => format!(
            "Reminder needs a time for {}.",
            extracted_reminder_body.as_deref().unwrap_or("this request")
        ),
        (false, true) => format!(
            "Reminder at {} still needs the reminder text.",
            extracted_time_of_day.as_deref().unwrap_or("--:--")
        ),
        (false, false) => "Reminder needs a small clarification.".to_string(),
    };

    ReminderAutomationClarification {
        extracted_time_of_day,
        extracted_reminder_body,
        missing_time_of_day,
        missing_reminder_body,
        assistant_reply,
        quick_reply,
    }
}

fn local_ops_capability_id(action: &LocalOpsAction) -> &'static str {
    match action {
        LocalOpsAction::ReadCurrentTime => "current_time",
        LocalOpsAction::InspectListeningPort(_) => "inspect_listening_port",
        LocalOpsAction::InspectPythonProcesses(_) => "inspect_python_processes",
    }
}

struct LocalOpsExecutionResult {
    task_status: TaskStatus,
    module_status: ModuleRunStatus,
    task_summary: String,
    result_summary: String,
    assistant_reply: String,
    quick_reply: String,
    artifacts: Vec<ArtifactEnvelope>,
    recoverability: Option<Recoverability>,
    observation: Option<ExecutionObservation>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct PortListenerRecord {
    command: String,
    pid: String,
    address: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct PythonProcessRecord {
    pid: String,
    command: String,
    arguments: String,
    listening_addresses: Vec<String>,
}

fn execute_read_current_time() -> LocalOpsExecutionResult {
    let facts = capture_host_runtime_facts();
    if facts.local_time != "unknown" {
        LocalOpsExecutionResult {
            task_status: TaskStatus::Completed,
            module_status: ModuleRunStatus::Completed,
            task_summary: format!("Read the current local time: {}.", facts.local_time),
            result_summary: format!(
                "Read the current local time from the host runtime: {}.",
                facts.local_time
            ),
            assistant_reply: format!("已检查。本机当前时间是 `{}`。", facts.local_time),
            quick_reply: format!("Current local time: {}.", facts.local_time),
            artifacts: vec![ArtifactEnvelope {
                artifact_id: "artifact_local_ops_current_time".to_string(),
                artifact_type: "diagnostic_result".to_string(),
                title: "Current local time".to_string(),
                summary: facts.local_time.clone(),
                payload_ref: "memory://local-ops/current-time".to_string(),
                inline_preview: Some(facts.local_time.clone().into()),
                domain_tags: vec!["local-ops".to_string(), "time".to_string()],
            }],
            recoverability: None,
            observation: Some(ExecutionObservation::CurrentTime {
                local_time: facts.local_time,
            }),
        }
    } else {
        LocalOpsExecutionResult {
            task_status: TaskStatus::Failed,
            module_status: ModuleRunStatus::Failed,
            task_summary: "Failed to read the current local time.".to_string(),
            result_summary: "Current-time local ops request failed.".to_string(),
            assistant_reply: "我尝试读取这台 Mac 的当前时间，但没有成功。".to_string(),
            quick_reply: "Unable to read the current local time yet.".to_string(),
            artifacts: Vec::new(),
            recoverability: Some(Recoverability {
                retry_safe: true,
                resume_supported: false,
                hint: Some(
                    "Retry the local time check after the host shell environment is available."
                        .to_string(),
                ),
            }),
            observation: None,
        }
    }
}

fn execute_inspect_listening_port(port: u16) -> LocalOpsExecutionResult {
    match inspect_listening_port(port) {
        Ok(listeners) if listeners.is_empty() => LocalOpsExecutionResult {
            task_status: TaskStatus::Completed,
            module_status: ModuleRunStatus::Completed,
            task_summary: format!("Checked port {port}. No listening process is using it."),
            result_summary: format!("Checked port {port}. No LISTEN socket was found."),
            assistant_reply: format!(
                "已检查。本机端口 `{port}` 当前没有处于 `LISTEN` 状态的进程。"
            ),
            quick_reply: format!("Port {port} is not listening right now."),
            artifacts: vec![ArtifactEnvelope {
                artifact_id: format!("artifact_local_ops_port_{port}"),
                artifact_type: "diagnostic_result".to_string(),
                title: format!("Port {port} inspection"),
                summary: format!("No LISTEN process found on port {port}."),
                payload_ref: format!("memory://local-ops/ports/{port}"),
                inline_preview: Some(format!("port {port}: no listeners").into()),
                domain_tags: vec!["local-ops".to_string(), "network".to_string()],
            }],
            recoverability: None,
            observation: Some(ExecutionObservation::ListeningPortInspection {
                port,
                listener_count: 0,
                listeners: Vec::new(),
            }),
        },
        Ok(listeners) => {
            let listener_summary = listeners
                .iter()
                .map(|listener| {
                    format!(
                        "{} (PID {}) -> {}",
                        listener.command, listener.pid, listener.address
                    )
                })
                .collect::<Vec<_>>()
                .join("；");
            let primary_listener = listeners
                .first()
                .map(|listener| format!("{} (PID {})", listener.command, listener.pid))
                .unwrap_or_else(|| "a local process".to_string());

            LocalOpsExecutionResult {
                task_status: TaskStatus::Completed,
                module_status: ModuleRunStatus::Completed,
                task_summary: format!(
                    "Checked port {port}. Found {} listening process(es).",
                    listeners.len()
                ),
                result_summary: format!(
                    "Checked port {port}. LISTEN process(es): {listener_summary}."
                ),
                assistant_reply: format!(
                    "已检查。本机端口 `{port}` 当前有监听进程：{listener_summary}。"
                ),
                quick_reply: format!("Port {port} is listening via {primary_listener}."),
                artifacts: vec![ArtifactEnvelope {
                    artifact_id: format!("artifact_local_ops_port_{port}"),
                    artifact_type: "diagnostic_result".to_string(),
                    title: format!("Port {port} inspection"),
                    summary: listener_summary.clone(),
                    payload_ref: format!("memory://local-ops/ports/{port}"),
                    inline_preview: Some(listener_summary.into()),
                    domain_tags: vec!["local-ops".to_string(), "network".to_string()],
                }],
                recoverability: None,
                observation: Some(ExecutionObservation::ListeningPortInspection {
                    port,
                    listener_count: listeners.len(),
                    listeners: listeners
                        .iter()
                        .map(|listener| {
                            format!(
                                "{} (PID {}) -> {}",
                                listener.command, listener.pid, listener.address
                            )
                        })
                        .collect(),
                }),
            }
        }
        Err(error) => LocalOpsExecutionResult {
            task_status: TaskStatus::Failed,
            module_status: ModuleRunStatus::Failed,
            task_summary: format!("Failed to inspect port {port}. {error}"),
            result_summary: format!(
                "Port-inspection local ops request failed for port {port}. {error}"
            ),
            assistant_reply: format!("我尝试检查端口 `{port}` 的监听状态，但没有成功：{error}"),
            quick_reply: format!("Unable to inspect port {port} yet."),
            artifacts: Vec::new(),
            recoverability: Some(Recoverability {
                retry_safe: true,
                resume_supported: false,
                hint: Some(
                    "Retry the port check after the host shell environment is available."
                        .to_string(),
                ),
            }),
            observation: None,
        },
    }
}

fn execute_inspect_python_processes(
    request: &PythonProcessInspectionRequest,
) -> LocalOpsExecutionResult {
    match inspect_python_processes(request.include_listening_ports) {
        Ok(processes) if processes.is_empty() => LocalOpsExecutionResult {
            task_status: TaskStatus::Completed,
            module_status: ModuleRunStatus::Completed,
            task_summary: "Checked local Python processes. No running python/python3 process was found.".to_string(),
            result_summary:
                "Checked local Python processes. No running python/python3 process was found."
                    .to_string(),
            assistant_reply:
                "已检查。本机当前没有发现正在运行的 `python` / `python3` 进程。".to_string(),
            quick_reply: "No running python/python3 process was found.".to_string(),
            artifacts: vec![ArtifactEnvelope {
                artifact_id: "artifact_local_ops_python_processes".to_string(),
                artifact_type: "diagnostic_result".to_string(),
                title: "Python process inspection".to_string(),
                summary: "No running python/python3 process was found.".to_string(),
                payload_ref: "memory://local-ops/python-processes".to_string(),
                inline_preview: Some("no running python/python3 process".into()),
                domain_tags: vec!["local-ops".to_string(), "process".to_string()],
            }],
            recoverability: None,
            observation: Some(ExecutionObservation::PythonProcessInspection {
                process_count: 0,
                listening_count: 0,
                processes: Vec::new(),
            }),
        },
        Ok(processes) => {
            let process_count = processes.len();
            let listening_count = processes
                .iter()
                .filter(|process| !process.listening_addresses.is_empty())
                .count();
            let process_summary = processes
                .iter()
                .map(format_python_process_summary)
                .collect::<Vec<_>>()
                .join("；");
            let primary_process = processes
                .first()
                .map(|process| format!("{} (PID {})", process.command, process.pid))
                .unwrap_or_else(|| "a python process".to_string());

            LocalOpsExecutionResult {
                task_status: TaskStatus::Completed,
                module_status: ModuleRunStatus::Completed,
                task_summary: format!(
                    "Checked local Python processes. Found {process_count} running python/python3 process(es)."
                ),
                result_summary: if request.include_listening_ports {
                    format!(
                        "Checked local Python processes and listening ports. Found {process_count} running python/python3 process(es); {listening_count} listening on TCP ports. {process_summary}."
                    )
                } else {
                    format!(
                        "Checked local Python processes. Found {process_count} running python/python3 process(es). {process_summary}."
                    )
                },
                assistant_reply: if request.include_listening_ports {
                    format!(
                        "已检查。本机当前发现 {process_count} 个正在运行的 `python` / `python3` 进程，其中 {listening_count} 个正在监听端口：{process_summary}。"
                    )
                } else {
                    format!(
                        "已检查。本机当前发现 {process_count} 个正在运行的 `python` / `python3` 进程：{process_summary}。"
                    )
                },
                quick_reply: if request.include_listening_ports {
                    format!(
                        "Found {process_count} running python/python3 process(es); {listening_count} listening on ports."
                    )
                } else {
                    format!("Found {process_count} running python/python3 process(es); primary process: {primary_process}.")
                },
                artifacts: vec![ArtifactEnvelope {
                    artifact_id: "artifact_local_ops_python_processes".to_string(),
                    artifact_type: "diagnostic_result".to_string(),
                    title: "Python process inspection".to_string(),
                    summary: process_summary.clone(),
                    payload_ref: "memory://local-ops/python-processes".to_string(),
                    inline_preview: Some(process_summary.into()),
                    domain_tags: vec![
                        "local-ops".to_string(),
                        "process".to_string(),
                        "python".to_string(),
                    ],
                }],
                recoverability: None,
                observation: Some(ExecutionObservation::PythonProcessInspection {
                    process_count,
                    listening_count,
                    processes: processes
                        .iter()
                        .map(format_python_process_summary)
                        .collect(),
                }),
            }
        }
        Err(error) => LocalOpsExecutionResult {
            task_status: TaskStatus::Failed,
            module_status: ModuleRunStatus::Failed,
            task_summary: format!("Failed to inspect local Python processes. {error}"),
            result_summary: format!("Python-process inspection failed. {error}"),
            assistant_reply: format!(
                "我尝试检查本机正在运行的 `python` / `python3` 进程，但没有成功：{error}"
            ),
            quick_reply: "Unable to inspect local Python processes yet.".to_string(),
            artifacts: Vec::new(),
            recoverability: Some(Recoverability {
                retry_safe: true,
                resume_supported: false,
                hint: Some(
                    "Retry the Python process inspection after the host process tools are available."
                        .to_string(),
                ),
            }),
            observation: None,
        },
    }
}

fn read_current_time_label() -> Result<String, String> {
    read_shell_fact(&["+%Y-%m-%d %H:%M:%S %Z"])
        .ok_or_else(|| "date returned an empty timestamp".to_string())
}

fn read_shell_fact(args: &[&str]) -> Option<String> {
    let output = Command::new("date").args(args).output().ok()?;

    if !output.status.success() {
        return None;
    }

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if stdout.is_empty() {
        None
    } else {
        Some(stdout)
    }
}

fn inspect_listening_port(port: u16) -> Result<Vec<PortListenerRecord>, String> {
    let output = Command::new("lsof")
        .args(["-nP", &format!("-iTCP:{port}"), "-sTCP:LISTEN"])
        .output()
        .map_err(|error| error.to_string())?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if output.status.code() == Some(1) && stderr.is_empty() && stdout.is_empty() {
            return Ok(Vec::new());
        }

        return Err(if !stderr.is_empty() {
            stderr
        } else if !stdout.is_empty() {
            stdout
        } else {
            format!("lsof exited with status {}", output.status)
        });
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let listeners = stdout
        .lines()
        .skip(1)
        .filter_map(parse_lsof_listener_line)
        .collect::<Vec<_>>();
    Ok(listeners)
}

fn inspect_python_processes(
    include_listening_ports: bool,
) -> Result<Vec<PythonProcessRecord>, String> {
    let output = Command::new("ps")
        .args(["-axo", "pid=,comm=,args="])
        .output()
        .map_err(|error| error.to_string())?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        return Err(if !stderr.is_empty() {
            stderr
        } else if !stdout.is_empty() {
            stdout
        } else {
            format!("ps exited with status {}", output.status)
        });
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut processes = stdout
        .lines()
        .filter_map(parse_ps_process_line)
        .filter(|process| looks_like_python_process(&process.command, &process.arguments))
        .collect::<Vec<_>>();

    if include_listening_ports && !processes.is_empty() {
        let listening_ports_by_pid = inspect_listening_ports_by_pid()?;
        for process in &mut processes {
            if let Some(addresses) = listening_ports_by_pid.get(&process.pid) {
                process.listening_addresses = addresses.clone();
            }
        }
    }

    Ok(processes)
}

fn inspect_listening_ports_by_pid() -> Result<HashMap<String, Vec<String>>, String> {
    let output = Command::new("lsof")
        .args(["-nP", "-iTCP", "-sTCP:LISTEN"])
        .output()
        .map_err(|error| error.to_string())?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if output.status.code() == Some(1) && stderr.is_empty() && stdout.is_empty() {
            return Ok(HashMap::new());
        }
        return Err(if !stderr.is_empty() {
            stderr
        } else if !stdout.is_empty() {
            stdout
        } else {
            format!("lsof exited with status {}", output.status)
        });
    }

    let mut by_pid: HashMap<String, Vec<String>> = HashMap::new();
    for listener in String::from_utf8_lossy(&output.stdout)
        .lines()
        .skip(1)
        .filter_map(parse_lsof_listener_line)
    {
        by_pid
            .entry(listener.pid)
            .or_default()
            .push(listener.address);
    }

    Ok(by_pid)
}

fn parse_lsof_listener_line(line: &str) -> Option<PortListenerRecord> {
    let columns = line.split_whitespace().collect::<Vec<_>>();
    if columns.len() < 2 {
        return None;
    }

    Some(PortListenerRecord {
        command: columns.first()?.to_string(),
        pid: columns.get(1)?.to_string(),
        address: columns.last()?.to_string(),
    })
}

fn parse_ps_process_line(line: &str) -> Option<PythonProcessRecord> {
    let mut columns = line.split_whitespace();
    let pid = columns.next()?.to_string();
    let command = columns.next()?.to_string();
    let arguments = columns.collect::<Vec<_>>().join(" ");

    Some(PythonProcessRecord {
        pid,
        command,
        arguments,
        listening_addresses: Vec::new(),
    })
}

fn looks_like_python_process(command: &str, arguments: &str) -> bool {
    let command_lower = command.to_ascii_lowercase();
    let args_lower = arguments.to_ascii_lowercase();
    command_lower.contains("python")
        || args_lower.contains("/python")
        || args_lower.contains(" python")
        || args_lower.starts_with("python")
}

fn format_python_process_summary(process: &PythonProcessRecord) -> String {
    let base = if process.arguments.trim().is_empty() {
        format!("{} (PID {})", process.command, process.pid)
    } else {
        format!(
            "{} (PID {}) — {}",
            process.command,
            process.pid,
            summarize_prompt(&process.arguments, 96)
        )
    };

    if process.listening_addresses.is_empty() {
        base
    } else {
        format!("{base} -> {}", process.listening_addresses.join(", "))
    }
}

fn execute_local_markdown_request_in_directory(
    request: &LocalMarkdownRequest,
    desktop_directory: &Path,
) -> Result<PathBuf, String> {
    fs::create_dir_all(desktop_directory).map_err(|error| error.to_string())?;
    let target_path = desktop_directory.join(&request.file_name);

    if target_path.exists() {
        return Err(format!(
            "{} already exists on the Desktop. Rename it or remove the existing file first.",
            request.file_name
        ));
    }

    fs::write(&target_path, &request.content).map_err(|error| error.to_string())?;
    Ok(target_path)
}

fn local_markdown_artifacts(file_name: &str, path: &Path, prompt: &str) -> Vec<ArtifactEnvelope> {
    vec![
        ArtifactEnvelope {
            artifact_id: format!("artifact_{}_file", file_name.replace('.', "_")),
            artifact_type: "local_file".to_string(),
            title: file_name.to_string(),
            summary: format!("Created a local Markdown file at {}.", path.display()),
            payload_ref: path.display().to_string(),
            inline_preview: None,
            domain_tags: vec!["local-filesystem".to_string(), "markdown".to_string()],
        },
        ArtifactEnvelope {
            artifact_id: format!("artifact_{}_brief", file_name.replace('.', "_")),
            artifact_type: "task_brief".to_string(),
            title: "Request brief".to_string(),
            summary: summarize_prompt(prompt, 120),
            payload_ref: "memory://local-markdown/latest".to_string(),
            inline_preview: None,
            domain_tags: vec!["workspace".to_string(), "local-filesystem".to_string()],
        },
    ]
}

fn local_markdown_success_reply(path: &Path, request: &LocalMarkdownRequest) -> (String, String) {
    (
        format!(
            "已完成。我已经在桌面创建了空白 Markdown 文档 `{}`，路径是 `{}`。",
            request.file_name,
            path.display()
        ),
        format!("Created {} on the Desktop.", request.file_name),
    )
}

fn local_markdown_failure_reply(request: &LocalMarkdownRequest, error: &str) -> (String, String) {
    (
        format!(
            "我尝试在桌面创建 `{}`，但没有成功：{}",
            request.file_name, error
        ),
        format!("Unable to create {} on the Desktop yet.", request.file_name),
    )
}

fn reminder_schedule_label(request: &ReminderAutomationRequest) -> String {
    match request.cadence {
        ScheduleCadence::Once => format!(
            "{} at {}",
            request.schedule_hint.as_deref().unwrap_or("One time"),
            request.time_of_day
        ),
        ScheduleCadence::Daily => format!("Every day at {}", request.time_of_day),
        ScheduleCadence::Weekdays => format!("Weekdays at {}", request.time_of_day),
        ScheduleCadence::Weekly => format!("Every week at {}", request.time_of_day),
    }
}

fn reminder_schedule_label_zh(request: &ReminderAutomationRequest) -> String {
    match request.cadence {
        ScheduleCadence::Once => match request.schedule_hint.as_deref() {
            Some("Today") => format!("今天 {}", request.time_of_day),
            Some("Tomorrow") => format!("明天 {}", request.time_of_day),
            Some(schedule_hint) if !schedule_hint.is_empty() && schedule_hint != "One time" => {
                format!("{schedule_hint} {}", request.time_of_day)
            }
            _ => format!("一次性 {}", request.time_of_day),
        },
        ScheduleCadence::Daily => format!("每天 {}", request.time_of_day),
        ScheduleCadence::Weekdays => format!("工作日 {}", request.time_of_day),
        ScheduleCadence::Weekly => format!("每周 {}", request.time_of_day),
    }
}

fn reminder_body_summary(request: &ReminderAutomationRequest) -> String {
    request
        .name
        .strip_prefix("提醒：")
        .unwrap_or(request.name.as_str())
        .trim()
        .to_string()
}

fn reminder_automation_artifacts(
    request: &ReminderAutomationRequest,
    prompt: &str,
) -> Vec<ArtifactEnvelope> {
    let artifact_key = request
        .name
        .chars()
        .filter(|ch| ch.is_ascii_alphanumeric())
        .collect::<String>()
        .to_ascii_lowercase();
    let artifact_key = if artifact_key.is_empty() {
        "reminder".to_string()
    } else {
        artifact_key
    };

    vec![
        ArtifactEnvelope {
            artifact_id: format!("artifact_{}_schedule", artifact_key),
            artifact_type: "automation_schedule".to_string(),
            title: request.name.clone(),
            summary: reminder_schedule_label(request),
            payload_ref: "memory://automation/latest".to_string(),
            inline_preview: None,
            domain_tags: vec!["automation".to_string(), "reminder".to_string()],
        },
        ArtifactEnvelope {
            artifact_id: format!("artifact_{}_brief", artifact_key),
            artifact_type: "task_brief".to_string(),
            title: "Reminder request brief".to_string(),
            summary: summarize_prompt(prompt, 120),
            payload_ref: "memory://automation-brief/latest".to_string(),
            inline_preview: None,
            domain_tags: vec!["automation".to_string(), "workspace".to_string()],
        },
    ]
}

fn reminder_automation_replies(request: &ReminderAutomationRequest) -> (String, String) {
    let schedule = reminder_schedule_label(request);
    let schedule_zh = reminder_schedule_label_zh(request);
    let reminder_body = reminder_body_summary(request);
    (
        format!(
            "已设置提醒“{}”。我会在{} 提醒你。",
            reminder_body, schedule_zh
        ),
        format!("Created reminder automation {}.", schedule),
    )
}

#[cfg(test)]
mod tests {
    use super::{
        ExecutionRequestMeta, ExecutionRuntime, FirstPartyExecutionIntent, HostRuntimeFacts,
        LocalOpsAction, ReminderAutomationParseResult, classify_reminder_automation_request,
        complete_reminder_automation_request_from_follow_up,
        complete_reminder_automation_request_from_follow_up_with_facts, default_desktop_directory,
        format_python_process_summary, looks_like_affirmation, parse_local_markdown_request,
        parse_local_ops_requests, parse_ps_process_line, parse_reminder_automation_request,
        parse_reminder_automation_request_with_facts, sanitize_markdown_filename, summarize_prompt,
    };
    use automation_engine::ScheduleCadence;
    use module_gateway::ModuleRunStatus;
    use task_engine::TaskStatus;

    #[test]
    fn parses_chinese_local_markdown_request() {
        let request = parse_local_markdown_request("在桌面创建一个md文档，空白内容，名称123")
            .expect("request should parse");

        assert_eq!(request.file_name, "123.md");
        assert_eq!(request.content, "");
    }

    #[test]
    fn normalizes_markdown_file_name() {
        assert_eq!(
            sanitize_markdown_filename("  “roadmap”  ").as_deref(),
            Some("roadmap.md")
        );
        assert_eq!(
            sanitize_markdown_filename("bad/name").as_deref(),
            Some("badname.md")
        );
    }

    #[test]
    fn affirmation_detection_accepts_short_confirmations() {
        assert!(looks_like_affirmation("可以，执行吧"));
        assert!(looks_like_affirmation("执行"));
        assert!(looks_like_affirmation("go ahead"));
        assert!(!looks_like_affirmation("先别动"));
    }

    #[test]
    fn runtime_creates_desktop_markdown_file_in_target_directory() {
        let temp_dir = tempfile::tempdir().expect("tempdir should create");
        let runtime = ExecutionRuntime::with_desktop_directory(temp_dir.path().join("Desktop"));
        let meta = ExecutionRequestMeta {
            task_id: "task_01".to_string(),
            module_run_id: "run_01".to_string(),
            conversation_id: Some("conv_01".to_string()),
            title: "Quick request: 在桌面创建一个md文档，空白内容，名称123".to_string(),
            prompt: "在桌面创建一个md文档，空白内容，名称123".to_string(),
            created_at: "now".to_string(),
            updated_at: "now".to_string(),
        };
        let outcome = runtime.execute_first_party(
            &FirstPartyExecutionIntent::CreateDesktopMarkdown(
                parse_local_markdown_request("在桌面创建一个md文档，空白内容，名称123")
                    .expect("request should parse"),
            ),
            &meta,
        );

        assert_eq!(outcome.task_run.status, TaskStatus::Completed);
        assert_eq!(outcome.module_run.status, ModuleRunStatus::Completed);
        assert!(
            temp_dir.path().join("Desktop").join("123.md").exists(),
            "expected markdown file to exist"
        );
    }

    #[test]
    fn default_desktop_directory_uses_home() {
        let desktop = default_desktop_directory().expect("desktop path should resolve");
        assert!(desktop.ends_with("Desktop"));
    }

    #[test]
    fn summarize_prompt_truncates_long_text() {
        let summary = summarize_prompt("abcdefghijklmnopqrstuvwxyz", 10);
        assert_eq!(summary, "abcdefghi…");
    }

    #[test]
    fn parses_chinese_one_time_reminder_request() {
        let request = parse_reminder_automation_request("明天8点通知我吃药💊")
            .expect("reminder request should parse");

        assert_eq!(request.cadence, ScheduleCadence::Once);
        assert_eq!(request.time_of_day, "08:00");
        assert_eq!(request.schedule_hint.as_deref(), Some("Tomorrow"));
        assert!(request.name.contains("吃药"));
        assert!(request.goal_prompt.contains("吃药"));
    }

    #[test]
    fn parses_wrapped_reminder_task_request_without_relative_day() {
        let request =
            parse_reminder_automation_request("创建一个任务，在12点设定一个提醒我吃药的任务")
                .expect("wrapped reminder task request should parse");

        assert_eq!(request.cadence, ScheduleCadence::Once);
        assert_eq!(request.time_of_day, "12:00");
        assert_eq!(request.schedule_hint.as_deref(), Some("One time"));
        assert_eq!(request.name, "提醒：吃药");
        assert!(request.goal_prompt.contains("吃药"));
    }

    #[test]
    fn parses_relative_hour_reminder_request_with_host_facts() {
        let facts = HostRuntimeFacts {
            local_time: "2026-04-22 16:44:45 +08".to_string(),
            time_zone: "Asia/Singapore".to_string(),
            cwd: "/tmp".to_string(),
        };
        let request = parse_reminder_automation_request_with_facts("4小时后提醒我上课", &facts)
            .expect("relative reminder request should parse");

        assert_eq!(request.cadence, ScheduleCadence::Once);
        assert_eq!(request.time_of_day, "20:44");
        assert_eq!(request.schedule_hint.as_deref(), Some("Today"));
        assert_eq!(request.name, "提醒：上课");
    }

    #[test]
    fn parses_relative_reminder_request_that_crosses_midnight() {
        let facts = HostRuntimeFacts {
            local_time: "2026-04-22 23:35:10 +08".to_string(),
            time_zone: "Asia/Singapore".to_string(),
            cwd: "/tmp".to_string(),
        };
        let request = parse_reminder_automation_request_with_facts("2小时后提醒我睡觉", &facts)
            .expect("relative reminder request should parse");

        assert_eq!(request.time_of_day, "01:35");
        assert_eq!(request.schedule_hint.as_deref(), Some("Tomorrow"));
        assert_eq!(request.name, "提醒：睡觉");
    }

    #[test]
    fn classifies_missing_reminder_time_as_clarification() {
        let classification = classify_reminder_automation_request("创建一个任务，提醒我吃药")
            .expect("reminder request should classify");

        match classification {
            ReminderAutomationParseResult::Clarify(clarification) => {
                assert!(clarification.missing_time_of_day);
                assert!(!clarification.missing_reminder_body);
                assert_eq!(
                    clarification.extracted_reminder_body.as_deref(),
                    Some("吃药")
                );
            }
            _ => panic!("expected clarification result"),
        }
    }

    #[test]
    fn follow_up_can_complete_a_partially_specified_reminder_request() {
        let request = complete_reminder_automation_request_from_follow_up(
            "创建一个任务，提醒我吃药",
            "今天12点",
        )
        .expect("follow-up should complete reminder request");

        assert_eq!(request.cadence, ScheduleCadence::Once);
        assert_eq!(request.time_of_day, "12:00");
        assert_eq!(request.schedule_hint.as_deref(), Some("Today"));
        assert_eq!(request.name, "提醒：吃药");
    }

    #[test]
    fn follow_up_body_can_complete_a_time_only_reminder_request() {
        let request = complete_reminder_automation_request_from_follow_up("今天12点提醒我", "吃药")
            .expect("follow-up body should complete reminder request");

        assert_eq!(request.cadence, ScheduleCadence::Once);
        assert_eq!(request.time_of_day, "12:00");
        assert_eq!(request.schedule_hint.as_deref(), Some("Today"));
        assert_eq!(request.name, "提醒：吃药");
    }

    #[test]
    fn relative_time_follow_up_can_complete_a_partial_reminder_request() {
        let facts = HostRuntimeFacts {
            local_time: "2026-04-22 09:15:00 +08".to_string(),
            time_zone: "Asia/Singapore".to_string(),
            cwd: "/tmp".to_string(),
        };
        let request = complete_reminder_automation_request_from_follow_up_with_facts(
            "提醒我上课",
            "4小时后",
            &facts,
        )
        .expect("relative follow-up should complete reminder request");

        assert_eq!(request.time_of_day, "13:15");
        assert_eq!(request.schedule_hint.as_deref(), Some("Today"));
        assert_eq!(request.name, "提醒：上课");
    }

    #[test]
    fn reminder_execution_creates_an_automation_draft() {
        let runtime = ExecutionRuntime::for_local_system();
        let meta = ExecutionRequestMeta {
            task_id: "task_reminder_01".to_string(),
            module_run_id: "run_reminder_01".to_string(),
            conversation_id: Some("conv_01".to_string()),
            title: "Quick request: 明天8点通知我吃药💊".to_string(),
            prompt: "明天8点通知我吃药💊".to_string(),
            created_at: "now".to_string(),
            updated_at: "now".to_string(),
        };

        let outcome = runtime.execute_first_party(
            &FirstPartyExecutionIntent::CreateReminderAutomation(
                parse_reminder_automation_request("明天8点通知我吃药💊")
                    .expect("reminder request should parse"),
            ),
            &meta,
        );

        assert_eq!(outcome.task_run.status, TaskStatus::Completed);
        assert_eq!(outcome.module_run.status, ModuleRunStatus::Completed);
        assert_eq!(outcome.automation_drafts.len(), 1);
        assert_eq!(outcome.automation_drafts[0].cadence, ScheduleCadence::Once);
        assert_eq!(outcome.automation_drafts[0].time_of_day, "08:00");
        assert!(outcome.assistant_reply.contains("08:00"));
    }

    #[test]
    fn parses_current_time_request_into_local_ops() {
        let request = parse_local_ops_requests("现在是几点")
            .into_iter()
            .next()
            .expect("current-time request should parse");

        assert!(matches!(request.action, LocalOpsAction::ReadCurrentTime));
    }

    #[test]
    fn parses_ps_process_line_into_python_process_record() {
        let process =
            parse_ps_process_line("12345 /usr/bin/python3 /usr/bin/python3 -m http.server 8000")
                .expect("ps line should parse");

        assert_eq!(process.pid, "12345");
        assert_eq!(process.command, "/usr/bin/python3");
        assert!(process.arguments.contains("http.server"));
    }

    #[test]
    fn formats_python_process_summary_with_listening_ports() {
        let summary = format_python_process_summary(&super::PythonProcessRecord {
            pid: "12345".to_string(),
            command: "python3".to_string(),
            arguments: "python3 -m http.server 8000".to_string(),
            listening_addresses: vec!["127.0.0.1:8000".to_string()],
        });

        assert!(summary.contains("PID 12345"));
        assert!(summary.contains("127.0.0.1:8000"));
    }

    #[test]
    fn current_time_local_ops_execution_completes() {
        let runtime = ExecutionRuntime::for_local_system();
        let outcome = runtime.execute_first_party(
            &FirstPartyExecutionIntent::RunLocalOps(
                parse_local_ops_requests("现在是几点")
                    .into_iter()
                    .next()
                    .expect("current-time request should parse"),
            ),
            &ExecutionRequestMeta {
                task_id: "task_local_ops_01".to_string(),
                module_run_id: "run_local_ops_01".to_string(),
                conversation_id: Some("conv_01".to_string()),
                title: "Quick request: 现在是几点".to_string(),
                prompt: "现在是几点".to_string(),
                created_at: "now".to_string(),
                updated_at: "now".to_string(),
            },
        );

        assert_eq!(outcome.task_run.status, TaskStatus::Completed);
        assert_eq!(outcome.module_run.status, ModuleRunStatus::Completed);
        assert_eq!(outcome.module_run.module_id, "geeagent.local.ops");
        assert_eq!(outcome.module_run.capability_id, "current_time");
    }
}
