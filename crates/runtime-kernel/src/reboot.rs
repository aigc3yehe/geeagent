use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum KernelSurfaceKind {
    DesktopWorkspaceChat,
    DesktopQuickInput,
    CliWorkspaceChat,
    CliQuickInput,
    Automation,
    BackgroundAgent,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum KernelSessionStatus {
    Idle,
    Active,
    Interrupted,
    Archived,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KernelSession {
    pub session_id: String,
    pub surface_kind: KernelSurfaceKind,
    pub created_at: String,
    pub updated_at: String,
    pub active_agent_id: String,
    pub status: KernelSessionStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub current_run_id: Option<String>,
    pub history_cursor: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cwd: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub workspace_ref: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub runtime_home_ref: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub continuation_strategy: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub summary_ref: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum KernelRunStatus {
    Queued,
    Running,
    Interrupted,
    Completed,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KernelRun {
    pub run_id: String,
    pub session_id: String,
    pub origin_message_id: String,
    pub status: KernelRunStatus,
    pub started_at: String,
    pub updated_at: String,
    pub step_count: u32,
    pub max_steps: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub run_kind: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub active_step_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent_run_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub interrupt_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub stop_reason: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub final_output_ref: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error_summary: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RunStepPhase {
    TurnSetup,
    ModelStep,
    Dispatch,
    Commit,
    ContinueCheck,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RunStepOutcome {
    Continued,
    Interrupted,
    Finalized,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RunStep {
    pub step_id: String,
    pub run_id: String,
    pub index: u32,
    pub phase: RunStepPhase,
    pub started_at: String,
    pub updated_at: String,
    pub outcome: RunStepOutcome,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model_decision_ref: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub dispatch_target: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool_invocation_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub interrupt_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub summary: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum KernelToolInvocationStatus {
    Admitted,
    Blocked,
    Executing,
    Completed,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KernelToolInvocation {
    pub tool_invocation_id: String,
    pub run_id: String,
    pub step_id: String,
    pub capability_family: String,
    pub tool_name: String,
    pub status: KernelToolInvocationStatus,
    pub started_at: String,
    pub updated_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub input_summary: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub approval_policy: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub execution_backend: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cwd: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub command_preview: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub correlation_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum KernelToolResultStatus {
    Success,
    Error,
    Blocked,
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KernelToolResult {
    pub tool_result_id: String,
    pub tool_invocation_id: String,
    pub run_id: String,
    pub status: KernelToolResultStatus,
    pub created_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub content_ref: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub structured_payload: Option<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error_summary: Option<String>,
    #[serde(default)]
    pub artifact_ids: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub exit_code: Option<i32>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RunInterruptReason {
    ApprovalRequired,
    UserInputRequired,
    EnvironmentBlocked,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RunInterruptStatus {
    Open,
    Resolved,
    Rejected,
    Expired,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RunInterruption {
    pub interrupt_id: String,
    pub run_id: String,
    pub reason: RunInterruptReason,
    pub status: RunInterruptStatus,
    pub created_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub approval_request_ref: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub requested_action_summary: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub resume_token: Option<String>,
    #[serde(default)]
    pub policy_tags: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub default_resolution: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ArtifactRecord {
    pub artifact_id: String,
    pub run_id: String,
    pub created_at: String,
    pub artifact_kind: String,
    pub storage_ref: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mime_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub preview_summary: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_tool_invocation_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub size_bytes: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QueuedRuntimeMessage {
    pub message_id: String,
    pub content: String,
    pub created_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_kind: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AgentRuntimeCore {
    pub session_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub active_run_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub active_step_id: Option<String>,
    pub max_steps_per_run: u32,
    #[serde(default)]
    pub steering_queue: Vec<QueuedRuntimeMessage>,
    #[serde(default)]
    pub follow_up_queue: Vec<QueuedRuntimeMessage>,
}

impl AgentRuntimeCore {
    pub fn new(session_id: impl Into<String>, max_steps_per_run: u32) -> Self {
        Self {
            session_id: session_id.into(),
            active_run_id: None,
            active_step_id: None,
            max_steps_per_run,
            steering_queue: Vec::new(),
            follow_up_queue: Vec::new(),
        }
    }

    pub fn bind_run(&mut self, run_id: impl Into<String>) {
        self.active_run_id = Some(run_id.into());
        self.active_step_id = None;
    }

    pub fn clear_run(&mut self) {
        self.active_run_id = None;
        self.active_step_id = None;
    }

    pub fn start_step(&mut self, step_id: impl Into<String>) {
        self.active_step_id = Some(step_id.into());
    }

    pub fn clear_step(&mut self) {
        self.active_step_id = None;
    }

    pub fn steer(&mut self, message: QueuedRuntimeMessage) {
        self.steering_queue.push(message);
    }

    pub fn follow_up(&mut self, message: QueuedRuntimeMessage) {
        self.follow_up_queue.push(message);
    }

    pub fn drain_steering(&mut self) -> Vec<QueuedRuntimeMessage> {
        std::mem::take(&mut self.steering_queue)
    }

    pub fn drain_follow_up(&mut self) -> Vec<QueuedRuntimeMessage> {
        std::mem::take(&mut self.follow_up_queue)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum KernelEventPayload {
    SessionCreated {
        session: KernelSession,
    },
    SessionResumed {
        session_id: String,
    },
    SessionCwdChanged {
        cwd: String,
    },
    SessionAgentChanged {
        active_agent_id: String,
    },
    RunCreated {
        run: KernelRun,
    },
    RunStarted {
        run_id: String,
    },
    RunInterrupted {
        interrupt_id: String,
        reason: RunInterruptReason,
    },
    RunResumed {
        run_id: String,
    },
    RunCompleted {
        run_id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        final_output_ref: Option<String>,
    },
    RunFailed {
        run_id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        error_summary: Option<String>,
    },
    RunCancelled {
        run_id: String,
    },
    StepStarted {
        step: RunStep,
    },
    StepModelOutputRecorded {
        step_id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        summary: Option<String>,
    },
    StepCommitFinished {
        step_id: String,
    },
    StepContinue {
        step_id: String,
    },
    StepFinalize {
        step_id: String,
    },
    ToolInvocationCreated {
        invocation: KernelToolInvocation,
    },
    ToolBlocked {
        invocation_id: String,
        reason: String,
    },
    ToolExecutionStarted {
        invocation_id: String,
    },
    ToolExecutionFinished {
        invocation_id: String,
        status: KernelToolInvocationStatus,
    },
    ToolResultRecorded {
        result: KernelToolResult,
    },
    InterruptOpened {
        interruption: RunInterruption,
    },
    InterruptResolved {
        interrupt_id: String,
    },
    InterruptRejected {
        interrupt_id: String,
    },
    ArtifactCreated {
        artifact: ArtifactRecord,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KernelEvent {
    pub event_id: String,
    pub sequence: u64,
    pub occurred_at: String,
    pub session_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub run_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub step_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool_invocation_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub interrupt_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub actor_kind: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub surface_kind: Option<KernelSurfaceKind>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub summary: Option<String>,
    pub payload: KernelEventPayload,
}

#[derive(Debug, Default, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KernelEventLog {
    next_sequence: u64,
    events: Vec<KernelEvent>,
}

impl KernelEventLog {
    pub fn append(
        &mut self,
        event_id: impl Into<String>,
        occurred_at: impl Into<String>,
        session_id: impl Into<String>,
        payload: KernelEventPayload,
    ) -> &KernelEvent {
        self.next_sequence = self.next_sequence.saturating_add(1);
        let event = KernelEvent {
            event_id: event_id.into(),
            sequence: self.next_sequence,
            occurred_at: occurred_at.into(),
            session_id: session_id.into(),
            run_id: None,
            step_id: None,
            tool_invocation_id: None,
            interrupt_id: None,
            actor_kind: None,
            surface_kind: None,
            summary: None,
            payload,
        };
        self.events.push(event);
        self.events
            .last()
            .expect("append always pushes one event before returning")
    }

    pub fn append_with_context(&mut self, mut event: KernelEvent) -> &KernelEvent {
        self.next_sequence = self.next_sequence.saturating_add(1);
        event.sequence = self.next_sequence;
        self.events.push(event);
        self.events
            .last()
            .expect("append_with_context always pushes one event before returning")
    }

    pub fn events(&self) -> &[KernelEvent] {
        &self.events
    }

    pub fn next_sequence(&self) -> u64 {
        self.next_sequence.saturating_add(1)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AgentSessionRuntime {
    pub session: KernelSession,
    pub core: AgentRuntimeCore,
    pub event_log: KernelEventLog,
    #[serde(default)]
    pub runs: BTreeMap<String, KernelRun>,
    #[serde(default)]
    pub steps: BTreeMap<String, RunStep>,
    #[serde(default)]
    pub tool_invocations: BTreeMap<String, KernelToolInvocation>,
    #[serde(default)]
    pub tool_results: BTreeMap<String, KernelToolResult>,
    #[serde(default)]
    pub interruptions: BTreeMap<String, RunInterruption>,
    #[serde(default)]
    pub artifacts: BTreeMap<String, ArtifactRecord>,
}

impl AgentSessionRuntime {
    pub fn new(session: KernelSession, max_steps_per_run: u32) -> Self {
        let core = AgentRuntimeCore::new(session.session_id.clone(), max_steps_per_run);
        Self {
            session,
            core,
            event_log: KernelEventLog::default(),
            runs: BTreeMap::new(),
            steps: BTreeMap::new(),
            tool_invocations: BTreeMap::new(),
            tool_results: BTreeMap::new(),
            interruptions: BTreeMap::new(),
            artifacts: BTreeMap::new(),
        }
    }

    pub fn start_run(&mut self, run: KernelRun, event_id: impl Into<String>) {
        self.session.status = KernelSessionStatus::Active;
        self.session.current_run_id = Some(run.run_id.clone());
        self.session.updated_at = run.updated_at.clone();
        self.core.bind_run(run.run_id.clone());
        self.runs.insert(run.run_id.clone(), run.clone());
        self.event_log.append_with_context(KernelEvent {
            event_id: event_id.into(),
            sequence: 0,
            occurred_at: run.started_at.clone(),
            session_id: self.session.session_id.clone(),
            run_id: Some(run.run_id.clone()),
            step_id: None,
            tool_invocation_id: None,
            interrupt_id: None,
            actor_kind: Some("runtime".to_string()),
            surface_kind: Some(self.session.surface_kind.clone()),
            summary: Some("run created".to_string()),
            payload: KernelEventPayload::RunCreated { run },
        });
    }

    pub fn start_step(&mut self, step: RunStep, event_id: impl Into<String>) {
        if let Some(run) = self.runs.get_mut(&step.run_id) {
            run.active_step_id = Some(step.step_id.clone());
            run.step_count = run.step_count.max(step.index);
            run.updated_at = step.updated_at.clone();
        }
        self.core.start_step(step.step_id.clone());
        self.steps.insert(step.step_id.clone(), step.clone());
        self.event_log.append_with_context(KernelEvent {
            event_id: event_id.into(),
            sequence: 0,
            occurred_at: step.started_at.clone(),
            session_id: self.session.session_id.clone(),
            run_id: Some(step.run_id.clone()),
            step_id: Some(step.step_id.clone()),
            tool_invocation_id: None,
            interrupt_id: None,
            actor_kind: Some("runtime".to_string()),
            surface_kind: Some(self.session.surface_kind.clone()),
            summary: step.summary.clone(),
            payload: KernelEventPayload::StepStarted { step },
        });
    }

    pub fn record_model_output(
        &mut self,
        step_id: &str,
        occurred_at: impl Into<String>,
        event_id: impl Into<String>,
        summary: Option<String>,
    ) {
        let occurred_at = occurred_at.into();
        if let Some(step) = self.steps.get_mut(step_id) {
            step.updated_at = occurred_at.clone();
            step.summary = summary.clone().or_else(|| step.summary.clone());
        }
        self.event_log.append_with_context(KernelEvent {
            event_id: event_id.into(),
            sequence: 0,
            occurred_at,
            session_id: self.session.session_id.clone(),
            run_id: self.steps.get(step_id).map(|step| step.run_id.clone()),
            step_id: Some(step_id.to_string()),
            tool_invocation_id: None,
            interrupt_id: None,
            actor_kind: Some("model".to_string()),
            surface_kind: Some(self.session.surface_kind.clone()),
            summary: summary.clone(),
            payload: KernelEventPayload::StepModelOutputRecorded {
                step_id: step_id.to_string(),
                summary,
            },
        });
    }

    pub fn record_tool_invocation(
        &mut self,
        invocation: KernelToolInvocation,
        event_id: impl Into<String>,
    ) {
        if let Some(run) = self.runs.get_mut(&invocation.run_id) {
            run.updated_at = invocation.updated_at.clone();
        }
        self.tool_invocations
            .insert(invocation.tool_invocation_id.clone(), invocation.clone());
        self.event_log.append_with_context(KernelEvent {
            event_id: event_id.into(),
            sequence: 0,
            occurred_at: invocation.started_at.clone(),
            session_id: self.session.session_id.clone(),
            run_id: Some(invocation.run_id.clone()),
            step_id: Some(invocation.step_id.clone()),
            tool_invocation_id: Some(invocation.tool_invocation_id.clone()),
            interrupt_id: None,
            actor_kind: Some("tool".to_string()),
            surface_kind: Some(self.session.surface_kind.clone()),
            summary: invocation.input_summary.clone(),
            payload: KernelEventPayload::ToolInvocationCreated { invocation },
        });
    }

    pub fn mark_tool_execution_started(
        &mut self,
        invocation_id: &str,
        occurred_at: impl Into<String>,
        event_id: impl Into<String>,
    ) {
        let occurred_at = occurred_at.into();
        let mut run_id = None;
        let mut step_id = None;
        if let Some(invocation) = self.tool_invocations.get_mut(invocation_id) {
            invocation.status = KernelToolInvocationStatus::Executing;
            invocation.updated_at = occurred_at.clone();
            run_id = Some(invocation.run_id.clone());
            step_id = Some(invocation.step_id.clone());
        }
        self.event_log.append_with_context(KernelEvent {
            event_id: event_id.into(),
            sequence: 0,
            occurred_at,
            session_id: self.session.session_id.clone(),
            run_id,
            step_id,
            tool_invocation_id: Some(invocation_id.to_string()),
            interrupt_id: None,
            actor_kind: Some("tool".to_string()),
            surface_kind: Some(self.session.surface_kind.clone()),
            summary: Some("tool execution started".to_string()),
            payload: KernelEventPayload::ToolExecutionStarted {
                invocation_id: invocation_id.to_string(),
            },
        });
    }

    pub fn mark_tool_execution_finished(
        &mut self,
        invocation_id: &str,
        occurred_at: impl Into<String>,
        event_id: impl Into<String>,
        status: KernelToolInvocationStatus,
    ) {
        let occurred_at = occurred_at.into();
        let mut run_id = None;
        let mut step_id = None;
        if let Some(invocation) = self.tool_invocations.get_mut(invocation_id) {
            invocation.status = status.clone();
            invocation.updated_at = occurred_at.clone();
            run_id = Some(invocation.run_id.clone());
            step_id = Some(invocation.step_id.clone());
        }
        self.event_log.append_with_context(KernelEvent {
            event_id: event_id.into(),
            sequence: 0,
            occurred_at,
            session_id: self.session.session_id.clone(),
            run_id,
            step_id,
            tool_invocation_id: Some(invocation_id.to_string()),
            interrupt_id: None,
            actor_kind: Some("tool".to_string()),
            surface_kind: Some(self.session.surface_kind.clone()),
            summary: Some("tool execution finished".to_string()),
            payload: KernelEventPayload::ToolExecutionFinished {
                invocation_id: invocation_id.to_string(),
                status,
            },
        });
    }

    pub fn record_tool_result(&mut self, result: KernelToolResult, event_id: impl Into<String>) {
        if let Some(run) = self.runs.get_mut(&result.run_id) {
            run.updated_at = result.created_at.clone();
        }
        self.tool_results
            .insert(result.tool_result_id.clone(), result.clone());
        self.event_log.append_with_context(KernelEvent {
            event_id: event_id.into(),
            sequence: 0,
            occurred_at: result.created_at.clone(),
            session_id: self.session.session_id.clone(),
            run_id: Some(result.run_id.clone()),
            step_id: None,
            tool_invocation_id: Some(result.tool_invocation_id.clone()),
            interrupt_id: None,
            actor_kind: Some("tool".to_string()),
            surface_kind: Some(self.session.surface_kind.clone()),
            summary: result.error_summary.clone(),
            payload: KernelEventPayload::ToolResultRecorded { result },
        });
    }

    pub fn finish_step_commit(
        &mut self,
        step_id: &str,
        occurred_at: impl Into<String>,
        event_id: impl Into<String>,
    ) {
        let occurred_at = occurred_at.into();
        let run_id = self.steps.get(step_id).map(|step| step.run_id.clone());
        if let Some(step) = self.steps.get_mut(step_id) {
            step.updated_at = occurred_at.clone();
        }
        self.event_log.append_with_context(KernelEvent {
            event_id: event_id.into(),
            sequence: 0,
            occurred_at,
            session_id: self.session.session_id.clone(),
            run_id,
            step_id: Some(step_id.to_string()),
            tool_invocation_id: None,
            interrupt_id: None,
            actor_kind: Some("runtime".to_string()),
            surface_kind: Some(self.session.surface_kind.clone()),
            summary: Some("step commit finished".to_string()),
            payload: KernelEventPayload::StepCommitFinished {
                step_id: step_id.to_string(),
            },
        });
    }

    pub fn continue_step(
        &mut self,
        step_id: &str,
        occurred_at: impl Into<String>,
        event_id: impl Into<String>,
        summary: Option<String>,
    ) {
        let occurred_at = occurred_at.into();
        let run_id = self.steps.get(step_id).map(|step| step.run_id.clone());
        if let Some(step) = self.steps.get_mut(step_id) {
            step.updated_at = occurred_at.clone();
            step.outcome = RunStepOutcome::Continued;
            step.summary = summary.clone().or_else(|| step.summary.clone());
        }
        self.event_log.append_with_context(KernelEvent {
            event_id: event_id.into(),
            sequence: 0,
            occurred_at,
            session_id: self.session.session_id.clone(),
            run_id,
            step_id: Some(step_id.to_string()),
            tool_invocation_id: None,
            interrupt_id: None,
            actor_kind: Some("runtime".to_string()),
            surface_kind: Some(self.session.surface_kind.clone()),
            summary: summary.clone(),
            payload: KernelEventPayload::StepContinue {
                step_id: step_id.to_string(),
            },
        });
    }

    pub fn finalize_step(
        &mut self,
        step_id: &str,
        occurred_at: impl Into<String>,
        event_id: impl Into<String>,
        outcome: RunStepOutcome,
        summary: Option<String>,
    ) {
        let occurred_at = occurred_at.into();
        let run_id = self.steps.get(step_id).map(|step| step.run_id.clone());
        if let Some(step) = self.steps.get_mut(step_id) {
            step.updated_at = occurred_at.clone();
            step.outcome = outcome;
            step.summary = summary.clone().or_else(|| step.summary.clone());
        }
        self.core.clear_step();
        self.event_log.append_with_context(KernelEvent {
            event_id: event_id.into(),
            sequence: 0,
            occurred_at,
            session_id: self.session.session_id.clone(),
            run_id,
            step_id: Some(step_id.to_string()),
            tool_invocation_id: None,
            interrupt_id: None,
            actor_kind: Some("runtime".to_string()),
            surface_kind: Some(self.session.surface_kind.clone()),
            summary: summary.clone(),
            payload: KernelEventPayload::StepFinalize {
                step_id: step_id.to_string(),
            },
        });
    }

    pub fn open_interruption(
        &mut self,
        interruption: RunInterruption,
        event_id: impl Into<String>,
    ) {
        if let Some(run) = self.runs.get_mut(&interruption.run_id) {
            run.status = KernelRunStatus::Interrupted;
            run.interrupt_id = Some(interruption.interrupt_id.clone());
        }
        self.session.status = KernelSessionStatus::Interrupted;
        self.interruptions
            .insert(interruption.interrupt_id.clone(), interruption.clone());
        self.event_log.append_with_context(KernelEvent {
            event_id: event_id.into(),
            sequence: 0,
            occurred_at: interruption.created_at.clone(),
            session_id: self.session.session_id.clone(),
            run_id: Some(interruption.run_id.clone()),
            step_id: None,
            tool_invocation_id: None,
            interrupt_id: Some(interruption.interrupt_id.clone()),
            actor_kind: Some("runtime".to_string()),
            surface_kind: Some(self.session.surface_kind.clone()),
            summary: interruption.requested_action_summary.clone(),
            payload: KernelEventPayload::InterruptOpened { interruption },
        });
    }

    pub fn record_artifact(&mut self, artifact: ArtifactRecord, event_id: impl Into<String>) {
        self.artifacts
            .insert(artifact.artifact_id.clone(), artifact.clone());
        self.event_log.append_with_context(KernelEvent {
            event_id: event_id.into(),
            sequence: 0,
            occurred_at: artifact.created_at.clone(),
            session_id: self.session.session_id.clone(),
            run_id: Some(artifact.run_id.clone()),
            step_id: None,
            tool_invocation_id: artifact.source_tool_invocation_id.clone(),
            interrupt_id: None,
            actor_kind: Some("artifact".to_string()),
            surface_kind: Some(self.session.surface_kind.clone()),
            summary: artifact.preview_summary.clone(),
            payload: KernelEventPayload::ArtifactCreated { artifact },
        });
    }

    pub fn resolve_interruption(
        &mut self,
        interrupt_id: &str,
        occurred_at: impl Into<String>,
        event_id: impl Into<String>,
        accepted: bool,
    ) {
        let occurred_at = occurred_at.into();
        let mut interrupted_run_id: Option<String> = None;
        if let Some(interruption) = self.interruptions.get_mut(interrupt_id) {
            interruption.status = if accepted {
                RunInterruptStatus::Resolved
            } else {
                RunInterruptStatus::Rejected
            };
            interrupted_run_id = Some(interruption.run_id.clone());

            if let Some(run) = self.runs.get_mut(&interruption.run_id) {
                run.updated_at = occurred_at.clone();
                run.status = if accepted {
                    KernelRunStatus::Running
                } else {
                    KernelRunStatus::Failed
                };
                run.interrupt_id = None;
                if !accepted {
                    run.stop_reason = Some("interruption_rejected".to_string());
                    run.active_step_id = None;
                }
            }
        }
        self.session.updated_at = occurred_at.clone();
        self.session.status = if accepted {
            KernelSessionStatus::Active
        } else {
            KernelSessionStatus::Idle
        };
        if accepted {
            self.session.current_run_id = interrupted_run_id.clone();
        } else {
            self.session.current_run_id = None;
            self.core.clear_run();
        }
        self.event_log.append_with_context(KernelEvent {
            event_id: event_id.into(),
            sequence: 0,
            occurred_at,
            session_id: self.session.session_id.clone(),
            run_id: interrupted_run_id,
            step_id: None,
            tool_invocation_id: None,
            interrupt_id: Some(interrupt_id.to_string()),
            actor_kind: Some("approval_host".to_string()),
            surface_kind: Some(self.session.surface_kind.clone()),
            summary: Some(if accepted {
                "interruption resolved".to_string()
            } else {
                "interruption rejected".to_string()
            }),
            payload: if accepted {
                KernelEventPayload::InterruptResolved {
                    interrupt_id: interrupt_id.to_string(),
                }
            } else {
                KernelEventPayload::InterruptRejected {
                    interrupt_id: interrupt_id.to_string(),
                }
            },
        });
    }

    pub fn complete_run(
        &mut self,
        run_id: &str,
        occurred_at: impl Into<String>,
        event_id: impl Into<String>,
        final_output_ref: Option<String>,
    ) {
        let occurred_at = occurred_at.into();
        if let Some(run) = self.runs.get_mut(run_id) {
            run.status = KernelRunStatus::Completed;
            run.updated_at = occurred_at.clone();
            run.final_output_ref = final_output_ref.clone();
            run.stop_reason = Some("finalized".to_string());
            run.active_step_id = None;
        }
        self.session.status = KernelSessionStatus::Idle;
        self.session.current_run_id = None;
        self.session.updated_at = occurred_at.clone();
        self.core.clear_run();
        self.event_log.append_with_context(KernelEvent {
            event_id: event_id.into(),
            sequence: 0,
            occurred_at,
            session_id: self.session.session_id.clone(),
            run_id: Some(run_id.to_string()),
            step_id: None,
            tool_invocation_id: None,
            interrupt_id: None,
            actor_kind: Some("runtime".to_string()),
            surface_kind: Some(self.session.surface_kind.clone()),
            summary: Some("run completed".to_string()),
            payload: KernelEventPayload::RunCompleted {
                run_id: run_id.to_string(),
                final_output_ref,
            },
        });
    }

    pub fn fail_run(
        &mut self,
        run_id: &str,
        occurred_at: impl Into<String>,
        event_id: impl Into<String>,
        error_summary: Option<String>,
    ) {
        let occurred_at = occurred_at.into();
        if let Some(run) = self.runs.get_mut(run_id) {
            run.status = KernelRunStatus::Failed;
            run.updated_at = occurred_at.clone();
            run.error_summary = error_summary.clone();
            run.stop_reason = Some("failed".to_string());
            run.active_step_id = None;
        }
        self.session.status = KernelSessionStatus::Idle;
        self.session.current_run_id = None;
        self.session.updated_at = occurred_at.clone();
        self.core.clear_run();
        self.event_log.append_with_context(KernelEvent {
            event_id: event_id.into(),
            sequence: 0,
            occurred_at,
            session_id: self.session.session_id.clone(),
            run_id: Some(run_id.to_string()),
            step_id: None,
            tool_invocation_id: None,
            interrupt_id: None,
            actor_kind: Some("runtime".to_string()),
            surface_kind: Some(self.session.surface_kind.clone()),
            summary: error_summary.clone(),
            payload: KernelEventPayload::RunFailed {
                run_id: run_id.to_string(),
                error_summary,
            },
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_session() -> KernelSession {
        KernelSession {
            session_id: "session_01".to_string(),
            surface_kind: KernelSurfaceKind::DesktopWorkspaceChat,
            created_at: "now".to_string(),
            updated_at: "now".to_string(),
            active_agent_id: "gee".to_string(),
            status: KernelSessionStatus::Idle,
            current_run_id: None,
            history_cursor: 0,
            cwd: Some("/tmp/demo".to_string()),
            workspace_ref: None,
            runtime_home_ref: None,
            continuation_strategy: Some("session".to_string()),
            summary_ref: None,
        }
    }

    #[test]
    fn kernel_event_log_assigns_monotonic_sequences() {
        let mut log = KernelEventLog::default();
        log.append(
            "event_01",
            "now",
            "session_01",
            KernelEventPayload::SessionResumed {
                session_id: "session_01".to_string(),
            },
        );
        log.append(
            "event_02",
            "later",
            "session_01",
            KernelEventPayload::RunStarted {
                run_id: "run_01".to_string(),
            },
        );

        assert_eq!(log.events()[0].sequence, 1);
        assert_eq!(log.events()[1].sequence, 2);
        assert_eq!(log.next_sequence(), 3);
    }

    #[test]
    fn runtime_core_drains_steering_and_follow_up_queues_independently() {
        let mut core = AgentRuntimeCore::new("session_01", 12);
        core.steer(QueuedRuntimeMessage {
            message_id: "msg_steer".to_string(),
            content: "look at the docker output".to_string(),
            created_at: "now".to_string(),
            source_kind: Some("user".to_string()),
        });
        core.follow_up(QueuedRuntimeMessage {
            message_id: "msg_follow".to_string(),
            content: "and summarize what can be started".to_string(),
            created_at: "later".to_string(),
            source_kind: Some("runtime".to_string()),
        });

        let steering = core.drain_steering();
        let follow_up = core.drain_follow_up();

        assert_eq!(steering.len(), 1);
        assert_eq!(follow_up.len(), 1);
        assert!(core.steering_queue.is_empty());
        assert!(core.follow_up_queue.is_empty());
    }

    #[test]
    fn agent_session_runtime_tracks_run_interrupt_resume_and_complete_lineage() {
        let mut runtime = AgentSessionRuntime::new(sample_session(), 8);

        runtime.start_run(
            KernelRun {
                run_id: "run_01".to_string(),
                session_id: "session_01".to_string(),
                origin_message_id: "msg_01".to_string(),
                status: KernelRunStatus::Running,
                started_at: "t0".to_string(),
                updated_at: "t0".to_string(),
                step_count: 0,
                max_steps: 8,
                run_kind: Some("conversation".to_string()),
                active_step_id: None,
                parent_run_id: None,
                interrupt_id: None,
                stop_reason: None,
                final_output_ref: None,
                error_summary: None,
            },
            "event_run_created",
        );

        runtime.start_step(
            RunStep {
                step_id: "step_01".to_string(),
                run_id: "run_01".to_string(),
                index: 1,
                phase: RunStepPhase::Dispatch,
                started_at: "t1".to_string(),
                updated_at: "t1".to_string(),
                outcome: RunStepOutcome::Interrupted,
                model_decision_ref: Some("decision_ref".to_string()),
                dispatch_target: Some("terminal.exec".to_string()),
                tool_invocation_id: None,
                interrupt_id: None,
                summary: Some("about to execute a script in the requested directory".to_string()),
            },
            "event_step_started",
        );

        runtime.record_tool_invocation(
            KernelToolInvocation {
                tool_invocation_id: "tool_01".to_string(),
                run_id: "run_01".to_string(),
                step_id: "step_01".to_string(),
                capability_family: "terminal".to_string(),
                tool_name: "terminal.exec".to_string(),
                status: KernelToolInvocationStatus::Admitted,
                started_at: "t1".to_string(),
                updated_at: "t1".to_string(),
                input_summary: Some("cd /tmp/demo && sh ./run.sh".to_string()),
                approval_policy: Some("execute_requires_approval".to_string()),
                execution_backend: Some("local_shell".to_string()),
                cwd: Some("/tmp/demo".to_string()),
                command_preview: Some("sh ./run.sh".to_string()),
                correlation_id: Some("corr_01".to_string()),
            },
            "event_tool_created",
        );

        runtime.open_interruption(
            RunInterruption {
                interrupt_id: "interrupt_01".to_string(),
                run_id: "run_01".to_string(),
                reason: RunInterruptReason::ApprovalRequired,
                status: RunInterruptStatus::Open,
                created_at: "t2".to_string(),
                approval_request_ref: Some("approval_01".to_string()),
                requested_action_summary: Some("execute sh ./run.sh in /tmp/demo".to_string()),
                resume_token: Some("resume_01".to_string()),
                policy_tags: vec!["shell.execute".to_string()],
                default_resolution: Some("reject".to_string()),
            },
            "event_interrupt_opened",
        );

        runtime.resolve_interruption("interrupt_01", "t3", "event_interrupt_resolved", true);

        runtime.record_tool_result(
            KernelToolResult {
                tool_result_id: "result_01".to_string(),
                tool_invocation_id: "tool_01".to_string(),
                run_id: "run_01".to_string(),
                status: KernelToolResultStatus::Success,
                created_at: "t4".to_string(),
                content_ref: Some("artifact://stdout/01".to_string()),
                structured_payload: Some(serde_json::json!({ "exit_code": 0 })),
                error_summary: None,
                artifact_ids: vec!["artifact_01".to_string()],
                exit_code: Some(0),
            },
            "event_tool_result",
        );

        runtime.complete_run(
            "run_01",
            "t5",
            "event_run_completed",
            Some("assistant://final-output/01".to_string()),
        );

        assert_eq!(runtime.session.status, KernelSessionStatus::Idle);
        assert!(runtime.session.current_run_id.is_none());
        assert!(runtime.core.active_run_id.is_none());
        assert_eq!(runtime.runs["run_01"].status, KernelRunStatus::Completed);
        assert_eq!(
            runtime.interruptions["interrupt_01"].status,
            RunInterruptStatus::Resolved
        );
        assert_eq!(runtime.event_log.events().len(), 7);
        assert!(matches!(
            runtime.event_log.events()[0].payload,
            KernelEventPayload::RunCreated { .. }
        ));
        assert!(matches!(
            runtime.event_log.events()[4].payload,
            KernelEventPayload::InterruptResolved { .. }
        ));
        assert!(matches!(
            runtime.event_log.events()[6].payload,
            KernelEventPayload::RunCompleted { .. }
        ));
    }

    #[test]
    fn rejecting_an_interruption_fails_the_run_and_returns_session_to_idle() {
        let mut runtime = AgentSessionRuntime::new(sample_session(), 8);

        runtime.start_run(
            KernelRun {
                run_id: "run_reject".to_string(),
                session_id: "session_01".to_string(),
                origin_message_id: "msg_01".to_string(),
                status: KernelRunStatus::Running,
                started_at: "t0".to_string(),
                updated_at: "t0".to_string(),
                step_count: 0,
                max_steps: 8,
                run_kind: None,
                active_step_id: None,
                parent_run_id: None,
                interrupt_id: None,
                stop_reason: None,
                final_output_ref: None,
                error_summary: None,
            },
            "event_run_created",
        );

        runtime.open_interruption(
            RunInterruption {
                interrupt_id: "interrupt_reject".to_string(),
                run_id: "run_reject".to_string(),
                reason: RunInterruptReason::ApprovalRequired,
                status: RunInterruptStatus::Open,
                created_at: "t1".to_string(),
                approval_request_ref: Some("approval_reject".to_string()),
                requested_action_summary: Some("execute destructive script".to_string()),
                resume_token: Some("resume_reject".to_string()),
                policy_tags: vec!["shell.execute".to_string()],
                default_resolution: Some("reject".to_string()),
            },
            "event_interrupt_opened",
        );

        runtime.resolve_interruption("interrupt_reject", "t2", "event_interrupt_rejected", false);

        assert_eq!(runtime.session.status, KernelSessionStatus::Idle);
        assert!(runtime.session.current_run_id.is_none());
        assert!(runtime.core.active_run_id.is_none());
        assert_eq!(runtime.runs["run_reject"].status, KernelRunStatus::Failed);
        assert_eq!(
            runtime.runs["run_reject"].stop_reason.as_deref(),
            Some("interruption_rejected")
        );
        assert_eq!(
            runtime.interruptions["interrupt_reject"].status,
            RunInterruptStatus::Rejected
        );
        assert!(matches!(
            runtime
                .event_log
                .events()
                .last()
                .expect("one resolution event")
                .payload,
            KernelEventPayload::InterruptRejected { .. }
        ));
    }

    #[test]
    fn agent_session_runtime_records_step_and_tool_lineage() {
        let mut runtime = AgentSessionRuntime::new(sample_session(), 6);

        runtime.start_run(
            KernelRun {
                run_id: "run_terminal".to_string(),
                session_id: "session_01".to_string(),
                origin_message_id: "msg_user_01".to_string(),
                status: KernelRunStatus::Running,
                started_at: "t0".to_string(),
                updated_at: "t0".to_string(),
                step_count: 0,
                max_steps: 6,
                run_kind: Some("terminal".to_string()),
                active_step_id: None,
                parent_run_id: None,
                interrupt_id: None,
                stop_reason: None,
                final_output_ref: None,
                error_summary: None,
            },
            "evt_run_created",
        );
        runtime.start_step(
            RunStep {
                step_id: "step_terminal_01".to_string(),
                run_id: "run_terminal".to_string(),
                index: 1,
                phase: RunStepPhase::Dispatch,
                started_at: "t1".to_string(),
                updated_at: "t1".to_string(),
                outcome: RunStepOutcome::Continued,
                model_decision_ref: None,
                dispatch_target: Some("terminal".to_string()),
                tool_invocation_id: None,
                interrupt_id: None,
                summary: Some("dispatch terminal".to_string()),
            },
            "evt_step_started",
        );
        runtime.record_model_output(
            "step_terminal_01",
            "t1.1",
            "evt_model_output",
            Some("check docker containers".to_string()),
        );
        runtime.record_tool_invocation(
            KernelToolInvocation {
                tool_invocation_id: "toolinv_terminal_01".to_string(),
                run_id: "run_terminal".to_string(),
                step_id: "step_terminal_01".to_string(),
                capability_family: "terminal".to_string(),
                tool_name: "shell.run".to_string(),
                status: KernelToolInvocationStatus::Admitted,
                started_at: "t1.2".to_string(),
                updated_at: "t1.2".to_string(),
                input_summary: Some("docker ps -a".to_string()),
                approval_policy: Some("runtime_guarded".to_string()),
                execution_backend: Some("local_shell".to_string()),
                cwd: Some("/tmp/demo".to_string()),
                command_preview: Some("docker ps -a".to_string()),
                correlation_id: None,
            },
            "evt_tool_created",
        );
        runtime.mark_tool_execution_started("toolinv_terminal_01", "t1.3", "evt_tool_started");
        runtime.mark_tool_execution_finished(
            "toolinv_terminal_01",
            "t1.4",
            "evt_tool_finished",
            KernelToolInvocationStatus::Completed,
        );
        runtime.record_tool_result(
            KernelToolResult {
                tool_result_id: "toolres_terminal_01".to_string(),
                tool_invocation_id: "toolinv_terminal_01".to_string(),
                run_id: "run_terminal".to_string(),
                status: KernelToolResultStatus::Success,
                created_at: "t1.5".to_string(),
                content_ref: Some("artifact://terminal-output".to_string()),
                structured_payload: None,
                error_summary: None,
                artifact_ids: vec!["artifact_terminal_01".to_string()],
                exit_code: Some(0),
            },
            "evt_tool_result",
        );
        runtime.finish_step_commit("step_terminal_01", "t1.6", "evt_step_commit");
        runtime.finalize_step(
            "step_terminal_01",
            "t1.7",
            "evt_step_finalize",
            RunStepOutcome::Finalized,
            Some("terminal inspection converged".to_string()),
        );
        runtime.complete_run(
            "run_terminal",
            "t2",
            "evt_run_complete",
            Some("artifact://assistant-reply".to_string()),
        );

        assert_eq!(
            runtime
                .tool_invocations
                .get("toolinv_terminal_01")
                .expect("tool invocation should exist")
                .status,
            KernelToolInvocationStatus::Completed
        );
        assert_eq!(
            runtime
                .steps
                .get("step_terminal_01")
                .expect("step should exist")
                .outcome,
            RunStepOutcome::Finalized
        );
        assert_eq!(
            runtime
                .runs
                .get("run_terminal")
                .expect("run should exist")
                .status,
            KernelRunStatus::Completed
        );
        assert_eq!(runtime.session.status, KernelSessionStatus::Idle);
        assert_eq!(runtime.event_log.events().len(), 10);
    }
}
