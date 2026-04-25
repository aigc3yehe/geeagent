//! Agent Definition v2 — directory layout validation and `agent.json` loading.
//!
//! See `docs/specs/agent-definition-v2.md` for the public contract.

use std::{
    fmt, fs,
    path::{Component, Path, PathBuf},
};

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::{AgentAppearance, AgentProfile, ProfileSource, SkillRef};

/// Declarative on-disk authoring shape for an imported agent definition.
///
/// This is intentionally narrower than the runtime `AgentProfile`: the loaded
/// prompt is compiled from layered sibling files so the user can edit the agent
/// definition directly from Finder / the shell without touching `agent.json`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AgentPackManifest {
    pub definition_version: String,
    pub id: String,
    pub name: String,
    pub tagline: String,
    #[serde(default)]
    pub identity_prompt_path: PathBuf,
    #[serde(default)]
    pub soul_path: PathBuf,
    #[serde(default)]
    pub playbook_path: PathBuf,
    #[serde(default)]
    pub tools_context_path: Option<PathBuf>,
    #[serde(default)]
    pub memory_seed_path: Option<PathBuf>,
    #[serde(default)]
    pub heartbeat_path: Option<PathBuf>,
    pub appearance: AgentAppearance,
    #[serde(default)]
    pub skills: Vec<SkillRef>,
    #[serde(default)]
    pub allowed_tool_ids: Option<Vec<String>>,
    pub source: ProfileSource,
    pub version: String,
    #[serde(default)]
    pub author: Option<String>,
    #[serde(default)]
    pub license: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AgentPackContextPaths {
    pub identity_prompt_path: PathBuf,
    pub soul_path: PathBuf,
    pub playbook_path: PathBuf,
    pub tools_context_path: Option<PathBuf>,
    pub memory_seed_path: Option<PathBuf>,
    pub heartbeat_path: Option<PathBuf>,
}

/// Successful validation result for an agent definition package.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ValidatedAgentPack {
    pub root: PathBuf,
    pub manifest: AgentPackManifest,
    pub context_paths: AgentPackContextPaths,
    pub runtime_profile: AgentProfile,
}

/// Errors returned by [`validate_pack`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PackError {
    /// Pack root is not a directory.
    NotADirectory(PathBuf),
    /// `agent.json` is missing from the pack root.
    MissingAgentJson,
    /// `definition_version` is missing from `agent.json`.
    MissingDefinitionVersion,
    /// Only `definition_version == "2"` is supported for the current importer.
    UnsupportedDefinitionVersion(String),
    /// `agent.json` is not valid JSON.
    InvalidJson(String),
    /// Profile shape or semantic validation failed.
    InvalidProfile(String),
    /// Third-party packs must not claim the reserved first-party source.
    InvalidSource(String),
    /// A required layered file path is missing or empty.
    MissingRequiredContextPath(&'static str),
    /// A referenced layered file does not exist.
    MissingContextFile { field: &'static str, path: PathBuf },
    /// Referenced paths in a pack must stay inside the pack root.
    PathEscapesPack { field: &'static str, path: PathBuf },
    /// The pack references an appearance asset that does not exist.
    MissingAppearanceAsset { field: &'static str, path: PathBuf },
    /// Definition packs must not contain executables or scripts.
    ForbiddenExecutable(PathBuf),
}

impl fmt::Display for PackError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NotADirectory(path) => write!(f, "not a directory: {}", path.display()),
            Self::MissingAgentJson => write!(f, "missing agent.json in package root"),
            Self::MissingDefinitionVersion => {
                write!(f, "missing definition_version in agent.json")
            }
            Self::UnsupportedDefinitionVersion(version) => {
                write!(
                    f,
                    "unsupported definition_version `{version}` (expected `2`)"
                )
            }
            Self::InvalidJson(msg) => write!(f, "invalid JSON: {msg}"),
            Self::InvalidProfile(msg) => write!(f, "{msg}"),
            Self::InvalidSource(source) => {
                write!(
                    f,
                    "source `{source}` is reserved and cannot be imported from an agent definition"
                )
            }
            Self::MissingRequiredContextPath(field) => {
                write!(
                    f,
                    "missing required layered file path `{field}` in agent.json"
                )
            }
            Self::MissingContextFile { field, path } => write!(
                f,
                "{field} does not exist inside the agent definition: {}",
                path.display()
            ),
            Self::PathEscapesPack { field, path } => write!(
                f,
                "{field} points outside the agent definition root: {}",
                path.display()
            ),
            Self::MissingAppearanceAsset { field, path } => write!(
                f,
                "{field} does not exist inside the agent definition: {}",
                path.display()
            ),
            Self::ForbiddenExecutable(path) => write!(
                f,
                "package contains executable content, which is forbidden in Agent Definition v2: {}",
                path.display()
            ),
        }
    }
}

