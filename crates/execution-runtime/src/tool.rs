//! Agent-invocable tool catalog (v1).
//!
//! This is the `execution-runtime` half of Plan 4. It defines the types shared by
//! `runtime-kernel::ToolDispatcher` (pure routing/gating) and the actual executors
//! that reach into the OS. Runtime-kernel decides *whether* a tool runs; this
//! module decides *how*.
//!
//! ## v1 constraints
//! - The catalog is a compile-time array. Third-party packs cannot register tools.
//! - Executors return structured JSON payloads so Swift can apply them without
//!   another round-trip through the snapshot.
//! - OS-touching tools use plain `std::process::Command`. No `tokio`, no IPC
//!   daemons — these are intentionally synchronous and small.
//! - `shell.run` has a strict allow-list; anything outside returns an
//!   `Error { code: "shell.command_not_allowed" }` outcome.

use std::{
    collections::HashMap,
    fs,
    io::Write,
    path::{Path, PathBuf},
    process::{Command, Stdio},
};

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

/// Blast radius hints the UI when asking for approval. Not authoritative for gating —
/// gating is controlled by `needs_approval` on the spec.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ToolBlastRadius {
    /// Reads in-app state or pops UI. No persistent side effect.
    Safe,
    /// Reads from the local filesystem / clipboard. Reversible.
    Local,
    /// Writes to disk, executes shell, opens external app, or posts notifications.
    External,
}

/// A tool description. v1 tools are declarative — the compile-time array here is
/// the authoritative registry.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ToolSpec {
    pub id: &'static str,
    pub title: &'static str,
    pub description: &'static str,
    pub needs_approval: bool,
    pub blast_radius: ToolBlastRadius,
}

/// The v1 tool catalog.
pub const V1_TOOL_CATALOG: &[ToolSpec] = &[
    ToolSpec {
        id: "core.read",
        title: "Read file",
        description: "Read a UTF-8 file from the local filesystem and return its contents.",
        needs_approval: false,
        blast_radius: ToolBlastRadius::Local,
    },
    ToolSpec {
        id: "core.write",
        title: "Write file",
        description: "Write UTF-8 content to the local filesystem. Requires approval.",
        needs_approval: true,
        blast_radius: ToolBlastRadius::External,
    },
    ToolSpec {
        id: "core.edit",
        title: "Edit file",
        description: "Apply a bounded text replacement to a UTF-8 file. Requires approval.",
        needs_approval: true,
        blast_radius: ToolBlastRadius::External,
    },
    ToolSpec {
        id: "core.bash",
        title: "Run bash command",
        description: "Run a guarded local command. Read-only inspections may proceed directly; broader commands require approval.",
        needs_approval: true,
        blast_radius: ToolBlastRadius::External,
    },
    ToolSpec {
        id: "core.grep",
        title: "Search file contents",
        description: "Search UTF-8 files under a directory for a literal text pattern.",
        needs_approval: false,
        blast_radius: ToolBlastRadius::Local,
    },
    ToolSpec {
        id: "core.find",
        title: "Find files",
        description: "Find filesystem entries under a directory by literal name substring.",
        needs_approval: false,
        blast_radius: ToolBlastRadius::Local,
    },
    ToolSpec {
        id: "core.ls",
        title: "List directory",
        description: "List entries in a local directory.",
        needs_approval: false,
        blast_radius: ToolBlastRadius::Local,
    },
    ToolSpec {
        id: "navigate.openSection",
        title: "Open workbench section",
        description: "Switch the workbench nav to a known section (home, chat, tasks, agents, settings, apps).",
        needs_approval: false,
        blast_radius: ToolBlastRadius::Safe,
    },
    ToolSpec {
        id: "navigate.openModule",
        title: "Open installed module",
        description: "Open an installed capability module by id.",
        needs_approval: false,
        blast_radius: ToolBlastRadius::Safe,
    },
    ToolSpec {
        id: "files.readText",
        title: "Read text file",
        description: "Read a UTF-8 file from the local filesystem and return its contents.",
        needs_approval: false,
        blast_radius: ToolBlastRadius::Local,
    },
    ToolSpec {
        id: "files.writeText",
        title: "Write text file",
        description: "Write UTF-8 content to the local filesystem. Requires approval.",
        needs_approval: true,
        blast_radius: ToolBlastRadius::External,
    },
    ToolSpec {
        id: "shell.run",
        title: "Run shell command",
        description: "Run one of the guarded shell commands. Read-only inspections may proceed directly; broader commands require approval.",
        needs_approval: true,
        blast_radius: ToolBlastRadius::External,
    },
    ToolSpec {
        id: "clipboard.read",
        title: "Read clipboard",
        description: "Read the current pasteboard text.",
        needs_approval: false,
        blast_radius: ToolBlastRadius::Local,
    },
    ToolSpec {
        id: "clipboard.write",
        title: "Write clipboard",
        description: "Replace the pasteboard text.",
        needs_approval: false,
        blast_radius: ToolBlastRadius::Local,
    },
    ToolSpec {
        id: "url.open",
        title: "Open URL",
        description: "Open a URL in the user's default handler.",
        needs_approval: false,
        blast_radius: ToolBlastRadius::External,
    },
    ToolSpec {
        id: "notify.post",
        title: "Post system notification",
        description: "Post a system notification via `osascript`.",
        needs_approval: false,
        blast_radius: ToolBlastRadius::External,
    },
];

