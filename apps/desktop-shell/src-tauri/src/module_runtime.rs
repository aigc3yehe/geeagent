use std::{
    collections::HashMap,
    env, fs,
    path::{Path, PathBuf},
    time::Duration,
};

use module_gateway::{ModuleRun, ModuleStatusResponse};
use reqwest::Client;
use serde::Deserialize;

const DEFAULT_MODULE_REGISTRY_TOML: &str = include_str!("../../../../config/module-registry.toml");

#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
pub struct ModuleRegistryConfig {
    pub version: u8,
    #[serde(default = "default_request_timeout_seconds")]
    pub request_timeout_seconds: u64,
    #[serde(default)]
    pub modules: HashMap<String, ModuleRefreshConfig>,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
pub struct ModuleRefreshConfig {
    pub enabled: bool,
    pub refresh_mode: RefreshMode,
    pub base_url: Option<String>,
    pub status_path_template: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RefreshMode {
    Simulated,
    Http,
}

#[derive(Clone)]
pub struct ModuleStatusRuntime {
    client: Client,
    config: ModuleRegistryConfig,
}

fn default_request_timeout_seconds() -> u64 {
    4
}

fn load_config_text(
    override_dir: Option<&Path>,
    file_name: &str,
    embedded_default: &str,
) -> Result<String, String> {
    if let Ok(env_override) = env::var("GEEAGENT_CONFIG_DIR") {
        let path = PathBuf::from(env_override).join(file_name);
        if path.exists() {
            return fs::read_to_string(path).map_err(|error| error.to_string());
        }
    }

    if let Some(override_dir) = override_dir {
        let path = override_dir.join(file_name);
        if path.exists() {
            return fs::read_to_string(path).map_err(|error| error.to_string());
        }
    }

    let repo_path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../..")
        .join("config")
        .join(file_name);
    if repo_path.exists() {
        return fs::read_to_string(repo_path).map_err(|error| error.to_string());
    }

    Ok(embedded_default.to_string())
}

impl ModuleRegistryConfig {
    pub fn from_toml_str(input: &str) -> Result<Self, String> {
        let config: Self = toml::from_str(input).map_err(|error| error.to_string())?;
        if config.version != 1 {
            return Err(format!(
                "module registry version `{}` is not supported",
                config.version
            ));
        }

        for (module_id, module) in &config.modules {
            match module.refresh_mode {
                RefreshMode::Simulated => {}
                RefreshMode::Http => {
                    let base_url = module.base_url.as_deref().ok_or_else(|| {
                        format!("module `{module_id}` requires base_url for http refresh")
                    })?;
                    if !(base_url.starts_with("http://") || base_url.starts_with("https://")) {
                        return Err(format!(
                            "module `{module_id}` base_url must start with http:// or https://"
                        ));
                    }
                }
            }
        }

        Ok(config)
    }

    pub fn status_endpoint_for_run(
        &self,
        module_id: &str,
        module_run_id: &str,
    ) -> Result<Option<String>, String> {
        let Some(module) = self.modules.get(module_id) else {
            return Ok(None);
        };

        if !module.enabled || matches!(module.refresh_mode, RefreshMode::Simulated) {
            return Ok(None);
        }

        let base_url = module
            .base_url
            .as_deref()
            .ok_or_else(|| format!("module `{module_id}` is missing base_url"))?;
        let path_template = module
            .status_path_template
            .clone()
            .unwrap_or_else(|| "/runs/{module_run_id}".to_string());
        let path = path_template.replace("{module_run_id}", module_run_id);
        let normalized_base = base_url.trim_end_matches('/');
        let normalized_path = if path.starts_with('/') {
            path
        } else {
            format!("/{path}")
        };

        Ok(Some(format!("{normalized_base}{normalized_path}")))
    }
}

impl ModuleStatusRuntime {
    pub fn from_config_dir(config_dir: Option<&Path>) -> Result<Self, String> {
        let raw = load_config_text(
            config_dir,
            "module-registry.toml",
            DEFAULT_MODULE_REGISTRY_TOML,
        )?;
        let config = ModuleRegistryConfig::from_toml_str(&raw)?;
        Self::from_config(config)
    }

    fn from_config(config: ModuleRegistryConfig) -> Result<Self, String> {
        let client = Client::builder()
            .timeout(Duration::from_secs(config.request_timeout_seconds))
            .build()
            .map_err(|error| error.to_string())?;

        Ok(Self { client, config })
    }