impl std::error::Error for PackError {}

impl PackError {
    pub fn code(&self) -> &'static str {
        match self {
            Self::NotADirectory(_) => "pack.not_a_directory",
            Self::MissingAgentJson => "pack.missing_agent_json",
            Self::MissingDefinitionVersion => "pack.missing_definition_version",
            Self::UnsupportedDefinitionVersion(_) => "pack.unsupported_definition_version",
            Self::InvalidJson(_) => "pack.invalid_json",
            Self::InvalidProfile(_) => "pack.invalid_profile",
            Self::InvalidSource(_) => "pack.invalid_source",
            Self::MissingRequiredContextPath(_) => "pack.invalid_profile",
            Self::MissingContextFile { .. } => "pack.missing_required_context_file",
            Self::PathEscapesPack { .. } => "pack.path_escapes_root",
            Self::MissingAppearanceAsset { .. } => "pack.missing_appearance_asset",
            Self::ForbiddenExecutable(_) => "pack.forbidden_executable",
        }
    }
}

/// Validates an Agent Definition v2 directory and returns the normalized runtime
/// `AgentProfile` plus the authoring-layer manifest metadata.
pub fn validate_pack(root: impl AsRef<Path>) -> Result<ValidatedAgentPack, PackError> {
    let root = root.as_ref();
    if !root.is_dir() {
        return Err(PackError::NotADirectory(root.to_path_buf()));
    }

    let agent_path = root.join("agent.json");
    if !agent_path.is_file() {
        return Err(PackError::MissingAgentJson);
    }

    let raw =
        fs::read_to_string(&agent_path).map_err(|e| PackError::InvalidProfile(e.to_string()))?;
    let value: Value =
        serde_json::from_str(&raw).map_err(|e| PackError::InvalidJson(e.to_string()))?;

    let definition_version = value
        .get("definition_version")
        .and_then(|v| v.as_str())
        .ok_or(PackError::MissingDefinitionVersion)?;
    if definition_version != "2" {
        return Err(PackError::UnsupportedDefinitionVersion(
            definition_version.to_string(),
        ));
    }

    reject_forbidden_files(root)?;

    let manifest: AgentPackManifest =
        serde_json::from_value(value).map_err(|e| PackError::InvalidProfile(e.to_string()))?;
    let (runtime_profile, context_paths) = build_runtime_profile(root, &manifest)?;

    Ok(ValidatedAgentPack {
        root: root.to_path_buf(),
        manifest,
        context_paths,
        runtime_profile,
    })
}

fn build_runtime_profile(
    root: &Path,
    manifest: &AgentPackManifest,
) -> Result<(AgentProfile, AgentPackContextPaths), PackError> {
    if matches!(manifest.source, ProfileSource::FirstParty) {
        return Err(PackError::InvalidSource("first_party".to_string()));
    }

    let context_paths = AgentPackContextPaths {
        identity_prompt_path: resolve_required_context_path(
            root,
            "identity_prompt_path",
            &manifest.identity_prompt_path,
        )?,
        soul_path: resolve_required_context_path(root, "soul_path", &manifest.soul_path)?,
        playbook_path: resolve_required_context_path(
            root,
            "playbook_path",
            &manifest.playbook_path,
        )?,
        tools_context_path: resolve_optional_context_path(
            root,
            "tools_context_path",
            manifest.tools_context_path.as_ref(),
        )?,
        memory_seed_path: resolve_optional_context_path(
            root,
            "memory_seed_path",
            manifest.memory_seed_path.as_ref(),
        )?,
        heartbeat_path: resolve_optional_context_path(
            root,
            "heartbeat_path",
            manifest.heartbeat_path.as_ref(),
        )?,
    };

    let prompt = compile_runtime_prompt(&context_paths)?;
    let appearance = resolve_manifest_appearance(root, &manifest.appearance)?;
    let skills = resolve_manifest_skills(root, &manifest.skills)?;
    if matches!(appearance, AgentAppearance::Abstract) {
        return Err(PackError::InvalidProfile(
            "imported profiles must declare a non-abstract appearance".to_string(),
        ));
    }

    let profile = AgentProfile {
        id: manifest.id.clone(),
        name: manifest.name.clone(),
        tagline: manifest.tagline.clone(),
        personality_prompt: prompt,
        appearance,
        skills,
        allowed_tool_ids: manifest.allowed_tool_ids.clone(),
        source: manifest.source.clone(),
        version: manifest.version.clone(),
    };
    profile.validate().map_err(PackError::InvalidProfile)?;

    Ok((profile, context_paths))
}

