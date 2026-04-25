use experience_registry::{
    AgentSkinManifest, ExperienceRegistry, InstallState, InstalledAppManifest, ModuleDisplayMode,
};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WorkbenchSection {
    Home,
    Chat,
    Tasks,
    Automations,
    Apps,
    Settings,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WorkspaceInstallState {
    Installed,
}

impl From<InstallState> for WorkspaceInstallState {
    fn from(value: InstallState) -> Self {
        match value {
            InstallState::Installed => Self::Installed,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct InstalledAppSummary {
    pub app_id: String,
    pub display_name: String,
    pub install_state: WorkspaceInstallState,
    #[serde(default)]
    pub display_mode: ModuleDisplayMode,
}

impl From<&InstalledAppManifest> for InstalledAppSummary {
    fn from(manifest: &InstalledAppManifest) -> Self {
        Self {
            app_id: manifest.app_id.clone(),
            display_name: manifest.display_name.clone(),
            install_state: manifest.install_state.into(),
            display_mode: manifest.display_mode,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AgentSkinSummary {
    pub skin_id: String,
    pub display_name: String,
}

impl From<&AgentSkinManifest> for AgentSkinSummary {
    fn from(manifest: &AgentSkinManifest) -> Self {
        Self {
            skin_id: manifest.skin_id.clone(),
            display_name: manifest.display_name.clone(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkspaceSnapshot {
    pub active_section: WorkbenchSection,
    pub sections: Vec<WorkbenchSection>,
    pub apps: Vec<InstalledAppSummary>,
    pub agent_skins: Vec<AgentSkinSummary>,
}

#[derive(Debug, Clone)]
pub struct WorkspaceRuntime {
    registry: ExperienceRegistry,
}

impl WorkspaceRuntime {
    pub fn new(registry: ExperienceRegistry) -> Self {
        Self { registry }
    }

    pub fn snapshot(&self) -> WorkspaceSnapshot {
        WorkspaceSnapshot {
            active_section: WorkbenchSection::Home,
            sections: vec![
                WorkbenchSection::Home,
                WorkbenchSection::Chat,
                WorkbenchSection::Tasks,
                WorkbenchSection::Automations,
                WorkbenchSection::Apps,
                WorkbenchSection::Settings,
            ],
            apps: self
                .registry
                .apps()
                .iter()
                .map(InstalledAppSummary::from)
                .collect(),
            agent_skins: self
                .registry
                .skins()
                .iter()
                .map(AgentSkinSummary::from)
                .collect(),
        }
    }
}
