use task_engine::{ImportanceLevel, TaskRun, TaskStatus};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PetMode {
    Hidden,
    Ambient,
    Report,
    Review,
    Concern,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MenuBarAssistantState {
    Idle,
    Working,
    WaitingReview,
    WaitingInput,
    Degraded,
}

pub struct ProjectionPolicy;

impl ProjectionPolicy {
    pub fn pet_mode_for_task(task: &TaskRun) -> PetMode {
        if task.status == TaskStatus::WaitingReview
            || task.importance_level == ImportanceLevel::Review
        {
            return PetMode::Review;
        }

        if task.status == TaskStatus::Failed {
            return PetMode::Concern;
        }

        match task.importance_level {
            ImportanceLevel::Important => PetMode::Report,
            ImportanceLevel::Passive => PetMode::Ambient,
            ImportanceLevel::Background => PetMode::Hidden,
            ImportanceLevel::Review => PetMode::Review,
        }
    }

    pub fn menu_bar_state_for_task(task: &TaskRun) -> MenuBarAssistantState {
        match task.status {
            TaskStatus::WaitingReview => MenuBarAssistantState::WaitingReview,
            TaskStatus::WaitingInput => MenuBarAssistantState::WaitingInput,
            TaskStatus::Failed => MenuBarAssistantState::Degraded,
            TaskStatus::Queued | TaskStatus::Running => MenuBarAssistantState::Working,
            TaskStatus::Completed | TaskStatus::Cancelled => MenuBarAssistantState::Idle,
        }
    }
}