fn compile_runtime_prompt(context_paths: &AgentPackContextPaths) -> Result<String, PackError> {
    let mut sections = Vec::new();
    sections.push(compiled_section(
        "IDENTITY",
        read_context_file("identity_prompt_path", &context_paths.identity_prompt_path)?,
    ));
    sections.push(compiled_section(
        "SOUL",
        read_context_file("soul_path", &context_paths.soul_path)?,
    ));
    sections.push(compiled_section(
        "PLAYBOOK",
        read_context_file("playbook_path", &context_paths.playbook_path)?,
    ));

    if let Some(path) = &context_paths.tools_context_path {
        sections.push(compiled_section(
            "TOOLS",
            read_context_file("tools_context_path", path)?,
        ));
    }
    if let Some(path) = &context_paths.memory_seed_path {
        sections.push(compiled_section(
            "MEMORY",
            read_context_file("memory_seed_path", path)?,
        ));
    }
    if let Some(path) = &context_paths.heartbeat_path {
        sections.push(compiled_section(
            "HEARTBEAT",
            read_context_file("heartbeat_path", path)?,
        ));
    }

    Ok(sections.join("\n\n"))
}

fn compiled_section(title: &str, body: String) -> String {
    format!("[{title}]\n{body}")
}

fn read_context_file(field: &'static str, path: &Path) -> Result<String, PackError> {
    let raw = fs::read_to_string(path).map_err(|error| {
        PackError::InvalidProfile(format!(
            "failed to read {field} `{}`: {error}",
            path.display()
        ))
    })?;
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Err(PackError::InvalidProfile(format!(
            "{field} cannot point at an empty file"
        )));
    }

    Ok(trimmed.to_string())
}

fn resolve_manifest_appearance(
    root: &Path,
    appearance: &AgentAppearance,
) -> Result<AgentAppearance, PackError> {
    match appearance {
        AgentAppearance::StaticImage { asset_path } => {
            let resolved = resolve_required_pack_path(root, "appearance.asset_path", asset_path)?;
            if !resolved.is_file() {
                return Err(PackError::InvalidProfile(
                    "appearance.asset_path must point to a file".to_string(),
                ));
            }
            Ok(AgentAppearance::StaticImage {
                asset_path: resolved,
            })
        }
        AgentAppearance::Video { asset_path } => {
            let resolved = resolve_required_pack_path(root, "appearance.asset_path", asset_path)?;
            if !resolved.is_file() {
                return Err(PackError::InvalidProfile(
                    "appearance.asset_path must point to a file".to_string(),
                ));
            }
            Ok(AgentAppearance::Video {
                asset_path: resolved,
            })
        }
        AgentAppearance::Live2D { bundle_path } => {
            let resolved = resolve_required_pack_path(root, "appearance.bundle_path", bundle_path)?;
            if !(resolved.is_file() && has_model3_suffix(&resolved)) {
                return Err(PackError::InvalidProfile(
                    "appearance.bundle_path must point directly to a *.model3.json file in Agent Definition v2".to_string(),
                ));
            }
            Ok(AgentAppearance::Live2D {
                bundle_path: resolved,
            })
        }
        AgentAppearance::Abstract => Ok(AgentAppearance::Abstract),
    }
}