/// Commands allowed for `shell.run` in v1. Command names alone are not enough;
/// `shell_command_policy` also validates subcommands/args before execution.
pub const SHELL_ALLOW_LIST: &[&str] = &[
    "ls", "pwd", "echo", "date", "uname", "whoami", "ps", "lsof", "docker", "git", "cat", "grep",
    "rg", "find", "head", "tail",
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShellCommandPolicy {
    AllowedNoApproval,
    AllowedNeedsApproval,
    Denied,
}

pub fn shell_request_needs_approval(request: &ToolRequest) -> bool {
    let Some(command) = request.arguments.get("command").and_then(Value::as_str) else {
        return true;
    };
    let args = shell_args(request);
    matches!(
        shell_command_policy(command, &args),
        ShellCommandPolicy::AllowedNeedsApproval
    )
}

fn shell_args(request: &ToolRequest) -> Vec<String> {
    request
        .arguments
        .get("args")
        .and_then(Value::as_array)
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_str().map(str::to_owned))
                .collect()
        })
        .unwrap_or_default()
}

fn shell_command_policy(command: &str, args: &[String]) -> ShellCommandPolicy {
    if !command_is_sane(command) || !args_are_sane(args) {
        return ShellCommandPolicy::Denied;
    }

    if !SHELL_ALLOW_LIST.contains(&command) {
        return ShellCommandPolicy::AllowedNeedsApproval;
    }

    match command {
        "ls" | "pwd" | "echo" | "date" | "uname" | "whoami" | "ps" | "lsof" | "cat" | "grep"
        | "rg" | "find" | "head" | "tail" => ShellCommandPolicy::AllowedNoApproval,
        "docker" => docker_shell_policy(args),
        "git" => git_shell_policy(args),
        _ => ShellCommandPolicy::Denied,
    }
}

fn command_is_sane(command: &str) -> bool {
    let trimmed = command.trim();
    !trimmed.is_empty()
        && !trimmed.contains('\n')
        && !trimmed.contains('\r')
        && !trimmed.contains('\0')
        && trimmed.split_whitespace().count() == 1
}

fn args_are_sane(args: &[String]) -> bool {
    args.iter()
        .all(|arg| !arg.contains('\0') && !arg.contains('\n') && !arg.contains('\r'))
}

fn docker_shell_policy(args: &[String]) -> ShellCommandPolicy {
    let Some(subcommand) = args.first().map(String::as_str) else {
        return ShellCommandPolicy::Denied;
    };

    match subcommand {
        "ps" | "images" | "info" | "version" | "inspect" => ShellCommandPolicy::AllowedNoApproval,
        _ => ShellCommandPolicy::Denied,
    }
}

fn git_shell_policy(args: &[String]) -> ShellCommandPolicy {
    let Some(subcommand) = args.first().map(String::as_str) else {
        return ShellCommandPolicy::Denied;
    };

    match subcommand {
        "status" | "branch" | "log" | "diff" | "rev-parse" => ShellCommandPolicy::AllowedNoApproval,
        _ => ShellCommandPolicy::Denied,
    }
}

/// Request from the frontend.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ToolRequest {
    pub tool_id: String,
    #[serde(default)]
    pub arguments: Value,
    /// If present, the persona's allow-list. `None` means "all tools allowed".
    /// Values may contain `*` as a wildcard suffix, e.g. `"navigate.*"`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub allowed_tool_ids: Option<Vec<String>>,
    /// Frontend-generated approval token. Non-empty means the approval sheet
    /// was accepted. Semantics-wise v1 treats any non-empty string as valid;
    /// a later plan can add HMAC + single-use semantics.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub approval_token: Option<String>,
    /// Optional filesystem root override — used by tests and by the bridge to
    /// keep `files.*` scoped to the app's sandbox when we add sandboxing.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub files_root: Option<PathBuf>,
}

/// Outcome of running a tool. Serialised to the frontend as the bridge result.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum ToolOutcome {
    /// Tool completed — `payload` is a tool-specific JSON object.
    Completed { tool_id: String, payload: Value },
    /// Frontend must present the approval sheet and re-invoke with an
    /// `approval_token`.
    NeedsApproval {
        tool_id: String,
        blast_radius: ToolBlastRadius,
        prompt: String,
    },
    /// Persona gating rejected this tool.
    Denied { tool_id: String, reason: String },
    /// Everything else: unknown tool, bad args, executor failure.
    Error {
        tool_id: String,
        code: String,
        message: String,
    },
}

impl ToolOutcome {
    pub fn is_completed(&self) -> bool {
        matches!(self, ToolOutcome::Completed { .. })
    }
}

/// Lookup by id. Pure.
pub fn spec_for(tool_id: &str) -> Option<&'static ToolSpec> {
    V1_TOOL_CATALOG.iter().find(|spec| spec.id == tool_id)
}

/// Check an allow-list entry (supports the trailing-`*` wildcard).
pub fn allow_list_matches(pattern: &str, tool_id: &str) -> bool {
    if let Some(prefix) = pattern.strip_suffix('*') {
        tool_id.starts_with(prefix)
    } else {
        pattern == tool_id
    }
}

