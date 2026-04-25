use std::{error::Error, fmt};

use experience_registry::ModuleDisplayMode;
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BindingType {
    Http,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EntryBinding {
    pub binding_type: BindingType,
    pub base_url: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CapabilityDefinition {
    pub capability_id: String,
    pub title: String,
    pub description: String,
    pub input_schema: Value,
    pub artifact_types: Vec<String>,
    pub execution_mode: String,
    pub sensitive_actions: Vec<SensitiveAction>,
    pub result_summary_template: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SensitiveActionKind {
    ExternalPublish,
    ExternalStateChange,
    LocalFileWrite,
    LongTermMemoryWrite,
    CredentialUse,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SensitiveAction {
    pub action_id: String,
    pub kind: SensitiveActionKind,
    pub default_review_required: bool,
    pub description: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ModuleRunStatus {
    Queued,
    Running,
    WaitingReview,
    Completed,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ModuleRunStage {
    Preflight,
    Dispatch,
    WaitingUpstream,
    Postprocess,
    ReviewPending,
    Finalized,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ArtifactEnvelope {
    pub artifact_id: String,
    #[serde(rename = "type")]
    pub artifact_type: String,
    pub title: String,
    pub summary: String,
    pub payload_ref: String,
    pub inline_preview: Option<Value>,
    pub domain_tags: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ExecutionContext {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub conversation_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub surface: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub workspace_section: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub active_agent_profile_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub trace_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub project_path: Option<String>,
    #[serde(default)]
    pub requested_host_capabilities: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModuleRun {
    pub module_run_id: String,
    pub task_id: String,
    pub module_id: String,
    pub capability_id: String,
    pub status: ModuleRunStatus,
    pub stage: ModuleRunStage,
    pub attempt_count: u32,
    pub result_summary: Option<String>,
    pub artifacts: Vec<ArtifactEnvelope>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ServiceHealthStatus {
    Healthy,
    Degraded,
    Unhealthy,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HealthSnapshot {
    pub status: ServiceHealthStatus,
    pub service_name: String,
    pub service_version: String,
    pub timestamp: String,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModuleInvokeRequest {
    pub task_id: String,
    pub module_id: String,
    pub capability_id: String,
    pub intent_summary: Option<String>,
    pub input: Value,
    pub requested_artifact_types: Vec<String>,
    pub allow_background: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub execution_context: Option<ExecutionContext>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModuleInvokeResponse {
    pub module_run_id: String,
    pub status: ModuleRunStatus,
    pub summary: String,
    pub result_preview: Option<Value>,
    pub next_poll_hint_ms: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Recoverability {
    pub retry_safe: bool,
    pub resume_supported: bool,
    pub hint: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModuleStatusResponse {
    pub module_run: ModuleRun,
    pub recoverability: Option<Recoverability>,
    pub result_preview: Option<Value>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ModuleRunEventKind {
    Accepted,
    Progress,
    WaitingReview,
    ArtifactProduced,
    Completed,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModuleRunEvent {
    pub event_id: String,
    pub module_run_id: String,
    pub kind: ModuleRunEventKind,
    pub summary: String,
    pub created_at: String,
    #[serde(default)]
    pub artifact_ids: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub result_preview: Option<Value>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModuleCancelRequest {
    pub module_run_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModuleManifest {
    pub module_id: String,
    pub version: String,
    pub display_name: String,
    pub description: String,
    pub owner: String,
    pub entry_binding: EntryBinding,
    pub domains: Vec<String>,
    pub capabilities: Vec<CapabilityDefinition>,
    /// How the host should present the module UI when opened from the
    /// workbench. Defaults to `in_nav` for backwards compatibility.
    #[serde(default)]
    pub display_mode: ModuleDisplayMode,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ValidationError {
    message: String,
}

impl ValidationError {
    fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl fmt::Display for ValidationError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.message)
    }
}

impl Error for ValidationError {}

impl ModuleManifest {
    pub fn validate(&self) -> Result<(), ValidationError> {
        validate_identifier("module_id", &self.module_id)?;

        if self.capabilities.is_empty() {
            return Err(ValidationError::new(
                "capabilities must contain at least one capability",
            ));
        }

        validate_base_url(&self.entry_binding)?;

        for capability in &self.capabilities {
            validate_identifier("capability_id", &capability.capability_id)?;
            validate_execution_mode(&capability.execution_mode)?;

            if capability.artifact_types.is_empty() {
                return Err(ValidationError::new(format!(
                    "capability `{}` must declare at least one artifact type",
                    capability.capability_id
                )));
            }

            for artifact_type in &capability.artifact_types {
                validate_identifier("artifact_type", artifact_type)?;
            }

            for sensitive_action in &capability.sensitive_actions {
                validate_identifier("action_id", &sensitive_action.action_id)?;
            }
        }

        Ok(())
    }
}

fn validate_base_url(binding: &EntryBinding) -> Result<(), ValidationError> {
    match binding.binding_type {
        BindingType::Http => {
            if binding.base_url.starts_with("http://") || binding.base_url.starts_with("https://") {
                Ok(())
            } else {
                Err(ValidationError::new(
                    "entry_binding.base_url must start with http:// or https://",
                ))
            }
        }
    }
}

fn validate_execution_mode(value: &str) -> Result<(), ValidationError> {
    match value {
        "sync" | "async" => Ok(()),
        _ => Err(ValidationError::new(format!(
            "execution_mode `{value}` must be `sync` or `async`"
        ))),
    }
}

fn validate_identifier(field_name: &str, value: &str) -> Result<(), ValidationError> {
    if !value.is_ascii() {
        return Err(ValidationError::new(format!(
            "{field_name} must use ASCII-only characters"
        )));
    }

    if value.is_empty() {
        return Err(ValidationError::new(format!(
            "{field_name} cannot be empty"
        )));
    }

    let allowed = value
        .chars()
        .all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || matches!(ch, '.' | '-' | '_'));

    if !allowed {
        return Err(ValidationError::new(format!(
            "{field_name} must use lowercase English identifier characters"
        )));
    }

    Ok(())
}
