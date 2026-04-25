use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConversationStatus {
    Active,
    Archived,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Conversation {
    pub conversation_id: String,
    pub title: String,
    pub status: ConversationStatus,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ExecutionSurface {
    DesktopWorkspaceChat,
    DesktopQuickInput,
    CliWorkspaceChat,
    CliQuickInput,
    Automation,
    BackgroundAgent,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ExecutionMode {
    Interactive,
    Background,
    Scheduled,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SessionPersistencePolicy {
    Persisted,
    Ephemeral,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ExecutionSession {
    pub session_id: String,
    pub conversation_id: Option<String>,
    pub surface: ExecutionSurface,
    pub mode: ExecutionMode,
    pub project_path: Option<String>,
    pub parent_session_id: Option<String>,
    pub persistence_policy: SessionPersistencePolicy,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ArtifactRef {
    pub artifact_id: String,
    #[serde(rename = "type")]
    pub artifact_type: String,
    pub title: String,
    pub payload_ref: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub inline_preview_summary: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ToolInvocationStatus {
    Queued,
    Running,
    Succeeded,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ToolInvocation {
    pub invocation_id: String,
    pub session_id: String,
    pub originating_message_id: String,
    pub tool_name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub input_summary: Option<String>,
    pub status: ToolInvocationStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub approval_request_id: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum TranscriptEventPayload {
    UserMessage {
        message_id: String,
        content: String,
    },
    AssistantMessage {
        message_id: String,
        content: String,
    },
    ToolInvocation {
        invocation: ToolInvocation,
    },
    ToolResult {
        invocation_id: String,
        status: ToolInvocationStatus,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        summary: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        error: Option<String>,
        #[serde(default)]
        artifacts: Vec<ArtifactRef>,
    },
    SessionStateChanged {
        summary: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TranscriptEvent {
    pub event_id: String,
    pub session_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent_event_id: Option<String>,
    pub created_at: String,
    pub payload: TranscriptEventPayload,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TaskType {
    Conversation,
    AbilityRun,
    ScheduledRun,
    ApprovalWaiting,
    BackgroundAgent,
    DigestRun,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TaskStatus {
    Queued,
    Running,
    WaitingReview,
    WaitingInput,
    Completed,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TaskStage {
    Intent,
    Planning,
    Dispatching,
    Running,
    Digesting,
    ReviewPending,
    Reporting,
    Finalized,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ImportanceLevel {
    Background,
    Passive,
    Important,
    Review,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TaskRun {
    pub task_id: String,
    pub conversation_id: Option<String>,
    pub task_type: TaskType,
    pub title: String,
    pub status: TaskStatus,
    pub current_stage: TaskStage,
    pub summary: String,
    pub progress_percent: Option<u8>,
    pub importance_level: ImportanceLevel,
    pub approval_request_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ApprovalStatus {
    Open,
    Approved,
    Rejected,
    Expired,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ApprovalRequest {
    pub approval_request_id: String,
    pub task_id: String,
    pub action_title: String,
    pub reason: String,
    pub risk_tags: Vec<String>,
    pub review_required: bool,
    pub status: ApprovalStatus,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProductEvent {
    pub event_id: String,
    pub event_type: String,
    pub aggregate_kind: String,
    pub aggregate_id: String,
    pub task_id: Option<String>,
    pub conversation_id: Option<String>,
    pub importance_level: Option<ImportanceLevel>,
    pub summary: Option<String>,
    pub payload: serde_json::Value,
}

#[cfg(test)]
mod tests {
    use super::{
        ArtifactRef, ExecutionMode, ExecutionSession, ExecutionSurface, SessionPersistencePolicy,
        ToolInvocation, ToolInvocationStatus, TranscriptEvent, TranscriptEventPayload,
    };

    #[test]
    fn execution_session_serializes_with_snake_case_enums() {
        let session = ExecutionSession {
            session_id: "session_conv_01".to_string(),
            conversation_id: Some("conv_01".to_string()),
            surface: ExecutionSurface::DesktopQuickInput,
            mode: ExecutionMode::Interactive,
            project_path: Some("/tmp/demo".to_string()),
            parent_session_id: None,
            persistence_policy: SessionPersistencePolicy::Persisted,
            created_at: "now".to_string(),
            updated_at: "now".to_string(),
        };

        let value = serde_json::to_value(&session).expect("session should serialize");
        assert_eq!(value["surface"], "desktop_quick_input");
        assert_eq!(value["mode"], "interactive");
        assert_eq!(value["persistence_policy"], "persisted");
    }

    #[test]
    fn transcript_tool_result_round_trips_with_artifact_refs() {
        let event = TranscriptEvent {
            event_id: "event_session_conv_01_03".to_string(),
            session_id: "session_conv_01".to_string(),
            parent_event_id: Some("event_session_conv_01_02".to_string()),
            created_at: "now".to_string(),
            payload: TranscriptEventPayload::ToolResult {
                invocation_id: "toolinv_run_01".to_string(),
                status: ToolInvocationStatus::Succeeded,
                summary: Some("Resolved the local reminder request.".to_string()),
                error: None,
                artifacts: vec![ArtifactRef {
                    artifact_id: "artifact_01".to_string(),
                    artifact_type: "automation_definition".to_string(),
                    title: "Reminder Draft".to_string(),
                    payload_ref: "automation://drafts/01".to_string(),
                    inline_preview_summary: Some("提醒：4 小时后上课".to_string()),
                }],
            },
        };

        let json = serde_json::to_string(&event).expect("event should serialize");
        let restored: TranscriptEvent =
            serde_json::from_str(&json).expect("event should deserialize");
        assert_eq!(restored, event);

        let invocation = ToolInvocation {
            invocation_id: "toolinv_run_01".to_string(),
            session_id: "session_conv_01".to_string(),
            originating_message_id: "msg_user_01".to_string(),
            tool_name: "geeagent.local.reminders.create".to_string(),
            input_summary: Some("明天8点通知我吃药💊".to_string()),
            status: ToolInvocationStatus::Succeeded,
            approval_request_id: None,
            created_at: "now".to_string(),
            updated_at: "now".to_string(),
        };
        let value = serde_json::to_value(invocation).expect("invocation should serialize");
        assert_eq!(value["tool_name"], "geeagent.local.reminders.create");
        assert_eq!(value["input_summary"], "明天8点通知我吃药💊");
        assert_eq!(value["status"], "succeeded");
    }
}