/// Whether a persona allow-list contains `tool_id`. `None` means "all allowed".
pub fn persona_allows(allow_list: Option<&[String]>, tool_id: &str) -> bool {
    match allow_list {
        None => true,
        Some(patterns) => patterns.iter().any(|p| allow_list_matches(p, tool_id)),
    }
}

/// Entrypoint. Runs the tool and returns a `ToolOutcome`. This function assumes
/// `runtime_kernel::ToolDispatcher` has already validated catalog membership,
/// persona gating, and approval. Callers must not invoke this directly for
/// `needs_approval` tools without an approval token — use the dispatcher.
pub fn run_tool(request: ToolRequest) -> ToolOutcome {
    match request.tool_id.as_str() {
        "core.read" => files_read_text(&request),
        "core.write" => files_write_text(&request),
        "core.edit" => files_edit_text(&request),
        "core.bash" => shell_run(&request),
        "core.grep" => core_grep(&request),
        "core.find" => core_find(&request),
        "core.ls" => core_ls(&request),
        "navigate.openSection" => navigate_open_section(&request),
        "navigate.openModule" => navigate_open_module(&request),
        "files.readText" => files_read_text(&request),
        "files.writeText" => files_write_text(&request),
        "shell.run" => shell_run(&request),
        "clipboard.read" => clipboard_read(&request),
        "clipboard.write" => clipboard_write(&request),
        "url.open" => url_open(&request),
        "notify.post" => notify_post(&request),
        _ => ToolOutcome::Error {
            tool_id: request.tool_id.clone(),
            code: "tool.unknown".to_string(),
            message: format!("no executor registered for tool `{}`", request.tool_id),
        },
    }
}

// ---------------------------------------------------------------------------
// Navigate tools (pure payload, no side effects)
// ---------------------------------------------------------------------------

/// Section ids recognised by `navigate.openSection`. Must stay in sync with
/// `WorkbenchSection` in `WorkbenchModels.swift`.
const KNOWN_SECTIONS: &[&str] = &[
    "home",
    "chat",
    "tasks",
    "automations",
    "apps",
    "agents",
    "settings",
];

fn navigate_open_section(request: &ToolRequest) -> ToolOutcome {
    let Some(section) = request.arguments.get("section").and_then(Value::as_str) else {
        return arg_error(
            &request.tool_id,
            "section",
            "required string `section` is missing",
        );
    };
    if !KNOWN_SECTIONS.iter().any(|known| *known == section) {
        return ToolOutcome::Error {
            tool_id: request.tool_id.clone(),
            code: "navigate.unknown_section".to_string(),
            message: format!("unknown section `{section}` (expected one of {KNOWN_SECTIONS:?})"),
        };
    }
    ToolOutcome::Completed {
        tool_id: request.tool_id.clone(),
        payload: json!({
            "intent": "navigate.section",
            "section": section,
        }),
    }
}

fn navigate_open_module(request: &ToolRequest) -> ToolOutcome {
    let Some(module_id) = request.arguments.get("module_id").and_then(Value::as_str) else {
        return arg_error(
            &request.tool_id,
            "module_id",
            "required string `module_id` is missing",
        );
    };
    if module_id.is_empty() {
        return arg_error(&request.tool_id, "module_id", "must not be empty");
    }
    ToolOutcome::Completed {
        tool_id: request.tool_id.clone(),
        payload: json!({
            "intent": "navigate.module",
            "module_id": module_id,
        }),
    }
}

// ---------------------------------------------------------------------------
// Files
// ---------------------------------------------------------------------------

const FILES_READ_MAX_DEFAULT_BYTES: usize = 1024 * 1024; // 1 MiB hard ceiling

fn files_read_text(request: &ToolRequest) -> ToolOutcome {
    let Some(path_str) = request.arguments.get("path").and_then(Value::as_str) else {
        return arg_error(
            &request.tool_id,
            "path",
            "required string `path` is missing",
        );
    };
    let resolved = match resolve_scoped_path(path_str, request.files_root.as_deref()) {
        Ok(path) => path,
        Err(err) => return err,
    };
    let max_bytes = request
        .arguments
        .get("max_bytes")
        .and_then(Value::as_u64)
        .map(|n| n as usize)
        .unwrap_or(FILES_READ_MAX_DEFAULT_BYTES);

    match fs::read(&resolved) {
        Ok(bytes) => {
            let truncated = bytes.len() > max_bytes;
            let slice = if truncated {
                &bytes[..max_bytes]
            } else {
                &bytes[..]
            };
            match std::str::from_utf8(slice) {
                Ok(text) => ToolOutcome::Completed {
                    tool_id: request.tool_id.clone(),
                    payload: json!({
                        "path": resolved.to_string_lossy(),
                        "contents": text,
                        "truncated": truncated,
                        "bytes_read": slice.len(),
                    }),
                },
                Err(err) => ToolOutcome::Error {
                    tool_id: request.tool_id.clone(),
                    code: "files.not_utf8".to_string(),
                    message: format!("file is not valid UTF-8: {err}"),
                },
            }
        }
        Err(err) => ToolOutcome::Error {
            tool_id: request.tool_id.clone(),
            code: "files.read_failed".to_string(),
            message: format!("{err}"),
        },
    }
}

