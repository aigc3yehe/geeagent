use std::{collections::HashMap, error::Error, fmt, fs, path::Path};

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub struct ContinuationConfig {
    pub min_confidence_to_resume: f64,
    pub fallback_action: String,
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub struct RouteClass {
    pub provider: String,
    pub model: String,
    pub reasoning_effort: String,
    pub fallback_model: String,
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub struct ProfileRoutingPolicy {
    pub default_route_class: String,
    #[serde(default)]
    pub upgrade_when: Vec<String>,
    #[serde(default)]
    pub downgrade_when: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub struct TaskTypeRoutingPolicy {
    pub default_profile: String,
    pub default_route_class: String,
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub struct RoutingConfig {
    pub default_route_class: String,
    pub allow_user_overrides: bool,
    pub continuation: ContinuationConfig,
    #[serde(default)]
    pub route_classes: HashMap<String, RouteClass>,
    #[serde(default)]
    pub profiles: HashMap<String, ProfileRoutingPolicy>,
    #[serde(default)]
    pub task_types: HashMap<String, TaskTypeRoutingPolicy>,
}

#[derive(Debug)]
pub enum RoutingConfigError {
    Parse(toml::de::Error),
    Validation(String),
}

impl fmt::Display for RoutingConfigError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Parse(error) => write!(f, "{error}"),
            Self::Validation(message) => write!(f, "{message}"),
        }
    }
}

impl Error for RoutingConfigError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        match self {
            Self::Parse(error) => Some(error),
            Self::Validation(_) => None,
        }
    }
}

impl RoutingConfig {
    pub fn from_path(path: impl AsRef<Path>) -> Result<Self, std::io::Error> {
        let raw = fs::read_to_string(path)?;
        Self::from_toml_str(&raw).map_err(std::io::Error::other)
    }

    pub fn from_toml_str(input: &str) -> Result<Self, RoutingConfigError> {
        let config: Self = toml::from_str(input).map_err(RoutingConfigError::Parse)?;
        config.validate()?;
        Ok(config)
    }

    fn validate(&self) -> Result<(), RoutingConfigError> {
        if !self.route_classes.contains_key(&self.default_route_class) {
            return Err(RoutingConfigError::Validation(format!(
                "default_route_class `{}` must reference a defined route class",
                self.default_route_class
            )));
        }

        for (profile_name, profile) in &self.profiles {
            if !self
                .route_classes
                .contains_key(&profile.default_route_class)
            {
                return Err(RoutingConfigError::Validation(format!(
                    "profile `{profile_name}` default_route_class `{}` must reference a defined route class",
                    profile.default_route_class
                )));
            }
        }

        for (task_type_name, task_type) in &self.task_types {
            if !self.profiles.contains_key(&task_type.default_profile) {
                return Err(RoutingConfigError::Validation(format!(
                    "task_type `{task_type_name}` default_profile `{}` must reference a defined profile",
                    task_type.default_profile
                )));
            }

            if !self
                .route_classes
                .contains_key(&task_type.default_route_class)
            {
                return Err(RoutingConfigError::Validation(format!(
                    "task_type `{task_type_name}` default_route_class `{}` must reference a defined route class",
                    task_type.default_route_class
                )));
            }
        }

        Ok(())
    }
}
