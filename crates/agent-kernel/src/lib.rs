use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

use serde::{Deserialize, Serialize};

mod pack;

pub use pack::{AgentPackManifest, PackError, ValidatedAgentPack, validate_pack};

const BUNDLED_GEE_PROFILE_JSON: &str = include_str!("../../../config/agents/gee.json");

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SkillRef {
    pub id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub path: Option<PathBuf>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "kind")]
pub enum AgentAppearance {
    StaticImage {
        asset_path: PathBuf,
    },
    Video {
        asset_path: PathBuf,
    },
    #[serde(rename = "live2d", alias = "live2_d")]
    Live2D {
        bundle_path: PathBuf,
    },
    Abstract,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProfileSource {
    FirstParty,
    UserCreated,
    ModulePack,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AgentProfile {
    pub id: String,
    pub name: String,
    pub tagline: String,
    pub personality_prompt: String,
    pub appearance: AgentAppearance,
    #[serde(default)]
    pub skills: Vec<SkillRef>,
    #[serde(default)]
    pub allowed_tool_ids: Option<Vec<String>>,
    pub source: ProfileSource,
    pub version: String,
}

impl AgentProfile {
    pub fn from_json_str(raw: &str) -> Result<Self, String> {
        serde_json::from_str(raw).map_err(|error| error.to_string())
    }

    pub fn load_from_file(path: impl AsRef<Path>) -> Result<Self, String> {
        let path = path.as_ref();
        let raw = fs::read_to_string(path)
            .map_err(|error| format!("failed to read `{}`: {error}", path.display()))?;
        let mut profile = Self::from_json_str(&raw)
            .map_err(|error| format!("failed to parse `{}`: {error}", path.display()))?;
        let base_dir = path.parent().unwrap_or_else(|| Path::new("."));
        profile.normalize_loaded_paths(base_dir);
        profile
            .validate()
            .map_err(|error| format!("invalid `{}`: {error}", path.display()))?;
        Ok(profile)
    }

    pub fn validate(&self) -> Result<(), String> {
        ensure_non_empty("id", &self.id)?;
        ensure_non_empty("name", &self.name)?;
        ensure_non_empty("tagline", &self.tagline)?;
        ensure_non_empty("personality_prompt", &self.personality_prompt)?;
        ensure_non_empty("version", &self.version)?;

        for skill in &self.skills {
            ensure_non_empty("skills[].id", &skill.id)?;
            if let Some(path) = &skill.path {
                ensure_non_empty_path("skills[].path", path)?;
                validate_skill_path_on_disk(path)?;
            }
        }

        if let Some(allowed_tool_ids) = &self.allowed_tool_ids {
            for tool_id in allowed_tool_ids {
                ensure_non_empty("allowed_tool_ids[]", tool_id)?;
            }
        }

        match &self.appearance {
            AgentAppearance::StaticImage { asset_path } | AgentAppearance::Video { asset_path } => {
                ensure_non_empty_path("appearance.asset_path", asset_path)?;
            }
            AgentAppearance::Live2D { bundle_path } => {
                ensure_non_empty_path("appearance.bundle_path", bundle_path)?;
                // When the bundle exists on disk, require a Cubism `*.model3.json` descriptor
                // inside it. When the path hasn't been materialized yet (e.g. a profile loaded
                // before the pack was imported), skip the fs check so validation stays a pure
                // shape check. See `validate_live2d_bundle_on_disk` for the physical invariant.
                validate_live2d_bundle_on_disk(bundle_path)?;
            }
            AgentAppearance::Abstract => {}
        }

        Ok(())
    }

    fn normalize_loaded_paths(&mut self, base_dir: &Path) {
        match &mut self.appearance {
            AgentAppearance::StaticImage { asset_path } | AgentAppearance::Video { asset_path } => {
                if asset_path.is_relative() {
                    *asset_path = base_dir.join(&*asset_path);
                }
            }
            AgentAppearance::Live2D { bundle_path } => {
                if bundle_path.is_relative() {
                    *bundle_path = base_dir.join(&*bundle_path);
                }
            }
            AgentAppearance::Abstract => {}
        }

        for skill in &mut self.skills {
            if let Some(path) = &mut skill.path {
                if path.is_relative() {
                    *path = base_dir.join(&*path);
                }
            }
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AgentRuntimeContext {
    pub agent_id: String,
    pub profile_id: String,
    pub conversation_id: Option<String>,
    pub task_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentProfileRegistry {
    #[serde(default)]
    profiles: BTreeMap<String, AgentProfile>,
    #[serde(default)]
    active_profile_id: String,
}

impl AgentProfileRegistry {
    pub fn empty() -> Self {
        Self {
            profiles: BTreeMap::new(),
            active_profile_id: String::new(),
        }
    }

    pub fn bundled_defaults() -> Result<Self, String> {
        let mut profile = AgentProfile::from_json_str(BUNDLED_GEE_PROFILE_JSON)
            .map_err(|error| format!("failed to parse bundled gee profile: {error}"))?;
        profile.normalize_loaded_paths(&bundled_agents_dir());
        profile
            .validate()
            .map_err(|error| format!("bundled gee profile is invalid: {error}"))?;
        Self::from_profiles([profile])
    }

    pub fn from_profiles(profiles: impl IntoIterator<Item = AgentProfile>) -> Result<Self, String> {
        let mut registry = Self::empty();
        for profile in profiles {
            registry.insert(profile)?;
        }
        Ok(registry)
    }

    pub fn load_dir(path: impl AsRef<Path>) -> Result<Self, String> {
        let path = path.as_ref();
        if !path.exists() {
            return Ok(Self::empty());
        }
        if !path.is_dir() {
            return Err(format!("`{}` is not a directory", path.display()));
        }

        let mut entries = fs::read_dir(path)
            .map_err(|error| format!("failed to read `{}`: {error}", path.display()))?
            .filter_map(|entry| entry.ok().map(|entry| entry.path()))
            .filter(|entry| entry.extension().and_then(|ext| ext.to_str()) == Some("json"))
            .collect::<Vec<_>>();
        entries.sort();

        let mut registry = Self::empty();
        for entry in entries {
            let profile = AgentProfile::load_from_file(&entry)?;
            registry.insert(profile)?;
        }

        Ok(registry)
    }

    pub fn merge(&mut self, other: Self) -> Result<(), String> {
        let preferred_active = other.active_profile_id.clone();
        for profile in other.profiles.into_values() {
            self.insert(profile)?;
        }
        if self.active_profile_id.is_empty() && !preferred_active.is_empty() {
            self.active_profile_id = preferred_active;
        }
        Ok(())
    }

    pub fn insert(&mut self, profile: AgentProfile) -> Result<(), String> {
        profile.validate()?;

        if self.profiles.contains_key(&profile.id) {
            return Err(format!(
                "agent profile `{}` is already registered",
                profile.id
            ));
        }

        let profile_id = profile.id.clone();
        self.profiles.insert(profile_id.clone(), profile);
        if self.active_profile_id.is_empty() {
            self.active_profile_id = profile_id;
        }
        Ok(())
    }

    pub fn get(&self, profile_id: &str) -> Option<&AgentProfile> {
        self.profiles.get(profile_id)
    }

    pub fn active_profile_id(&self) -> Option<&str> {
        if self.active_profile_id.is_empty() {
            None
        } else {
            Some(&self.active_profile_id)
        }
    }

    pub fn active(&self) -> Option<&AgentProfile> {
        self.active_profile_id()
            .and_then(|profile_id| self.get(profile_id))
            .or_else(|| self.profiles.values().next())
    }

    pub fn list(&self) -> Vec<&AgentProfile> {
        self.profiles.values().collect()
    }

    pub fn len(&self) -> usize {
        self.profiles.len()
    }

    pub fn is_empty(&self) -> bool {
        self.profiles.is_empty()
    }

    pub fn set_active(&mut self, profile_id: &str) -> Result<bool, String> {
        if !self.profiles.contains_key(profile_id) {
            return Err(format!("unknown agent profile `{profile_id}`"));
        }

        if self.active_profile_id == profile_id {
            return Ok(false);
        }

        self.active_profile_id = profile_id.to_string();
        Ok(true)
    }

    pub fn into_profiles(self) -> Vec<AgentProfile> {
        self.profiles.into_values().collect()
    }
}

fn ensure_non_empty(field_name: &str, value: &str) -> Result<(), String> {
    if value.trim().is_empty() {
        return Err(format!("{field_name} cannot be empty"));
    }

    Ok(())
}

fn ensure_non_empty_path(field_name: &str, value: &Path) -> Result<(), String> {
    if value.as_os_str().is_empty() {
        return Err(format!("{field_name} cannot be empty"));
    }

    Ok(())
}

fn validate_skill_path_on_disk(path: &Path) -> Result<(), String> {
    if !path.exists() {
        return Err(format!(
            "skills[].path `{}` must point at a folder containing SKILL.md",
            path.display()
        ));
    }
    if !path.is_dir() {
        return Err(format!(
            "skills[].path `{}` must be a folder containing SKILL.md",
            path.display()
        ));
    }
    let skill_file = path.join("SKILL.md");
    if !skill_file.is_file() {
        return Err(format!(
            "skills[].path `{}` is missing SKILL.md",
            path.display()
        ));
    }

    Ok(())
}

/// Verifies that a `Live2D { bundle_path }` appearance references a real Cubism bundle.
///
/// - If `bundle_path` does not exist, validation is a no-op (the profile may have been loaded
///   before the asset was materialized; the Swift side handles eventual resolution).
/// - If `bundle_path` is a file, it must end in `.model3.json`.
/// - If `bundle_path` is a directory, it must contain a `*.model3.json` at its root OR at one
///   level of nesting (a common layout for unzipped Cubism bundles with a single subfolder).
fn validate_live2d_bundle_on_disk(bundle_path: &Path) -> Result<(), String> {
    if !bundle_path.exists() {
        return Ok(());
    }

    if bundle_path.is_file() {
        return if has_model3_suffix(bundle_path) {
            Ok(())
        } else {
            Err(format!(
                "appearance.bundle_path `{}` must be a *.model3.json file or a directory containing one",
                bundle_path.display()
            ))
        };
    }

    if bundle_path.is_dir() {
        return if contains_model3_json(bundle_path) {
            Ok(())
        } else {
            Err(format!(
                "appearance.bundle_path `{}` is a directory but has no *.model3.json descriptor at its root or one level deep",
                bundle_path.display()
            ))
        };
    }

    Err(format!(
        "appearance.bundle_path `{}` is neither a file nor a directory",
        bundle_path.display()
    ))
}

fn has_model3_suffix(path: &Path) -> bool {
    path.file_name()
        .and_then(|name| name.to_str())
        .map(|name| name.to_ascii_lowercase().ends_with(".model3.json"))
        .unwrap_or(false)
}

fn contains_model3_json(dir: &Path) -> bool {
    let Ok(entries) = fs::read_dir(dir) else {
        return false;
    };
    let mut candidates = Vec::new();
    for entry in entries.flatten() {
        let entry_path = entry.path();
        if entry_path.is_file() && has_model3_suffix(&entry_path) {
            return true;
        }
        if entry_path.is_dir() {
            candidates.push(entry_path);
        }
    }
    // One level of nesting is tolerated so `.zip` imports that preserve a wrapper folder still validate.
    for nested in candidates {
        let Ok(nested_entries) = fs::read_dir(&nested) else {
            continue;
        };
        for entry in nested_entries.flatten() {
            let entry_path = entry.path();
            if entry_path.is_file() && has_model3_suffix(&entry_path) {
                return true;
            }
        }
    }
    false
}

fn bundled_agents_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../config/agents")
}