fn files_write_text(request: &ToolRequest) -> ToolOutcome {
    let Some(path_str) = request.arguments.get("path").and_then(Value::as_str) else {
        return arg_error(
            &request.tool_id,
            "path",
            "required string `path` is missing",
        );
    };
    let Some(contents) = request.arguments.get("contents").and_then(Value::as_str) else {
        return arg_error(
            &request.tool_id,
            "contents",
            "required string `contents` is missing",
        );
    };
    let resolved = match resolve_scoped_path(path_str, request.files_root.as_deref()) {
        Ok(path) => path,
        Err(err) => return err,
    };
    let create_parents = request
        .arguments
        .get("create_parents")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    if create_parents {
        if let Some(parent) = resolved.parent() {
            if let Err(err) = fs::create_dir_all(parent) {
                return ToolOutcome::Error {
                    tool_id: request.tool_id.clone(),
                    code: "files.create_parents_failed".to_string(),
                    message: format!("{err}"),
                };
            }
        }
    }
    match fs::write(&resolved, contents) {
        Ok(()) => ToolOutcome::Completed {
            tool_id: request.tool_id.clone(),
            payload: json!({
                "path": resolved.to_string_lossy(),
                "bytes_written": contents.len(),
            }),
        },
        Err(err) => ToolOutcome::Error {
            tool_id: request.tool_id.clone(),
            code: "files.write_failed".to_string(),
            message: format!("{err}"),
        },
    }
}

fn files_edit_text(request: &ToolRequest) -> ToolOutcome {
    let Some(path_str) = request.arguments.get("path").and_then(Value::as_str) else {
        return arg_error(
            &request.tool_id,
            "path",
            "required string `path` is missing",
        );
    };
    let Some(old_text) = request.arguments.get("old_text").and_then(Value::as_str) else {
        return arg_error(
            &request.tool_id,
            "old_text",
            "required string `old_text` is missing",
        );
    };
    let Some(new_text) = request.arguments.get("new_text").and_then(Value::as_str) else {
        return arg_error(
            &request.tool_id,
            "new_text",
            "required string `new_text` is missing",
        );
    };
    if old_text.is_empty() {
        return arg_error(&request.tool_id, "old_text", "must not be empty");
    }
    let resolved = match resolve_scoped_path(path_str, request.files_root.as_deref()) {
        Ok(path) => path,
        Err(err) => return err,
    };
    let replace_all = request
        .arguments
        .get("replace_all")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let contents = match fs::read_to_string(&resolved) {
        Ok(contents) => contents,
        Err(err) => {
            return ToolOutcome::Error {
                tool_id: request.tool_id.clone(),
                code: "files.read_failed".to_string(),
                message: format!("{err}"),
            };
        }
    };
    if !contents.contains(old_text) {
        return ToolOutcome::Error {
            tool_id: request.tool_id.clone(),
            code: "files.edit_no_match".to_string(),
            message: "old_text was not found in the target file".to_string(),
        };
    }
    let replacement_count = contents.matches(old_text).count();
    let updated = if replace_all {
        contents.replace(old_text, new_text)
    } else {
        contents.replacen(old_text, new_text, 1)
    };
    match fs::write(&resolved, updated.as_bytes()) {
        Ok(()) => ToolOutcome::Completed {
            tool_id: request.tool_id.clone(),
            payload: json!({
                "path": resolved.to_string_lossy(),
                "replace_all": replace_all,
                "matches_seen": replacement_count,
                "replacements_applied": if replace_all { replacement_count } else { 1 },
                "bytes_written": updated.len(),
            }),
        },
        Err(err) => ToolOutcome::Error {
            tool_id: request.tool_id.clone(),
            code: "files.write_failed".to_string(),
            message: format!("{err}"),
        },
    }
}

fn resolve_scoped_path(input: &str, root: Option<&Path>) -> Result<PathBuf, ToolOutcome> {
    if input.is_empty() {
        return Err(ToolOutcome::Error {
            tool_id: String::new(),
            code: "files.path_empty".to_string(),
            message: "path is empty".to_string(),
        });
    }
    let candidate = PathBuf::from(input);
    match root {
        None => Ok(candidate),
        Some(root) => {
            let abs = if candidate.is_absolute() {
                candidate.clone()
            } else {
                root.join(&candidate)
            };
            let normalised = normalise_path(&abs);
            if !normalised.starts_with(root) {
                Err(ToolOutcome::Error {
                    tool_id: String::new(),
                    code: "files.path_escapes_root".to_string(),
                    message: format!(
                        "resolved path `{}` escapes scoped root `{}`",
                        normalised.display(),
                        root.display()
                    ),
                })
            } else {
                Ok(normalised)
            }
        }
    }
}

/// Minimal path normaliser — collapses `.` and `..` components without touching
/// the filesystem, which is what we want before `starts_with` checks.
fn normalise_path(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for component in path.components() {
        match component {
            std::path::Component::ParentDir => {
                out.pop();
            }
            std::path::Component::CurDir => {}
            other => out.push(other.as_os_str()),
        }
    }
    out
}

