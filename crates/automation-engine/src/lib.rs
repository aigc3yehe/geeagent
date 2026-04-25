use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AutomationStatus {
    Active,
    Paused,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TriggerKind {
    Schedule,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ScheduleCadence {
    Once,
    Daily,
    Weekdays,
    Weekly,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LockPolicy {
    SkipIfRunning,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AutomationDefinition {
    pub automation_id: String,
    pub name: String,
    pub status: AutomationStatus,
    pub trigger_kind: TriggerKind,
    pub goal_prompt: String,
    pub lock_policy: LockPolicy,
    #[serde(default = "default_schedule_cadence")]
    pub cadence: ScheduleCadence,
    #[serde(default = "default_time_of_day")]
    pub time_of_day: String,
    #[serde(default)]
    pub schedule_hint: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum OverlapResolution {
    StartedNormally,
    SkippedDueToActiveRun,
}

impl OverlapResolution {
    pub fn from_active_run(has_active_run: bool) -> Self {
        if has_active_run {
            Self::SkippedDueToActiveRun
        } else {
            Self::StartedNormally
        }
    }
}

fn default_schedule_cadence() -> ScheduleCadence {
    ScheduleCadence::Daily
}

fn default_time_of_day() -> String {
    "09:00".to_string()
}
