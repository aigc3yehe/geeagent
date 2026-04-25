use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum ModuleDisplayMode {
    /// Shown inside the functional-stage card next to the nav rail (legacy).
    #[default]
    InNav,
    /// Full-window module surface (nav rail hidden), e.g. media library.
    FullCanvas,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum InstallState {
    Installed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct InstalledAppManifest {
    pub app_id: String,
    pub display_name: String,
    pub install_state: InstallState,
    #[serde(default)]
    pub display_mode: ModuleDisplayMode,
}

impl InstalledAppManifest {
    pub fn new(
        app_id: impl Into<String>,
        display_name: impl Into<String>,
        install_state: InstallState,
    ) -> Self {
        Self::with_display_mode(
            app_id,
            display_name,
            install_state,
            ModuleDisplayMode::InNav,
        )
    }

    pub fn with_display_mode(
        app_id: impl Into<String>,
        display_name: impl Into<String>,
        install_state: InstallState,
        display_mode: ModuleDisplayMode,
    ) -> Self {
        Self {
            app_id: app_id.into(),
            display_name: display_name.into(),
            install_state,
            display_mode,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AgentSkinManifest {
    pub skin_id: String,
    pub display_name: String,
}

impl AgentSkinManifest {
    pub fn new(skin_id: impl Into<String>, display_name: impl Into<String>) -> Self {
        Self {
            skin_id: skin_id.into(),
            display_name: display_name.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ExperienceRegistryError {
    DuplicateAppId(String),
    DuplicateSkinId(String),
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct ExperienceRegistry {
    apps: Vec<InstalledAppManifest>,
    skins: Vec<AgentSkinManifest>,
}

impl ExperienceRegistry {
    pub fn new(
        mut apps: Vec<InstalledAppManifest>,
        mut skins: Vec<AgentSkinManifest>,
    ) -> Result<Self, ExperienceRegistryError> {
        apps.sort_by(|left, right| left.app_id.cmp(&right.app_id));
        skins.sort_by(|left, right| left.skin_id.cmp(&right.skin_id));

        if let Some(duplicate_app_id) = apps
            .windows(2)
            .find(|pair| pair[0].app_id == pair[1].app_id)
            .map(|pair| pair[0].app_id.clone())
        {
            return Err(ExperienceRegistryError::DuplicateAppId(duplicate_app_id));
        }

        if let Some(duplicate_skin_id) = skins
            .windows(2)
            .find(|pair| pair[0].skin_id == pair[1].skin_id)
            .map(|pair| pair[0].skin_id.clone())
        {
            return Err(ExperienceRegistryError::DuplicateSkinId(duplicate_skin_id));
        }

        Ok(Self { apps, skins })
    }

    pub fn apps(&self) -> &[InstalledAppManifest] {
        &self.apps
    }

    pub fn skins(&self) -> &[AgentSkinManifest] {
        &self.skins
    }
}
