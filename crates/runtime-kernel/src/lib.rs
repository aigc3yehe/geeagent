mod reboot;

use execution_runtime::{
    ControlledTerminalPlanKind, ControlledTerminalRequest, ControlledTerminalStep,
    FirstPartyExecutionIntent, ReminderAutomationParseResult,
    canonicalize_reminder_automation_request, capture_host_runtime_facts,
    classify_reminder_automation_request_with_facts,
    complete_reminder_automation_request_from_follow_up_with_facts, looks_like_affirmation,
    parse_local_markdown_request, parse_reminder_automation_request_with_facts,
    tool::{persona_allows, run_tool as run_tool_executor, shell_request_needs_approval, spec_for},
};

// Re-export the tool-layer types so the bridge and tests can reach them as
// `runtime_kernel::ToolRequest`/`runtime_kernel::ToolOutcome` without having to
// name `execution_runtime::tool::…` directly.
pub use execution_runtime::tool::{
    SHELL_ALLOW_LIST, ToolBlastRadius, ToolOutcome, ToolRequest, ToolSpec, V1_TOOL_CATALOG,
    catalog_as_json,
};
pub use reboot::*;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FirstPartyDetectionContext<'a> {
    pub message: &'a str,
    pub focused_task_id: Option<&'a str>,
    pub focused_task_title: Option<&'a str>,
    pub recent_user_messages: &'a [String],
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DetectedExecutionPlan {
    pub target_task_id: Option<String>,
    pub canonical_prompt: String,
    pub steps: Vec<ExecutionPlanStep>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExecutionPlanStep {
    pub intent: FirstPartyExecutionIntent,
    pub condition: ExecutionPlanCondition,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ExecutionPlanCondition {
    Always,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DetectedClarificationNeed {
    pub canonical_prompt: String,
    pub assistant_reply: String,
    pub quick_reply: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FirstPartyRoutingDecision {
    Execute(DetectedExecutionPlan),
    Clarify(DetectedClarificationNeed),
}

#[derive(Debug, Default, Clone, Copy)]
pub struct RuntimeKernel;

impl RuntimeKernel {
    fn execution_plan(
        target_task_id: Option<String>,
        canonical_prompt: String,
        steps: Vec<ExecutionPlanStep>,
    ) -> FirstPartyRoutingDecision {
        FirstPartyRoutingDecision::Execute(DetectedExecutionPlan {
            target_task_id,
            canonical_prompt,
            steps,
        })
    }

    fn unconditional_step(intent: FirstPartyExecutionIntent) -> ExecutionPlanStep {
        ExecutionPlanStep {
            intent,
            condition: ExecutionPlanCondition::Always,
        }
    }

    pub fn classify_first_party_execution(
        context: &FirstPartyDetectionContext<'_>,
    ) -> Option<FirstPartyRoutingDecision> {
        let trimmed_message = context.message.trim();
        if trimmed_message.is_empty() {
            return None;
        }
        let host_facts = capture_host_runtime_facts();

        if let Some(request) = parse_local_markdown_request(trimmed_message) {
            return Some(Self::execution_plan(
                None,
                trimmed_message.to_string(),
                vec![Self::unconditional_step(
                    FirstPartyExecutionIntent::CreateDesktopMarkdown(request),
                )],
            ));
        }

        if let Some(request) = parse_controlled_terminal_request(trimmed_message) {
            return Some(Self::execution_plan(
                None,
                trimmed_message.to_string(),
                vec![Self::unconditional_step(
                    FirstPartyExecutionIntent::RunControlledTerminal(request),
                )],
            ));
        }

        if let Some(reminder_result) =
            classify_reminder_automation_request_with_facts(trimmed_message, &host_facts)
        {
            return Some(match reminder_result {
                ReminderAutomationParseResult::Complete(request) => Self::execution_plan(
                    None,
                    canonicalize_reminder_automation_request(&request),
                    vec![Self::unconditional_step(
                        FirstPartyExecutionIntent::CreateReminderAutomation(request),
                    )],
                ),
                ReminderAutomationParseResult::Clarify(clarification) => {
                    FirstPartyRoutingDecision::Clarify(DetectedClarificationNeed {
                        canonical_prompt: trimmed_message.to_string(),
                        assistant_reply: clarification.assistant_reply,
                        quick_reply: clarification.quick_reply,
                    })
                }
            });
        }

        for prior_user_message in context.recent_user_messages.iter().rev() {
            if prior_user_message.trim() == trimmed_message {
                continue;
            }

            if let Some(request) = complete_reminder_automation_request_from_follow_up_with_facts(
                prior_user_message,
                trimmed_message,
                &host_facts,
            ) {
                return Some(Self::execution_plan(
                    None,
                    canonicalize_reminder_automation_request(&request),
                    vec![Self::unconditional_step(
                        FirstPartyExecutionIntent::CreateReminderAutomation(request),
                    )],
                ));
            }
        }

        let focused_task_id = context.focused_task_id?;
        if !looks_like_affirmation(trimmed_message) {
            return None;
        }

        for prior_user_message in context.recent_user_messages.iter().rev() {
            if prior_user_message.trim() == trimmed_message {
                continue;
            }
            if let Some(request) = parse_local_markdown_request(prior_user_message) {
                return Some(Self::execution_plan(
                    Some(focused_task_id.to_string()),
                    prior_user_message.trim().to_string(),
                    vec![Self::unconditional_step(
                        FirstPartyExecutionIntent::CreateDesktopMarkdown(request),
                    )],
                ));
            }
            if let Some(request) = parse_controlled_terminal_request(prior_user_message) {
                return Some(Self::execution_plan(
                    Some(focused_task_id.to_string()),
                    prior_user_message.trim().to_string(),
                    vec![Self::unconditional_step(
                        FirstPartyExecutionIntent::RunControlledTerminal(request),
                    )],
                ));
            }
            if let Some(request) =
                parse_reminder_automation_request_with_facts(prior_user_message, &host_facts)
            {
                return Some(Self::execution_plan(
                    Some(focused_task_id.to_string()),
                    canonicalize_reminder_automation_request(&request),
                    vec![Self::unconditional_step(
                        FirstPartyExecutionIntent::CreateReminderAutomation(request),
                    )],
                ));
            }
        }

        let focused_task_title = context.focused_task_title?;
        if let Some(request) = parse_local_markdown_request(focused_task_title) {
            return Some(Self::execution_plan(
                Some(focused_task_id.to_string()),
                focused_task_title.trim().to_string(),
                vec![Self::unconditional_step(
                    FirstPartyExecutionIntent::CreateDesktopMarkdown(request),
                )],
            ));
        }
        if let Some(request) = parse_controlled_terminal_request(focused_task_title) {
            return Some(Self::execution_plan(
                Some(focused_task_id.to_string()),
                focused_task_title.trim().to_string(),
                vec![Self::unconditional_step(
                    FirstPartyExecutionIntent::RunControlledTerminal(request),
                )],
            ));
        }
        if let Some(request) =
            parse_reminder_automation_request_with_facts(focused_task_title, &host_facts)
        {
            return Some(Self::execution_plan(
                Some(focused_task_id.to_string()),
                canonicalize_reminder_automation_request(&request),
                vec![Self::unconditional_step(
                    FirstPartyExecutionIntent::CreateReminderAutomation(request),
                )],
            ));
        }

        None
    }

    pub fn detect_first_party_execution(
        context: &FirstPartyDetectionContext<'_>,
    ) -> Option<DetectedExecutionPlan> {
        match Self::classify_first_party_execution(context)? {
            FirstPartyRoutingDecision::Execute(plan) => Some(plan),
            FirstPartyRoutingDecision::Clarify(_) => None,
        }
    }
}

pub fn detect_first_party_execution(
    context: &FirstPartyDetectionContext<'_>,
) -> Option<DetectedExecutionPlan> {
    RuntimeKernel::detect_first_party_execution(context)
}

pub fn classify_first_party_execution(
    context: &FirstPartyDetectionContext<'_>,
) -> Option<FirstPartyRoutingDecision> {
    RuntimeKernel::classify_first_party_execution(context)
}

// ---------------------------------------------------------------------------
// Tool dispatcher (Plan 4)
// ---------------------------------------------------------------------------

/// Routes an agent-invoked tool call through three gates before the executor
/// touches anything:
///
/// 1. **Catalog gate** — the tool must exist in `V1_TOOL_CATALOG`. Unknown
///    tools short-circuit with a `tool.unknown` error so a malformed LLM
///    response can never reach `run_tool`.
/// 2. **Persona gate** — if the active persona has an `allowed_tool_ids`
///    allow-list, the call is short-circuited with `Denied` when the requested
///    tool isn't in it. `None` means "every tool allowed" (default for `gee`).
///    Allow-list entries support a trailing-`*` wildcard (e.g. `"navigate.*"`).
/// 3. **Approval gate** — tools flagged `needs_approval = true` short-circuit
///    with `NeedsApproval` unless a non-empty `approval_token` is present.
///    Tokens are opaque to the dispatcher in v1: any non-empty string counts.
///    A later plan can add HMAC + single-use semantics.
///
/// Only after all three gates pass does the executor in `execution-runtime`
/// actually run.
#[derive(Debug, Default, Clone, Copy)]
pub struct ToolDispatcher;

impl ToolDispatcher {
    pub fn invoke(request: ToolRequest) -> ToolOutcome {
        match Self::pre_execution_gate(&request) {
            DispatchGate::ShortCircuit(outcome) => outcome,
            DispatchGate::Execute => run_tool_executor(request),
        }
    }

    /// Runs the three gates without executing the tool. Exposed for tests.
    pub fn pre_execution_gate(request: &ToolRequest) -> DispatchGate {
        // 1. Catalog gate
        let Some(spec) = spec_for(&request.tool_id) else {
            return DispatchGate::ShortCircuit(ToolOutcome::Error {
                tool_id: request.tool_id.clone(),
                code: "tool.unknown".to_string(),
                message: format!("`{}` is not a registered v1 tool", request.tool_id),
            });
        };

        // 2. Persona gate
        if !persona_allows(request.allowed_tool_ids.as_deref(), &request.tool_id) {
            return DispatchGate::ShortCircuit(ToolOutcome::Denied {
                tool_id: request.tool_id.clone(),
                reason: format!(
                    "the active persona's allow-list does not include `{}`",
                    request.tool_id
                ),
            });
        }

        // 3. Approval gate
        let needs_approval = if request.tool_id == "shell.run" {
            shell_request_needs_approval(request)
        } else {
            spec.needs_approval
        };

        if needs_approval && !has_valid_approval_token(request.approval_token.as_deref()) {
            return DispatchGate::ShortCircuit(ToolOutcome::NeedsApproval {
                tool_id: request.tool_id.clone(),
                blast_radius: spec.blast_radius,
                prompt: format!(
                    "\"{}\" requires your approval. Reason: {}",
                    spec.title, spec.description
                ),
            });
        }

        DispatchGate::Execute
    }
}

/// Result of running the three dispatcher gates.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DispatchGate {
    /// All gates passed; the caller should invoke the executor.
    Execute,
    /// A gate rejected or needs a round-trip. Return this outcome directly.
    ShortCircuit(ToolOutcome),
}

fn has_valid_approval_token(token: Option<&str>) -> bool {
    matches!(token, Some(t) if !t.trim().is_empty())
}

fn parse_controlled_terminal_request(text: &str) -> Option<ControlledTerminalRequest> {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return None;
    }

    let lowered = trimmed.to_ascii_lowercase();

    if let Some(request) = parse_explicit_script_execution_request(trimmed, &lowered) {
        return Some(request);
    }

    if let Some(request) = parse_host_diagnostics_terminal_request(trimmed, &lowered) {
        return Some(request);
    }

    if lowered.contains("docker")
        && (trimmed.contains("容器")
            || lowered.contains("container")
            || lowered.contains("containers"))
    {
        let only_startable = trimmed.contains("可启动")
            || trimmed.contains("能启动")
            || lowered.contains("startable")
            || lowered.contains("can start");
        return Some(ControlledTerminalRequest {
            goal: trimmed.to_string(),
            plan_summary: if only_startable {
                "Inspect local Docker containers, then identify which stopped containers are directly startable."
                    .to_string()
            } else {
                "Inspect local Docker containers and summarize their current status.".to_string()
            },
            kind: ControlledTerminalPlanKind::DockerContainers { only_startable },
            steps: vec![ControlledTerminalStep {
                title: "List local Docker containers with status".to_string(),
                command: "docker".to_string(),
                args: vec![
                    "ps".to_string(),
                    "-a".to_string(),
                    "--format".to_string(),
                    "{{.Names}}\t{{.Image}}\t{{.Status}}".to_string(),
                ],
                condition: execution_runtime::ControlledTerminalStepCondition::Always,
                cwd: None,
            }],
        });
    }

    if lowered.contains("git")
        && (trimmed.contains("状态")
            || trimmed.contains("分支")
            || lowered.contains("status")
            || lowered.contains("branch"))
    {
        return Some(ControlledTerminalRequest {
            goal: trimmed.to_string(),
            plan_summary: "Inspect the current repository state through a guarded git status lane."
                .to_string(),
            kind: ControlledTerminalPlanKind::GitStatus,
            steps: vec![ControlledTerminalStep {
                title: "Read the current git status".to_string(),
                command: "git".to_string(),
                args: vec![
                    "status".to_string(),
                    "--short".to_string(),
                    "--branch".to_string(),
                ],
                condition: execution_runtime::ControlledTerminalStepCondition::Always,
                cwd: None,
            }],
        });
    }

    let asks_for_directory = trimmed.contains("当前目录")
        || trimmed.contains("这个目录")
        || trimmed.contains("有哪些文件")
        || lowered.contains("current directory")
        || lowered.contains("list files")
        || lowered.contains("what files");
    if asks_for_directory {
        return Some(ControlledTerminalRequest {
            goal: trimmed.to_string(),
            plan_summary:
                "Inspect the active working directory, then summarize where GeeAgent is operating."
                    .to_string(),
            kind: ControlledTerminalPlanKind::DirectoryListing,
            steps: vec![
                ControlledTerminalStep {
                    title: "Read the current working directory".to_string(),
                    command: "pwd".to_string(),
                    args: Vec::new(),
                    condition: execution_runtime::ControlledTerminalStepCondition::Always,
                    cwd: None,
                },
                ControlledTerminalStep {
                    title: "List files in the current working directory".to_string(),
                    command: "ls".to_string(),
                    args: vec!["-la".to_string()],
                    condition: execution_runtime::ControlledTerminalStepCondition::Always,
                    cwd: None,
                },
            ],
        });
    }

    None
}

fn parse_host_diagnostics_terminal_request(
    trimmed: &str,
    lowered: &str,
) -> Option<ControlledTerminalRequest> {
    let asks_for_python = lowered.contains("python")
        && (trimmed.contains("进程")
            || trimmed.contains("程序")
            || trimmed.contains("服务")
            || trimmed.contains("运行")
            || trimmed.contains("看看")
            || trimmed.contains("检查")
            || trimmed.contains("告诉我")
            || trimmed.contains("哪些")
            || lowered.contains("process")
            || lowered.contains("service")
            || lowered.contains("running")
            || lowered.contains("check")
            || lowered.contains("inspect")
            || lowered.contains("tell me"));
    let asks_for_port = (trimmed.contains("端口") || lowered.contains("port"))
        && (trimmed.contains("占用")
            || trimmed.contains("监听")
            || trimmed.contains("被占")
            || trimmed.contains("有没有")
            || trimmed.contains("检查")
            || lowered.contains("listen")
            || lowered.contains("occupied")
            || lowered.contains("in use")
            || lowered.contains("check"));
    let asks_for_current_time = trimmed.contains("当前时间")
        || trimmed.contains("本地时间")
        || trimmed.contains("现在是几点")
        || lowered.contains("current time")
        || lowered.contains("what time");

    if !(asks_for_python || asks_for_port) {
        return None;
    }

    let port = asks_for_port
        .then(|| extract_terminal_port_number(trimmed))
        .flatten();
    let conditional_port = asks_for_python
        && port.is_some()
        && [
            "如果没有",
            "如果没",
            "没有的话",
            "if no",
            "if there is no",
            "if none",
        ]
        .iter()
        .any(|pattern| trimmed.contains(pattern) || lowered.contains(pattern));

    let mut steps = Vec::new();
    if asks_for_python {
        steps.push(ControlledTerminalStep {
            title: "Inspect running Python processes".to_string(),
            command: "ps".to_string(),
            args: vec!["-axo".to_string(), "pid=,comm=,args=".to_string()],
            condition: execution_runtime::ControlledTerminalStepCondition::Always,
            cwd: None,
        });
    }
    if let Some(port) = port {
        steps.push(ControlledTerminalStep {
            title: format!("Inspect LISTEN state for port {port}"),
            command: "lsof".to_string(),
            args: vec![
                "-nP".to_string(),
                format!("-iTCP:{port}"),
                "-sTCP:LISTEN".to_string(),
            ],
            condition: if conditional_port {
                execution_runtime::ControlledTerminalStepCondition::IfPreviousPythonInspectionEmpty
            } else {
                execution_runtime::ControlledTerminalStepCondition::Always
            },
            cwd: None,
        });
    }

    Some(ControlledTerminalRequest {
        goal: trimmed.to_string(),
        plan_summary: if conditional_port {
            format!(
                "Inspect local Python processes first, and only inspect port {} if no Python service is running.",
                port.unwrap_or_default()
            )
        } else if asks_for_python && port.is_some() {
            format!(
                "Inspect local Python processes and inspect port {} in the same terminal run.",
                port.unwrap_or_default()
            )
        } else if asks_for_python {
            "Inspect local Python processes through the guarded terminal lane.".to_string()
        } else {
            format!(
                "Inspect whether port {} is occupied through the guarded terminal lane.",
                port.unwrap_or_default()
            )
        },
        kind: ControlledTerminalPlanKind::HostDiagnostics {
            include_current_time: asks_for_current_time,
        },
        steps,
    })
}

fn extract_terminal_port_number(text: &str) -> Option<u16> {
    let mut token = String::new();
    for ch in text.chars() {
        if ch.is_ascii_digit() {
            token.push(ch);
            if token.len() > 5 {
                token.clear();
            }
            continue;
        }
        if !token.is_empty() {
            if let Ok(port) = token.parse::<u16>() {
                if port > 0 {
                    return Some(port);
                }
            }
            token.clear();
        }
    }
    if token.is_empty() {
        None
    } else {
        token.parse::<u16>().ok().filter(|port| *port > 0)
    }
}

fn parse_explicit_script_execution_request(
    trimmed: &str,
    lowered: &str,
) -> Option<ControlledTerminalRequest> {
    let mentions_running = trimmed.contains("执行")
        || trimmed.contains("运行")
        || trimmed.contains("启动")
        || lowered.contains("run ")
        || lowered.contains("start ");
    if !mentions_running {
        return None;
    }

    let cwd = lowered
        .find("cd ")
        .and_then(|index| trimmed.get(index + 3..))
        .map(|rest| {
            rest.split(|ch: char| ch.is_whitespace() || ['，', ',', '。', ';'].contains(&ch))
                .next()
                .unwrap_or("")
                .trim()
                .trim_matches('"')
                .trim_matches('\'')
                .to_string()
        })
        .filter(|candidate| candidate.starts_with('/'));

    let script = trimmed
        .split(|ch: char| ch.is_whitespace() || ['，', ',', '。', ';', ':', '：'].contains(&ch))
        .find(|token| token.ends_with(".sh"))
        .map(|token| token.trim_matches('"').trim_matches('\'').to_string());

    let script = script?;
    let cwd = cwd?;

    Some(ControlledTerminalRequest {
        goal: trimmed.to_string(),
        plan_summary: format!(
            "Enter {} and execute the script {} through the guarded terminal lane.",
            cwd, script
        ),
        kind: ControlledTerminalPlanKind::GenericShell {
            subject: format!("script {}", script),
        },
        steps: vec![ControlledTerminalStep {
            title: format!("Run {}", script),
            command: "sh".to_string(),
            args: vec![format!("./{}", script)],
            condition: execution_runtime::ControlledTerminalStepCondition::Always,
            cwd: Some(cwd),
        }],
    })
}

/// Top-level entrypoint the bridge calls. Thin wrapper around
/// `ToolDispatcher::invoke`.
pub fn invoke_tool(request: ToolRequest) -> ToolOutcome {
    ToolDispatcher::invoke(request)
}

#[cfg(test)]
mod tool_dispatcher_tests {
    use super::*;
    use serde_json::json;

    fn base_request(tool_id: &str) -> ToolRequest {
        ToolRequest {
            tool_id: tool_id.to_string(),
            arguments: json!({}),
            allowed_tool_ids: None,
            approval_token: None,
            files_root: None,
        }
    }

    #[test]
    fn unknown_tool_short_circuits_with_tool_unknown() {
        let outcome = ToolDispatcher::invoke(base_request("does.not.exist"));
        match outcome {
            ToolOutcome::Error { code, .. } => assert_eq!(code, "tool.unknown"),
            other => panic!("expected tool.unknown, got {other:?}"),
        }
    }

    #[test]
    fn persona_allow_list_denies_tools_not_in_list() {
        let mut request = base_request("shell.run");
        request.allowed_tool_ids = Some(vec!["navigate.*".to_string()]);
        request.approval_token = Some("ok".to_string());
        let outcome = ToolDispatcher::invoke(request);
        match outcome {
            ToolOutcome::Denied { reason, .. } => {
                assert!(reason.contains("shell.run"), "reason was {reason}");
            }
            other => panic!("expected Denied, got {other:?}"),
        }
    }

    #[test]
    fn persona_allow_list_with_wildcard_permits_namespaced_tools() {
        let mut request = base_request("navigate.openSection");
        request.arguments = json!({ "section": "home" });
        request.allowed_tool_ids = Some(vec!["navigate.*".to_string()]);
        match ToolDispatcher::invoke(request) {
            ToolOutcome::Completed { payload, .. } => {
                assert_eq!(payload["section"], "home");
            }
            other => panic!("expected completion, got {other:?}"),
        }
    }

    #[test]
    fn approval_required_tools_short_circuit_until_token_present() {
        let request = base_request("files.writeText");
        match ToolDispatcher::invoke(request) {
            ToolOutcome::NeedsApproval { tool_id, .. } => {
                assert_eq!(tool_id, "files.writeText");
            }
            other => panic!("expected NeedsApproval, got {other:?}"),
        }
    }

    #[test]
    fn approval_token_whitespace_only_is_rejected() {
        let mut request = base_request("files.writeText");
        request.approval_token = Some("   ".to_string());
        match ToolDispatcher::invoke(request) {
            ToolOutcome::NeedsApproval { .. } => {}
            other => panic!("whitespace token should be treated as absent, got {other:?}"),
        }
    }

    #[test]
    fn denied_precedes_needs_approval() {
        // A persona that denies shell.run should see Denied — not NeedsApproval.
        let mut request = base_request("shell.run");
        request.allowed_tool_ids = Some(vec!["navigate.*".to_string()]);
        match ToolDispatcher::invoke(request) {
            ToolOutcome::Denied { .. } => {}
            other => panic!("Denied must win over NeedsApproval, got {other:?}"),
        }
    }

    #[test]
    fn read_only_shell_request_can_execute_without_explicit_approval() {
        let mut request = base_request("shell.run");
        request.arguments = json!({
            "command": "pwd",
            "args": [],
        });

        match ToolDispatcher::pre_execution_gate(&request) {
            DispatchGate::Execute => {}
            other => panic!("expected read-only shell request to execute directly, got {other:?}"),
        }
    }

    #[test]
    fn navigate_open_section_runs_end_to_end() {
        let mut request = base_request("navigate.openSection");
        request.arguments = json!({ "section": "settings" });
        match ToolDispatcher::invoke(request) {
            ToolOutcome::Completed { payload, tool_id } => {
                assert_eq!(tool_id, "navigate.openSection");
                assert_eq!(payload["section"], "settings");
                assert_eq!(payload["intent"], "navigate.section");
            }
            other => panic!("expected completion, got {other:?}"),
        }
    }

    #[test]
    fn invoke_tool_top_level_matches_dispatcher_invoke() {
        let mut a = base_request("navigate.openSection");
        a.arguments = json!({ "section": "home" });
        let mut b = a.clone();
        assert_eq!(invoke_tool(a), ToolDispatcher::invoke(b.clone()));
        // Sanity: the clone must still produce the same outcome the second run.
        b.arguments = json!({ "section": "home" });
        assert!(matches!(invoke_tool(b), ToolOutcome::Completed { .. }));
    }
}

#[cfg(test)]
mod tests {
    use super::{
        ExecutionPlanCondition, ExecutionPlanStep, FirstPartyDetectionContext,
        FirstPartyRoutingDecision, classify_first_party_execution, detect_first_party_execution,
    };
    use execution_runtime::parse_reminder_automation_request;

    #[test]
    fn direct_markdown_request_becomes_execution_plan() {
        let recent_user_messages = vec![];
        let plan = detect_first_party_execution(&FirstPartyDetectionContext {
            message: "在桌面创建一个md文档，空白内容，名称123",
            focused_task_id: None,
            focused_task_title: None,
            recent_user_messages: &recent_user_messages,
        })
        .expect("expected direct local execution plan");

        assert_eq!(plan.target_task_id, None);
        assert!(plan.canonical_prompt.contains("名称123"));
    }

    #[test]
    fn affirmation_reuses_prior_user_request_when_task_is_focused() {
        let recent_user_messages = vec![
            "在桌面创建一个md文档，空白内容，名称123".to_string(),
            "别的事情".to_string(),
        ];
        let plan = detect_first_party_execution(&FirstPartyDetectionContext {
            message: "可以，执行吧",
            focused_task_id: Some("task_local_md"),
            focused_task_title: Some("Quick request: 在桌面创建一个md文档，空白内容，名称123"),
            recent_user_messages: &recent_user_messages,
        })
        .expect("expected affirmation to resolve");

        assert_eq!(plan.target_task_id.as_deref(), Some("task_local_md"));
        assert!(plan.canonical_prompt.contains("名称123"));
    }

    #[test]
    fn affirmation_without_focused_task_does_not_execute() {
        let recent_user_messages = vec!["在桌面创建一个md文档，空白内容，名称123".to_string()];
        let plan = detect_first_party_execution(&FirstPartyDetectionContext {
            message: "可以，执行吧",
            focused_task_id: None,
            focused_task_title: None,
            recent_user_messages: &recent_user_messages,
        });

        assert!(plan.is_none());
    }

    #[test]
    fn direct_reminder_request_becomes_execution_plan() {
        let recent_user_messages = vec![];
        let plan = detect_first_party_execution(&FirstPartyDetectionContext {
            message: "明天8点通知我吃药💊",
            focused_task_id: None,
            focused_task_title: None,
            recent_user_messages: &recent_user_messages,
        })
        .expect("expected reminder execution plan");

        assert_eq!(plan.target_task_id, None);
        match plan.steps.as_slice() {
            [
                ExecutionPlanStep {
                    intent:
                        execution_runtime::FirstPartyExecutionIntent::CreateReminderAutomation(request),
                    condition: ExecutionPlanCondition::Always,
                },
            ] => {
                let reparsed = parse_reminder_automation_request(&plan.canonical_prompt)
                    .expect("canonical prompt should stay parseable");
                assert_eq!(request.time_of_day, "08:00");
                assert_eq!(reparsed.time_of_day, "08:00");
            }
            _ => panic!("expected reminder automation intent"),
        }
    }

    #[test]
    fn wrapped_reminder_task_request_becomes_execution_plan() {
        let recent_user_messages = vec![];
        let plan = detect_first_party_execution(&FirstPartyDetectionContext {
            message: "创建一个任务，在12点设定一个提醒我吃药的任务",
            focused_task_id: None,
            focused_task_title: None,
            recent_user_messages: &recent_user_messages,
        })
        .expect("expected wrapped reminder task request to resolve");

        assert_eq!(plan.target_task_id, None);
        match plan.steps.as_slice() {
            [
                ExecutionPlanStep {
                    intent:
                        execution_runtime::FirstPartyExecutionIntent::CreateReminderAutomation(request),
                    condition: ExecutionPlanCondition::Always,
                },
            ] => {
                assert_eq!(request.time_of_day, "12:00");
                assert_eq!(request.schedule_hint.as_deref(), Some("One time"));
            }
            _ => panic!("expected reminder automation intent"),
        }
    }

    #[test]
    fn incomplete_reminder_request_returns_clarification() {
        let recent_user_messages = vec![];
        let decision = classify_first_party_execution(&FirstPartyDetectionContext {
            message: "创建一个任务，提醒我吃药",
            focused_task_id: None,
            focused_task_title: None,
            recent_user_messages: &recent_user_messages,
        })
        .expect("expected reminder clarification");

        match decision {
            FirstPartyRoutingDecision::Clarify(clarification) => {
                assert!(clarification.assistant_reply.contains("缺少时间"));
                assert!(clarification.quick_reply.contains("needs a time"));
            }
            _ => panic!("expected clarification decision"),
        }
    }

    #[test]
    fn reminder_follow_up_can_finish_a_prior_partial_request() {
        let recent_user_messages = vec!["创建一个任务，提醒我吃药".to_string()];
        let decision = classify_first_party_execution(&FirstPartyDetectionContext {
            message: "今天12点",
            focused_task_id: None,
            focused_task_title: None,
            recent_user_messages: &recent_user_messages,
        })
        .expect("expected reminder follow-up to resolve");

        match decision {
            FirstPartyRoutingDecision::Execute(plan) => match plan.steps.as_slice() {
                [
                    ExecutionPlanStep {
                        intent:
                            execution_runtime::FirstPartyExecutionIntent::CreateReminderAutomation(
                                request,
                            ),
                        condition: ExecutionPlanCondition::Always,
                    },
                ] => {
                    assert_eq!(request.time_of_day, "12:00");
                    assert_eq!(request.name, "提醒：吃药");
                }
                _ => panic!("expected reminder automation intent"),
            },
            _ => panic!("expected execution plan"),
        }
    }

    #[test]
    fn relative_reminder_request_is_canonicalized_to_absolute_time() {
        let recent_user_messages = vec![];
        let plan = detect_first_party_execution(&FirstPartyDetectionContext {
            message: "4小时后提醒我上课",
            focused_task_id: None,
            focused_task_title: None,
            recent_user_messages: &recent_user_messages,
        })
        .expect("expected relative reminder execution plan");

        match plan.steps.as_slice() {
            [
                ExecutionPlanStep {
                    intent:
                        execution_runtime::FirstPartyExecutionIntent::CreateReminderAutomation(request),
                    condition: ExecutionPlanCondition::Always,
                },
            ] => {
                assert_eq!(request.name, "提醒：上课");
                assert!(plan.canonical_prompt.contains("提醒我上课"));
                assert!(!plan.canonical_prompt.contains("小时后"));
            }
            _ => panic!("expected reminder automation intent"),
        }
    }

    #[test]
    fn current_time_request_is_not_routed_into_a_first_party_tool_plan() {
        let recent_user_messages = vec![];
        let plan = detect_first_party_execution(&FirstPartyDetectionContext {
            message: "现在是几点",
            focused_task_id: None,
            focused_task_title: None,
            recent_user_messages: &recent_user_messages,
        });

        assert!(
            plan.is_none(),
            "current time should be answered from runtime facts"
        );
    }

    #[test]
    fn port_check_request_becomes_controlled_terminal_execution_plan() {
        let recent_user_messages = vec![];
        let plan = detect_first_party_execution(&FirstPartyDetectionContext {
            message: "你看看3000端口有没有被占用",
            focused_task_id: None,
            focused_task_title: None,
            recent_user_messages: &recent_user_messages,
        })
        .expect("expected port-inspection request to resolve");

        match plan.steps.as_slice() {
            [
                ExecutionPlanStep {
                    intent:
                        execution_runtime::FirstPartyExecutionIntent::RunControlledTerminal(request),
                    condition: ExecutionPlanCondition::Always,
                },
            ] => {
                assert!(matches!(
                    request.kind,
                    execution_runtime::ControlledTerminalPlanKind::HostDiagnostics {
                        include_current_time: false
                    }
                ));
                assert_eq!(request.steps.len(), 1);
                assert_eq!(request.steps[0].command, "lsof");
                assert!(request.steps[0].args.iter().any(|arg| arg == "-iTCP:3000"));
            }
            other => panic!("expected controlled terminal intent, got {other:?}"),
        }
    }

    #[test]
    fn python_service_request_becomes_controlled_terminal_execution_plan() {
        let recent_user_messages = vec![];
        let plan = detect_first_party_execution(&FirstPartyDetectionContext {
            message: "你看看现在有什么正在运行的python服务",
            focused_task_id: None,
            focused_task_title: None,
            recent_user_messages: &recent_user_messages,
        })
        .expect("expected python-service request to resolve");

        match plan.steps.as_slice() {
            [
                ExecutionPlanStep {
                    intent:
                        execution_runtime::FirstPartyExecutionIntent::RunControlledTerminal(request),
                    condition: ExecutionPlanCondition::Always,
                },
            ] => {
                assert!(matches!(
                    request.kind,
                    execution_runtime::ControlledTerminalPlanKind::HostDiagnostics {
                        include_current_time: false
                    }
                ));
                assert_eq!(request.steps.len(), 1);
                assert_eq!(request.steps[0].command, "ps");
            }
            other => panic!("expected controlled terminal intent, got {other:?}"),
        }
    }

    #[test]
    fn docker_container_request_becomes_controlled_terminal_execution_plan() {
        let recent_user_messages = vec![];
        let plan = detect_first_party_execution(&FirstPartyDetectionContext {
            message: "你看下本机docker里面有什么可启动的容器",
            focused_task_id: None,
            focused_task_title: None,
            recent_user_messages: &recent_user_messages,
        })
        .expect("expected docker request to resolve");

        match plan.steps.as_slice() {
            [
                ExecutionPlanStep {
                    intent:
                        execution_runtime::FirstPartyExecutionIntent::RunControlledTerminal(request),
                    condition: ExecutionPlanCondition::Always,
                },
            ] => {
                assert!(matches!(
                    request.kind,
                    execution_runtime::ControlledTerminalPlanKind::DockerContainers {
                        only_startable: true
                    }
                ));
                assert_eq!(request.steps.len(), 1);
                assert_eq!(request.steps[0].command, "docker");
                assert_eq!(request.steps[0].args[0], "ps");
            }
            other => panic!("expected controlled terminal intent, got {other:?}"),
        }
    }

    #[test]
    fn explicit_script_request_becomes_generic_controlled_terminal_plan() {
        let recent_user_messages = vec![];
        let plan = detect_first_party_execution(&FirstPartyDetectionContext {
            message: "cd /tmp/demo-app 需要运行的文件是 run.sh",
            focused_task_id: None,
            focused_task_title: None,
            recent_user_messages: &recent_user_messages,
        })
        .expect("expected explicit script request to resolve");

        match plan.steps.as_slice() {
            [
                ExecutionPlanStep {
                    intent:
                        execution_runtime::FirstPartyExecutionIntent::RunControlledTerminal(request),
                    condition: ExecutionPlanCondition::Always,
                },
            ] => {
                assert!(matches!(
                    request.kind,
                    execution_runtime::ControlledTerminalPlanKind::GenericShell { .. }
                ));
                assert_eq!(request.steps.len(), 1);
                assert_eq!(request.steps[0].command, "sh");
                assert_eq!(request.steps[0].args, vec!["./run.sh".to_string()]);
                assert_eq!(request.steps[0].cwd.as_deref(), Some("/tmp/demo-app"));
            }
            other => panic!("expected controlled terminal intent, got {other:?}"),
        }
    }

    #[test]
    fn affirmation_reuses_prior_controlled_terminal_request_when_task_is_focused() {
        let recent_user_messages = vec!["cd /tmp/demo-app 需要运行的文件是 run.sh".to_string()];
        let plan = detect_first_party_execution(&FirstPartyDetectionContext {
            message: "执行",
            focused_task_id: Some("task_terminal_01"),
            focused_task_title: Some("Terminal request: run.sh"),
            recent_user_messages: &recent_user_messages,
        })
        .expect("expected affirmation to reuse prior controlled terminal request");

        assert_eq!(plan.target_task_id.as_deref(), Some("task_terminal_01"));
        match plan.steps.as_slice() {
            [
                ExecutionPlanStep {
                    intent:
                        execution_runtime::FirstPartyExecutionIntent::RunControlledTerminal(request),
                    condition: ExecutionPlanCondition::Always,
                },
            ] => {
                assert_eq!(request.steps[0].command, "sh");
                assert_eq!(request.steps[0].cwd.as_deref(), Some("/tmp/demo-app"));
            }
            other => panic!("expected controlled terminal intent, got {other:?}"),
        }
    }

    #[test]
    fn compound_runtime_facts_and_python_request_becomes_a_terminal_host_diagnostics_plan() {
        let recent_user_messages = vec![];
        let plan = detect_first_party_execution(&FirstPartyDetectionContext {
            message: "获取现在的本地时间，告诉我此时此刻本地有哪些python程序在运行",
            focused_task_id: None,
            focused_task_title: None,
            recent_user_messages: &recent_user_messages,
        })
        .expect("expected compound local ops request to resolve");

        match plan.steps.as_slice() {
            [
                ExecutionPlanStep {
                    intent:
                        execution_runtime::FirstPartyExecutionIntent::RunControlledTerminal(request),
                    condition: ExecutionPlanCondition::Always,
                },
            ] => {
                assert!(matches!(
                    request.kind,
                    execution_runtime::ControlledTerminalPlanKind::HostDiagnostics {
                        include_current_time: true
                    }
                ));
                assert_eq!(request.steps.len(), 1);
                assert_eq!(request.steps[0].command, "ps");
            }
            other => panic!("expected controlled terminal intent, got {other:?}"),
        }
    }

    #[test]
    fn conditional_python_then_port_request_stays_inside_one_host_diagnostics_terminal_plan() {
        let recent_user_messages = vec![];
        let plan = detect_first_party_execution(&FirstPartyDetectionContext {
            message: "看看本机python服务有什么正在运行吗？告诉我这是什么服务。如果没有正在运行的服务，你再看看3000端口是否被占用。",
            focused_task_id: None,
            focused_task_title: None,
            recent_user_messages: &recent_user_messages,
        })
        .expect("expected conditional diagnostics request to resolve");

        match plan.steps.as_slice() {
            [
                ExecutionPlanStep {
                    intent:
                        execution_runtime::FirstPartyExecutionIntent::RunControlledTerminal(request),
                    condition: ExecutionPlanCondition::Always,
                },
            ] => {
                assert!(matches!(
                    request.kind,
                    execution_runtime::ControlledTerminalPlanKind::HostDiagnostics {
                        include_current_time: false
                    }
                ));
                assert_eq!(request.steps.len(), 2);
                assert_eq!(request.steps[0].command, "ps");
                assert_eq!(request.steps[1].command, "lsof");
                assert!(matches!(
                    request.steps[1].condition,
                    execution_runtime::ControlledTerminalStepCondition::IfPreviousPythonInspectionEmpty
                ));
            }
            other => panic!("expected controlled terminal intent, got {other:?}"),
        }
    }
}