    pub async fn fetch_status(
        &self,
        module_run: &ModuleRun,
    ) -> Result<Option<ModuleStatusResponse>, String> {
        let Some(endpoint) = self
            .config
            .status_endpoint_for_run(&module_run.module_id, &module_run.module_run_id)?
        else {
            return Ok(None);
        };

        let response = self
            .client
            .get(endpoint)
            .send()
            .await
            .map_err(|error| error.to_string())?;

        if response.status().is_success() {
            return response
                .json::<ModuleStatusResponse>()
                .await
                .map(Some)
                .map_err(|error| error.to_string());
        }

        if response.status().as_u16() == 404 || response.status().as_u16() == 501 {
            return Ok(None);
        }

        Err(format!(
            "module status request failed with {}",
            response.status()
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::ModuleRegistryConfig;
    use module_gateway::{ModuleRun, ModuleRunStage, ModuleRunStatus};
    use std::{
        io::{Read, Write},
        net::TcpListener,
        thread,
    };

    #[test]
    fn parses_http_and_simulated_module_refresh_strategies() {
        let config = ModuleRegistryConfig::from_toml_str(
            r#"
version = 1

[modules."content.youtube.monitor"]
enabled = true
refresh_mode = "http"
base_url = "http://127.0.0.1:47821/gee/v1"

[modules."social.x.publisher"]
enabled = true
refresh_mode = "simulated"
"#,
        )
        .expect("config should parse");

        assert_eq!(config.version, 1);
        assert_eq!(config.request_timeout_seconds, 4);
        assert_eq!(
            config.modules["content.youtube.monitor"].refresh_mode,
            super::RefreshMode::Http
        );
        assert_eq!(
            config.modules["social.x.publisher"].refresh_mode,
            super::RefreshMode::Simulated
        );
    }

    #[test]
    fn builds_status_endpoint_from_registry_entry() {
        let config = ModuleRegistryConfig::from_toml_str(
            r#"
version = 1

[modules."content.youtube.monitor"]
enabled = true
refresh_mode = "http"
base_url = "http://127.0.0.1:47821/gee/v1"
status_path_template = "/runs/{module_run_id}"
"#,
        )
        .expect("config should parse");

        let endpoint = config
            .status_endpoint_for_run("content.youtube.monitor", "run_42")
            .expect("lookup should succeed")
            .expect("http module should have endpoint");

        assert_eq!(endpoint, "http://127.0.0.1:47821/gee/v1/runs/run_42");
    }

    #[test]
    fn simulated_modules_do_not_require_status_endpoint() {
        let config = ModuleRegistryConfig::from_toml_str(
            r#"
version = 1

[modules."social.x.publisher"]
enabled = true
refresh_mode = "simulated"
"#,
        )
        .expect("config should parse");

        assert_eq!(
            config
                .status_endpoint_for_run("social.x.publisher", "run_01")
                .expect("lookup should succeed"),
            None
        );
    }

    #[test]
    fn fetch_status_reads_live_http_module_responses() {
        let listener = TcpListener::bind("127.0.0.1:0").expect("listener should bind");
        let address = listener.local_addr().expect("listener should have address");

        let server = thread::spawn(move || {
            let (mut stream, _) = listener.accept().expect("server should accept one request");
            let mut buffer = [0u8; 2048];
            let bytes_read = stream
                .read(&mut buffer)
                .expect("request should be readable");
            let request = String::from_utf8_lossy(&buffer[..bytes_read]);
            assert!(request.starts_with("GET /gee/v1/runs/run_42 HTTP/1.1"));

            let body = r#"{
  "module_run": {
    "module_run_id": "run_42",
    "task_id": "task_42",
    "module_id": "content.youtube.monitor",
    "capability_id": "digest_recent_uploads",
    "status": "completed",
    "stage": "finalized",
    "attempt_count": 1,
    "result_summary": "Remote digest complete.",
    "artifacts": [],
    "created_at": "now",
    "updated_at": "now"
  },
  "recoverability": null,
  "result_preview": null
}"#;

            write!(
        stream,
        "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{}",
        body.len(),
        body
      )
      .expect("response should write");
        });

        let config = ModuleRegistryConfig::from_toml_str(
            format!(
                r#"
version = 1

[modules."content.youtube.monitor"]
enabled = true
refresh_mode = "http"
base_url = "http://{address}/gee/v1"
status_path_template = "/runs/{{module_run_id}}"
"#
            )
            .as_str(),
        )
        .expect("config should parse");
        let runtime =
            super::ModuleStatusRuntime::from_config(config).expect("runtime should build");

        let response = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("tokio runtime should build")
            .block_on(runtime.fetch_status(&ModuleRun {
                module_run_id: "run_42".to_string(),
                task_id: "task_42".to_string(),
                module_id: "content.youtube.monitor".to_string(),
                capability_id: "digest_recent_uploads".to_string(),
                status: ModuleRunStatus::Running,
                stage: ModuleRunStage::WaitingUpstream,
                attempt_count: 1,
                result_summary: None,
                artifacts: vec![],
                created_at: "now".to_string(),
                updated_at: "now".to_string(),
            }))
            .expect("request should succeed")
            .expect("http module should return a live status");

        assert_eq!(response.module_run.status, ModuleRunStatus::Completed);
        assert_eq!(response.module_run.stage, ModuleRunStage::Finalized);

        server.join().expect("server thread should finish");
    }
}