fn core_ls(request: &ToolRequest) -> ToolOutcome {
    let path_str = request
        .arguments
        .get("path")
        .and_then(Value::as_str)
        .unwrap_or(".");
    let include_hidden = request
        .arguments
        .get("include_hidden")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let max_entries = request
        .arguments
        .get("max_entries")
        .and_then(Value::as_u64)
        .map(|value| value as usize)
        .unwrap_or(200);
    let resolved = match resolve_scoped_path(path_str, request.files_root.as_deref()) {
        Ok(path) => path,
        Err(err) => return err,
    };
    let entries = match fs::read_dir(&resolved) {
        Ok(entries) => entries,
        Err(err) => {
            return ToolOutcome::Error {
                tool_id: request.tool_id.clone(),
                code: "files.list_failed".to_string(),
                message: format!("{err}"),
            };
        }
    };
    let mut rows = Vec::new();
    for entry in entries.flatten() {
        let file_name = entry.file_name().to_string_lossy().to_string();
        if !include_hidden && file_name.starts_with('.') {
            continue;
        }
        let metadata = entry.metadata().ok();
        rows.push(json!({
            "name": file_name,
            "path": entry.path().to_string_lossy(),
            "kind": metadata
                .as_ref()
                .map(|metadata| if metadata.is_dir() { "directory" } else if metadata.is_file() { "file" } else { "other" })
                .unwrap_or("unknown"),
            "size_bytes": metadata.filter(|metadata| metadata.is_file()).map(|metadata| metadata.len()),
        }));
        if rows.len() >= max_entries {
            break;
        }
    }
    ToolOutcome::Completed {
        tool_id: request.tool_id.clone(),
        payload: json!({
            "path": resolved.to_string_lossy(),
            "entries": rows,
            "truncated": rows.len() >= max_entries,
        }),
    }
}

fn core_find(request: &ToolRequest) -> ToolOutcome {
    let path_str = request
        .arguments
        .get("path")
        .and_then(Value::as_str)
        .unwrap_or(".");
    let name_contains = request
        .arguments
        .get("name_contains")
        .and_then(Value::as_str)
        .unwrap_or("");
    let max_results = request
        .arguments
        .get("max_results")
        .and_then(Value::as_u64)
        .map(|value| value as usize)
        .unwrap_or(200);
    let resolved = match resolve_scoped_path(path_str, request.files_root.as_deref()) {
        Ok(path) => path,
        Err(err) => return err,
    };
    let mut results = Vec::new();
    collect_find_results(&resolved, name_contains, max_results, &mut results);
    ToolOutcome::Completed {
        tool_id: request.tool_id.clone(),
        payload: json!({
            "path": resolved.to_string_lossy(),
            "name_contains": name_contains,
            "matches": results,
            "truncated": results.len() >= max_results,
        }),
    }
}

fn collect_find_results(
    root: &Path,
    name_contains: &str,
    max_results: usize,
    results: &mut Vec<Value>,
) {
    if results.len() >= max_results {
        return;
    }
    let Ok(entries) = fs::read_dir(root) else {
        return;
    };
    for entry in entries.flatten() {
        if results.len() >= max_results {
            return;
        }
        let path = entry.path();
        let file_name = entry.file_name().to_string_lossy().to_string();
        if name_contains.is_empty() || file_name.contains(name_contains) {
            let metadata = entry.metadata().ok();
            results.push(json!({
                "name": file_name,
                "path": path.to_string_lossy(),
                "kind": metadata
                    .as_ref()
                    .map(|metadata| if metadata.is_dir() { "directory" } else if metadata.is_file() { "file" } else { "other" })
                    .unwrap_or("unknown"),
            }));
        }
        if path.is_dir() {
            collect_find_results(&path, name_contains, max_results, results);
        }
    }
}

fn core_grep(request: &ToolRequest) -> ToolOutcome {
    let Some(pattern) = request.arguments.get("pattern").and_then(Value::as_str) else {
        return arg_error(
            &request.tool_id,
            "pattern",
            "required string `pattern` is missing",
        );
    };
    let path_str = request
        .arguments
        .get("path")
        .and_then(Value::as_str)
        .unwrap_or(".");
    let max_matches = request
        .arguments
        .get("max_matches")
        .and_then(Value::as_u64)
        .map(|value| value as usize)
        .unwrap_or(200);
    let resolved = match resolve_scoped_path(path_str, request.files_root.as_deref()) {
        Ok(path) => path,
        Err(err) => return err,
    };
    let mut matches = Vec::new();
    collect_grep_matches(&resolved, pattern, max_matches, &mut matches);
    ToolOutcome::Completed {
        tool_id: request.tool_id.clone(),
        payload: json!({
            "path": resolved.to_string_lossy(),
            "pattern": pattern,
            "matches": matches,
            "truncated": matches.len() >= max_matches,
        }),
    }
}

fn collect_grep_matches(root: &Path, pattern: &str, max_matches: usize, matches: &mut Vec<Value>) {
    if matches.len() >= max_matches {
        return;
    }
    if root.is_file() {
        let Ok(contents) = fs::read_to_string(root) else {
            return;
        };
        for (index, line) in contents.lines().enumerate() {
            if line.contains(pattern) {
                matches.push(json!({
                    "path": root.to_string_lossy(),
                    "line_number": index + 1,
                    "line": line,
                }));
                if matches.len() >= max_matches {
                    return;
                }
            }
        }
        return;
    }
    let Ok(entries) = fs::read_dir(root) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect_grep_matches(&path, pattern, max_matches, matches);
        } else if path.is_file() {
            collect_grep_matches(&path, pattern, max_matches, matches);
        }
        if matches.len() >= max_matches {
            return;
        }
    }
}

// ---------------------------------------------------------------------------
// Shell
// ---------------------------------------------------------------------------