fn resolve_manifest_skills(root: &Path, skills: &[SkillRef]) -> Result<Vec<SkillRef>, PackError> {
    skills
        .iter()
        .map(|skill| {
            let mut resolved_skill = skill.clone();
            if let Some(path) = &skill.path {
                if path.as_os_str().is_empty() {
                    return Err(PackError::InvalidProfile(
                        "skills[].path cannot be empty".to_string(),
                    ));
                }
                let resolved_path = resolve_in_pack(root, "skills[].path", path)?;
                if !resolved_path.is_dir() {
                    return Err(PackError::InvalidProfile(format!(
                        "skills[].path must point to a folder containing SKILL.md: {}",
                        resolved_path.display()
                    )));
                }
                let skill_file = resolved_path.join("SKILL.md");
                if !skill_file.is_file() {
                    return Err(PackError::MissingContextFile {
                        field: "skills[].path",
                        path: skill_file,
                    });
                }
                resolved_skill.path = Some(resolved_path);
            }
            Ok(resolved_skill)
        })
        .collect()
}

fn resolve_required_context_path(
    root: &Path,
    field: &'static str,
    raw_path: &Path,
) -> Result<PathBuf, PackError> {
    if raw_path.as_os_str().is_empty() {
        return Err(PackError::MissingRequiredContextPath(field));
    }

    let resolved_path = resolve_in_pack(root, field, raw_path)?;
    if !resolved_path.is_file() {
        return Err(PackError::MissingContextFile {
            field,
            path: resolved_path,
        });
    }

    Ok(resolved_path)
}

fn resolve_optional_context_path(
    root: &Path,
    field: &'static str,
    raw_path: Option<&PathBuf>,
) -> Result<Option<PathBuf>, PackError> {
    let Some(raw_path) = raw_path else {
        return Ok(None);
    };
    if raw_path.as_os_str().is_empty() {
        return Err(PackError::InvalidProfile(format!(
            "{field} cannot be empty"
        )));
    }

    let resolved_path = resolve_in_pack(root, field, raw_path)?;
    if !resolved_path.is_file() {
        return Err(PackError::MissingContextFile {
            field,
            path: resolved_path,
        });
    }

    Ok(Some(resolved_path))
}

fn resolve_required_pack_path(
    root: &Path,
    field: &'static str,
    raw_path: &Path,
) -> Result<PathBuf, PackError> {
    if raw_path.as_os_str().is_empty() {
        return Err(PackError::InvalidProfile(format!(
            "{field} cannot be empty"
        )));
    }

    let resolved_path = resolve_in_pack(root, field, raw_path)?;
    if !resolved_path.exists() {
        return Err(PackError::MissingAppearanceAsset {
            field,
            path: resolved_path,
        });
    }

    Ok(resolved_path)
}

fn resolve_in_pack(
    root: &Path,
    field: &'static str,
    raw_path: &Path,
) -> Result<PathBuf, PackError> {
    let resolved_path = if raw_path.is_absolute() {
        raw_path.to_path_buf()
    } else {
        root.join(raw_path)
    };

    if resolved_path.is_absolute() && !resolved_path.starts_with(root) {
        return Err(PackError::PathEscapesPack {
            field,
            path: resolved_path,
        });
    }

    if has_parent_dir_component(resolved_path.strip_prefix(root).unwrap_or(&resolved_path)) {
        return Err(PackError::PathEscapesPack {
            field,
            path: resolved_path,
        });
    }

    Ok(resolved_path)
}

fn has_parent_dir_component(path: &Path) -> bool {
    path.components()
        .any(|component| matches!(component, Component::ParentDir))
}

fn reject_forbidden_files(root: &Path) -> Result<(), PackError> {
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let entries = fs::read_dir(&dir).map_err(|e| PackError::InvalidProfile(e.to_string()))?;
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                stack.push(path);
                continue;
            }

            if is_forbidden_file(&path)? {
                return Err(PackError::ForbiddenExecutable(path));
            }
        }
    }
    Ok(())
}