fn shell_run(request: &ToolRequest) -> ToolOutcome {
    let Some(command) = request.arguments.get("command").and_then(Value::as_str) else {
        return arg_error(
            &request.tool_id,
            "command",
            "required string `command` is missing",
        );
    };
    let args = shell_args(request);
    let policy = shell_command_policy(command, &args);
    if matches!(policy, ShellCommandPolicy::Denied) {
        return ToolOutcome::Error {
            tool_id: request.tool_id.clone(),
            code: "shell.command_not_allowed".to_string(),
            message: format!(
                "command `{command}` with args {args:?} is not allowed in the guarded shell lane"
            ),
        };
    }

    let approval_granted = request
        .approval_token
        .as_deref()
        .map(str::trim)
        .is_some_and(|token| !token.is_empty());
    if matches!(policy, ShellCommandPolicy::AllowedNeedsApproval) && !approval_granted {
        return ToolOutcome::Error {
            tool_id: request.tool_id.clone(),
            code: "shell.approval_missing".to_string(),
            message: format!(
                "command `{command}` with args {args:?} requires approval before execution"
            ),
        };
    }

    let cwd = request.arguments.get("cwd").and_then(Value::as_str);
    let mut process = Command::new(command);
    process
        .args(&args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    if let Some(cwd) = cwd {
        process.current_dir(cwd);
    }

    match process.output() {
        Ok(output) => ToolOutcome::Completed {
            tool_id: request.tool_id.clone(),
            payload: json!({
                "command": command,
                "args": args,
                "cwd": cwd,
                "exit_code": output.status.code(),
                "stdout": String::from_utf8_lossy(&output.stdout).to_string(),
                "stderr": String::from_utf8_lossy(&output.stderr).to_string(),
            }),
        },
        Err(err) => ToolOutcome::Error {
            tool_id: request.tool_id.clone(),
            code: "shell.spawn_failed".to_string(),
            message: format!("{err}"),
        },
    }
}

// ---------------------------------------------------------------------------
// Clipboard (macOS pbcopy/pbpaste)
// ---------------------------------------------------------------------------

fn clipboard_read(request: &ToolRequest) -> ToolOutcome {
    match Command::new("pbpaste").output() {
        Ok(output) if output.status.success() => ToolOutcome::Completed {
            tool_id: request.tool_id.clone(),
            payload: json!({
                "text": String::from_utf8_lossy(&output.stdout).to_string(),
            }),
        },
        Ok(output) => ToolOutcome::Error {
            tool_id: request.tool_id.clone(),
            code: "clipboard.read_failed".to_string(),
            message: format!(
                "pbpaste exited with {:?}: {}",
                output.status.code(),
                String::from_utf8_lossy(&output.stderr)
            ),
        },
        Err(err) => ToolOutcome::Error {
            tool_id: request.tool_id.clone(),
            code: "clipboard.spawn_failed".to_string(),
            message: format!("{err}"),
        },
    }
}

fn clipboard_write(request: &ToolRequest) -> ToolOutcome {
    let Some(text) = request.arguments.get("text").and_then(Value::as_str) else {
        return arg_error(
            &request.tool_id,
            "text",
            "required string `text` is missing",
        );
    };
    let child = Command::new("pbcopy")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn();
    let mut child = match child {
        Ok(child) => child,
        Err(err) => {
            return ToolOutcome::Error {
                tool_id: request.tool_id.clone(),
                code: "clipboard.spawn_failed".to_string(),
                message: format!("{err}"),
            };
        }
    };
    if let Some(mut stdin) = child.stdin.take() {
        if let Err(err) = stdin.write_all(text.as_bytes()) {
            let _ = child.kill();
            return ToolOutcome::Error {
                tool_id: request.tool_id.clone(),
                code: "clipboard.write_failed".to_string(),
                message: format!("{err}"),
            };
        }
    }
    match child.wait() {
        Ok(status) if status.success() => ToolOutcome::Completed {
            tool_id: request.tool_id.clone(),
            payload: json!({
                "bytes_written": text.len(),
            }),
        },
        Ok(status) => ToolOutcome::Error {
            tool_id: request.tool_id.clone(),
            code: "clipboard.write_failed".to_string(),
            message: format!("pbcopy exited with {:?}", status.code()),
        },
        Err(err) => ToolOutcome::Error {
            tool_id: request.tool_id.clone(),
            code: "clipboard.wait_failed".to_string(),
            message: format!("{err}"),
        },
    }
}

// ---------------------------------------------------------------------------
// URL open
// ---------------------------------------------------------------------------

fn url_open(request: &ToolRequest) -> ToolOutcome {
    let Some(url) = request.arguments.get("url").and_then(Value::as_str) else {
        return arg_error(&request.tool_id, "url", "required string `url` is missing");
    };
    if !(url.starts_with("http://") || url.starts_with("https://") || url.starts_with("mailto:")) {
        return ToolOutcome::Error {
            tool_id: request.tool_id.clone(),
            code: "url.scheme_not_allowed".to_string(),
            message: format!("url `{url}` must start with http://, https://, or mailto: in v1"),
        };
    }
    match Command::new("open").arg(url).status() {
        Ok(status) if status.success() => ToolOutcome::Completed {
            tool_id: request.tool_id.clone(),
            payload: json!({ "url": url }),
        },
        Ok(status) => ToolOutcome::Error {
            tool_id: request.tool_id.clone(),
            code: "url.open_failed".to_string(),
            message: format!("`open` exited with {:?}", status.code()),
        },
        Err(err) => ToolOutcome::Error {
            tool_id: request.tool_id.clone(),
            code: "url.spawn_failed".to_string(),
            message: format!("{err}"),
        },
    }
}

// ---------------------------------------------------------------------------
// Notify
// ---------------------------------------------------------------------------

fn notify_post(request: &ToolRequest) -> ToolOutcome {
    let Some(title) = request.arguments.get("title").and_then(Value::as_str) else {
        return arg_error(
            &request.tool_id,
            "title",
            "required string `title` is missing",
        );
    };
    let body = request
        .arguments
        .get("body")
        .and_then(Value::as_str)
        .unwrap_or("");
    let script = format!(
        "display notification {} with title {}",
        applescript_string_literal(body),
        applescript_string_literal(title)
    );
    match Command::new("osascript").arg("-e").arg(&script).status() {
        Ok(status) if status.success() => ToolOutcome::Completed {
            tool_id: request.tool_id.clone(),
            payload: json!({
                "title": title,
                "body": body,
            }),
        },
        Ok(status) => ToolOutcome::Error {
            tool_id: request.tool_id.clone(),
            code: "notify.osascript_failed".to_string(),
            message: format!("osascript exited with {:?}", status.code()),
        },
        Err(err) => ToolOutcome::Error {
            tool_id: request.tool_id.clone(),
            code: "notify.spawn_failed".to_string(),
            message: format!("{err}"),
        },
    }
}

/// Wraps a string for safe insertion into an AppleScript literal. AppleScript
/// uses doubled `""` to escape quotes inside a string literal, and has no
/// backslash-escape — so we only need to double-up any quote characters.
fn applescript_string_literal(input: &str) -> String {
    let escaped = input.replace('"', "\"\"");
    format!("\"{escaped}\"")
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn arg_error(tool_id: &str, field: &str, detail: &str) -> ToolOutcome {
    ToolOutcome::Error {
        tool_id: tool_id.to_string(),
        code: format!("args.{field}"),
        message: detail.to_string(),
    }
}

/// Convenience for Swift previews — emits the static catalog as JSON.
pub fn catalog_as_json() -> Value {
    let mut out: Vec<Value> = Vec::with_capacity(V1_TOOL_CATALOG.len());
    for spec in V1_TOOL_CATALOG {
        out.push(json!({
            "id": spec.id,
            "title": spec.title,
            "description": spec.description,
            "needs_approval": spec.needs_approval,
            "blast_radius": spec.blast_radius,
        }));
    }
    Value::Array(out)
}

/// Test-only helper used by the dispatcher tests in runtime-kernel to inspect
/// the spec map without re-exporting the list by reference.
#[doc(hidden)]
pub fn catalog_map() -> HashMap<&'static str, ToolSpec> {
    V1_TOOL_CATALOG
        .iter()
        .map(|spec| (spec.id, *spec))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    fn req(tool_id: &str, args: Value) -> ToolRequest {
        ToolRequest {
            tool_id: tool_id.to_string(),
            arguments: args,
            allowed_tool_ids: None,
            approval_token: None,
            files_root: None,
        }
    }

    #[test]
    fn navigate_open_section_accepts_known_sections() {
        for section in KNOWN_SECTIONS {
            let outcome = run_tool(req("navigate.openSection", json!({ "section": section })));
            match outcome {
                ToolOutcome::Completed { payload, .. } => {
                    assert_eq!(payload["section"], *section);
                    assert_eq!(payload["intent"], "navigate.section");
                }
                other => panic!("expected completion for {section}, got {other:?}"),
            }
        }
    }

    #[test]
    fn navigate_open_section_rejects_unknown() {
        let outcome = run_tool(req("navigate.openSection", json!({ "section": "xyz" })));
        match outcome {
            ToolOutcome::Error { code, .. } => assert_eq!(code, "navigate.unknown_section"),
            other => panic!("expected error, got {other:?}"),
        }
    }

    #[test]
    fn navigate_open_module_requires_non_empty_id() {
        let outcome = run_tool(req("navigate.openModule", json!({ "module_id": "" })));
        match outcome {
            ToolOutcome::Error { code, .. } => assert_eq!(code, "args.module_id"),
            other => panic!("expected arg error, got {other:?}"),
        }
    }

    #[test]
    fn files_read_and_write_roundtrip_inside_scope() {
        let dir = tempdir().unwrap();
        let root = dir.path().to_path_buf();
        let mut write_req = req(
            "files.writeText",
            json!({ "path": "notes/hello.txt", "contents": "hi", "create_parents": true }),
        );
        write_req.files_root = Some(root.clone());
        let write_outcome = run_tool(write_req);
        assert!(
            write_outcome.is_completed(),
            "write must succeed, got {write_outcome:?}"
        );

        let mut read_req = req("files.readText", json!({ "path": "notes/hello.txt" }));
        read_req.files_root = Some(root.clone());
        match run_tool(read_req) {
            ToolOutcome::Completed { payload, .. } => assert_eq!(payload["contents"], "hi"),
            other => panic!("expected read completion, got {other:?}"),
        }
    }

    #[test]
    fn files_write_refuses_to_escape_scoped_root() {
        let dir = tempdir().unwrap();
        let root = dir.path().to_path_buf();
        let mut write_req = req(
            "files.writeText",
            json!({ "path": "../escape.txt", "contents": "nope" }),
        );
        write_req.files_root = Some(root.clone());
        let outcome = run_tool(write_req);
        match outcome {
            ToolOutcome::Error { code, .. } => assert_eq!(code, "files.path_escapes_root"),
            other => panic!("expected path-escape error, got {other:?}"),
        }
    }

    #[test]
    fn shell_run_requires_approval_for_broader_shell_commands() {
        let outcome = run_tool(req(
            "shell.run",
            json!({ "command": "rm", "args": ["-rf", "/"] }),
        ));
        match outcome {
            ToolOutcome::Error { code, .. } => assert_eq!(code, "shell.approval_missing"),
            other => panic!("expected approval gating error, got {other:?}"),
        }
    }

    #[test]
    fn shell_run_executes_allow_listed_commands() {
        // `echo` is guaranteed on every Unix.
        let outcome = run_tool(req(
            "shell.run",
            json!({ "command": "echo", "args": ["gee"] }),
        ));
        match outcome {
            ToolOutcome::Completed { payload, .. } => {
                assert_eq!(payload["exit_code"], 0);
                let stdout = payload["stdout"].as_str().unwrap_or("");
                assert!(stdout.contains("gee"), "stdout was {stdout:?}");
            }
            other => panic!("expected completion, got {other:?}"),
        }
    }

    #[test]
    fn shell_run_executes_broader_command_after_approval() {
        let dir = tempdir().unwrap();
        let script_path = dir.path().join("run.sh");
        fs::write(&script_path, "#!/bin/sh\nprintf gee-approved\n").unwrap();
        let mut request = req(
            "shell.run",
            json!({
                "command": "sh",
                "args": ["./run.sh"],
                "cwd": dir.path().display().to_string(),
            }),
        );
        request.approval_token = Some("approved".to_string());

        match run_tool(request) {
            ToolOutcome::Completed { payload, .. } => {
                assert_eq!(payload["exit_code"], 0);
                assert_eq!(payload["cwd"], dir.path().display().to_string());
                assert!(
                    payload["stdout"]
                        .as_str()
                        .unwrap_or("")
                        .contains("gee-approved")
                );
            }
            other => panic!("expected approved shell execution, got {other:?}"),
        }
    }

    #[test]
    fn guarded_shell_allows_read_only_docker_listing() {
        assert!(matches!(
            shell_command_policy(
                "docker",
                &[
                    "ps".to_string(),
                    "-a".to_string(),
                    "--format".to_string(),
                    "{{.Names}}".to_string()
                ]
            ),
            ShellCommandPolicy::AllowedNoApproval
        ));
    }

    #[test]
    fn guarded_shell_allows_read_only_manifest_inspection_commands() {
        assert!(matches!(
            shell_command_policy("cat", &["Cargo.toml".to_string()]),
            ShellCommandPolicy::AllowedNoApproval
        ));
        assert!(matches!(
            shell_command_policy("grep", &["^name".to_string(), "Cargo.toml".to_string()]),
            ShellCommandPolicy::AllowedNoApproval
        ));
        assert!(matches!(
            shell_command_policy("rg", &["workspace".to_string(), "Cargo.toml".to_string()]),
            ShellCommandPolicy::AllowedNoApproval
        ));
    }

    #[test]
    fn guarded_shell_rejects_mutating_docker_commands() {
        assert!(matches!(
            shell_command_policy("docker", &["start".to_string(), "redis".to_string()]),
            ShellCommandPolicy::Denied
        ));
    }

    #[test]
    fn url_open_rejects_disallowed_schemes() {
        let outcome = run_tool(req("url.open", json!({ "url": "file:///etc/passwd" })));
        match outcome {
            ToolOutcome::Error { code, .. } => assert_eq!(code, "url.scheme_not_allowed"),
            other => panic!("expected scheme rejection, got {other:?}"),
        }
    }

    #[test]
    fn unknown_tool_returns_unknown_error() {
        let outcome = run_tool(req("what.does.this.do", json!({})));
        match outcome {
            ToolOutcome::Error { code, .. } => assert_eq!(code, "tool.unknown"),
            other => panic!("expected unknown-tool error, got {other:?}"),
        }
    }

    #[test]
    fn allow_list_supports_wildcard_suffix() {
        assert!(allow_list_matches("navigate.*", "navigate.openSection"));
        assert!(!allow_list_matches("navigate.*", "shell.run"));
        assert!(allow_list_matches("shell.run", "shell.run"));
        assert!(!allow_list_matches("shell.run", "shell.runAway"));
    }

    #[test]
    fn applescript_string_literal_escapes_quotes() {
        assert_eq!(applescript_string_literal("hello"), "\"hello\"");
        assert_eq!(
            applescript_string_literal("say \"hi\""),
            "\"say \"\"hi\"\"\""
        );
    }

    #[test]
    fn v1_catalog_contains_expected_eight_tools() {
        let ids: Vec<&str> = V1_TOOL_CATALOG.iter().map(|spec| spec.id).collect();
        let expected = vec![
            "navigate.openSection",
            "navigate.openModule",
            "files.readText",
            "files.writeText",
            "shell.run",
            "clipboard.read",
            "clipboard.write",
            "url.open",
            "notify.post",
        ];
        assert_eq!(ids, expected);
    }
}