fn is_forbidden_file(path: &Path) -> Result<bool, PackError> {
    let extension = path
        .extension()
        .and_then(|ext| ext.to_str())
        .map(|ext| ext.to_ascii_lowercase());

    if matches!(
        extension.as_deref(),
        Some(
            "sh" | "command"
                | "bash"
                | "zsh"
                | "fish"
                | "py"
                | "rb"
                | "pl"
                | "exe"
                | "bat"
                | "cmd"
                | "app"
                | "dylib"
                | "so"
        )
    ) {
        return Ok(true);
    }

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;

        let metadata = fs::metadata(path).map_err(|e| PackError::InvalidProfile(e.to_string()))?;
        if metadata.permissions().mode() & 0o111 != 0 {
            return Ok(true);
        }
    }

    Ok(false)
}

fn has_model3_suffix(path: &Path) -> bool {
    path.file_name()
        .and_then(|name| name.to_str())
        .map(|name| name.to_ascii_lowercase().ends_with(".model3.json"))
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::{PackError, validate_pack};
    use std::{fs, path::PathBuf};

    #[test]
    fn validate_pack_compiles_layered_prompt_sections() {
        let pack_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../examples/agent-packs/companion-sora");

        let validated = validate_pack(&pack_root).expect("v2 pack should validate");
        let prompt = validated.runtime_profile.personality_prompt;

        assert!(prompt.contains("[IDENTITY]"));
        assert!(prompt.contains("[SOUL]"));
        assert!(prompt.contains("[PLAYBOOK]"));
        assert!(prompt.contains("Sora"));
    }

    #[test]
    fn validate_pack_resolves_skill_whitelist_paths() {
        let temp_dir = tempfile::tempdir().expect("tempdir");
        let root = temp_dir.path();
        fs::write(root.join("identity-prompt.md"), "identity").expect("identity");
        fs::write(root.join("soul.md"), "soul").expect("soul");
        fs::write(root.join("playbook.md"), "playbook").expect("playbook");
        fs::create_dir(root.join("appearance")).expect("appearance");
        fs::write(root.join("appearance/hero.png"), b"png").expect("hero");
        fs::create_dir_all(root.join("skills/research")).expect("skill dir");
        fs::write(
            root.join("skills/research/SKILL.md"),
            "# Research\n\nUse evidence.",
        )
        .expect("skill");
        fs::write(
            root.join("agent.json"),
            r#"{
                "definition_version": "2",
                "id": "skilled",
                "name": "Skilled",
                "tagline": "Skill whitelist",
                "identity_prompt_path": "identity-prompt.md",
                "soul_path": "soul.md",
                "playbook_path": "playbook.md",
                "appearance": { "kind": "static_image", "asset_path": "appearance/hero.png" },
                "skills": [{ "id": "research", "path": "skills/research" }],
                "source": "module_pack",
                "version": "1.0.0"
            }"#,
        )
        .expect("manifest");

        let validated = validate_pack(root).expect("skill path should validate");

        assert_eq!(
            validated.runtime_profile.skills[0].path.as_ref(),
            Some(&root.join("skills/research"))
        );
    }

    #[test]
    fn validate_pack_rejects_missing_definition_version() {
        let temp_dir = tempfile::tempdir().expect("tempdir");
        let root = temp_dir.path();
        fs::write(
            root.join("agent.json"),
            r#"{
                "id": "broken",
                "name": "Broken",
                "tagline": "Missing version",
                "identity_prompt_path": "identity-prompt.md",
                "soul_path": "soul.md",
                "playbook_path": "playbook.md",
                "appearance": { "kind": "static_image", "asset_path": "appearance/hero.png" },
                "source": "module_pack",
                "version": "1.0.0"
            }"#,
        )
        .expect("manifest");
        fs::write(root.join("identity-prompt.md"), "identity").expect("identity");
        fs::write(root.join("soul.md"), "soul").expect("soul");
        fs::write(root.join("playbook.md"), "playbook").expect("playbook");
        fs::create_dir(root.join("appearance")).expect("appearance");
        fs::write(root.join("appearance/hero.png"), b"png").expect("hero");

        let error = validate_pack(root).expect_err("missing definition_version should fail");
        assert_eq!(error, PackError::MissingDefinitionVersion);
        assert_eq!(error.code(), "pack.missing_definition_version");
    }
}
