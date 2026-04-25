use serde::{Deserialize, Serialize};
use std::{
    env,
    io::{self, BufRead, Write},
    path::PathBuf,
    process,
};

use geeagent_desktop_shell_lib::{
    native_bridge_create_workspace_conversation_json, native_bridge_delete_agent_profile_json,
    native_bridge_delete_terminal_access_rule_json,
    native_bridge_delete_workspace_conversation_json, native_bridge_get_chat_routing_settings_json,
    native_bridge_get_shell_snapshot_json, native_bridge_install_agent_pack_json,
    native_bridge_invoke_tool_json, native_bridge_list_agent_profiles_json,
    native_bridge_perform_task_action_json, native_bridge_reload_agent_profile_json,
    native_bridge_save_chat_routing_settings_json, native_bridge_set_active_agent_profile_json,
    native_bridge_set_active_workspace_conversation_json,
    native_bridge_set_highest_authorization_json, native_bridge_submit_quick_prompt_json,
    native_bridge_submit_workspace_message_json,
};

fn print_usage() {
    eprintln!(
        "usage: shell_runtime_bridge <command> [args] [--config-dir <path>]\n\
         commands:\n\
           snapshot\n\
           list-agent-profiles\n\
           set-active-agent-profile <profile-id>\n\
           install-agent-pack <pack-root>\n\
           reload-agent-profile <profile-id>\n\
           delete-agent-profile <profile-id>\n\
           create-conversation\n\
           set-active-conversation <conversation-id>\n\
           delete-conversation <conversation-id>\n\
           delete-terminal-access-rule <rule-id>\n\
           set-highest-authorization <true|false>\n\
           get-chat-routing-settings\n\
           save-chat-routing-settings <settings-json>\n\
           perform-task-action <task-id> <allow_once|always_allow|deny|retry>\n\
           submit-workspace-message <message>\n\
           submit-quick-prompt <prompt>\n\
           invoke-tool <tool-request-json>\n\
           serve"
    );
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ServerRequest {
    id: String,
    command: String,
    #[serde(default)]
    args: Vec<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ServerResponse {
    id: String,
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    output: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

fn parse_args(args: Vec<String>) -> Result<(String, Vec<String>, Option<PathBuf>), String> {
    let mut config_dir = None;
    let mut positional = Vec::new();
    let mut iter = args.into_iter();

    while let Some(arg) = iter.next() {
        if arg == "--config-dir" {
            let Some(path) = iter.next() else {
                return Err("--config-dir requires a path".to_string());
            };
            config_dir = Some(PathBuf::from(path));
            continue;
        }

        positional.push(arg);
    }

    let Some((command, rest)) = positional.split_first() else {
        return Err("missing command".to_string());
    };

    Ok((command.clone(), rest.to_vec(), config_dir))
}

fn parse_bool_arg(value: &str) -> Result<bool, String> {
    match value.trim().to_ascii_lowercase().as_str() {
        "true" | "1" | "yes" | "on" => Ok(true),
        "false" | "0" | "no" | "off" => Ok(false),
        _ => Err(format!("expected true or false, got `{value}`")),
    }
}

fn dispatch_command(
    command: &str,
    args: &[String],
    config_dir: Option<PathBuf>,
) -> Result<String, String> {
    match command {
        "snapshot" if args.is_empty() => native_bridge_get_shell_snapshot_json(config_dir),
        "list-agent-profiles" if args.is_empty() => {
            native_bridge_list_agent_profiles_json(config_dir)
        }
        "set-active-agent-profile" if args.len() == 1 => {
            native_bridge_set_active_agent_profile_json(&args[0], config_dir)
        }
        "install-agent-pack" if args.len() == 1 => {
            native_bridge_install_agent_pack_json(&args[0], config_dir)
        }
        "reload-agent-profile" if args.len() == 1 => {
            native_bridge_reload_agent_profile_json(&args[0], config_dir)
        }
        "delete-agent-profile" if args.len() == 1 => {
            native_bridge_delete_agent_profile_json(&args[0], config_dir)
        }
        "create-conversation" if args.is_empty() => {
            native_bridge_create_workspace_conversation_json(config_dir)
        }
        "set-active-conversation" if args.len() == 1 => {
            native_bridge_set_active_workspace_conversation_json(&args[0], config_dir)
        }
        "delete-conversation" if args.len() == 1 => {
            native_bridge_delete_workspace_conversation_json(&args[0], config_dir)
        }
        "delete-terminal-access-rule" if args.len() == 1 => {
            native_bridge_delete_terminal_access_rule_json(&args[0], config_dir)
        }
        "set-highest-authorization" if args.len() == 1 => {
            native_bridge_set_highest_authorization_json(parse_bool_arg(&args[0])?, config_dir)
        }
        "get-chat-routing-settings" if args.is_empty() => {
            native_bridge_get_chat_routing_settings_json(config_dir)
        }
        "save-chat-routing-settings" if args.len() == 1 => {
            native_bridge_save_chat_routing_settings_json(&args[0], config_dir)
        }
        "perform-task-action" if args.len() == 2 => {
            native_bridge_perform_task_action_json(&args[0], &args[1], config_dir)
        }
        "submit-workspace-message" if args.len() == 1 => {
            native_bridge_submit_workspace_message_json(&args[0], config_dir)
        }
        "submit-quick-prompt" if args.len() == 1 => {
            native_bridge_submit_quick_prompt_json(&args[0], config_dir)
        }
        "invoke-tool" if args.len() == 1 => native_bridge_invoke_tool_json(&args[0], config_dir),
        _ => Err("unsupported command or wrong argument count".to_string()),
    }
}

fn run_server(config_dir: Option<PathBuf>) -> Result<(), String> {
    let stdin = io::stdin();
    let mut stdout = io::stdout();

    for line in stdin.lock().lines() {
        let line = line.map_err(|error| error.to_string())?;
        if line.trim().is_empty() {
            continue;
        }

        let response = match serde_json::from_str::<ServerRequest>(&line) {
            Ok(request) => {
                match dispatch_command(&request.command, &request.args, config_dir.clone()) {
                    Ok(output) => ServerResponse {
                        id: request.id,
                        ok: true,
                        output: Some(output),
                        error: None,
                    },
                    Err(error) => ServerResponse {
                        id: request.id,
                        ok: false,
                        output: None,
                        error: Some(error),
                    },
                }
            }
            Err(error) => ServerResponse {
                id: "unknown".to_string(),
                ok: false,
                output: None,
                error: Some(format!("invalid server request JSON: {error}")),
            },
        };

        let encoded = serde_json::to_string(&response).map_err(|error| error.to_string())?;
        stdout
            .write_all(encoded.as_bytes())
            .map_err(|error| error.to_string())?;
        stdout.write_all(b"\n").map_err(|error| error.to_string())?;
        stdout.flush().map_err(|error| error.to_string())?;
    }

    Ok(())
}

fn main() {
    let raw_args = env::args().skip(1).collect::<Vec<_>>();
    let (command, args, config_dir) = match parse_args(raw_args) {
        Ok(parsed) => parsed,
        Err(error) => {
            eprintln!("{error}");
            print_usage();
            process::exit(2);
        }
    };

    if command == "serve" && args.is_empty() {
        if let Err(error) = run_server(config_dir) {
            eprintln!("{error}");
            process::exit(1);
        }
        return;
    }

    let result = dispatch_command(&command, &args, config_dir);

    match result {
        Ok(output) => {
            println!("{output}");
        }
        Err(error) => {
            eprintln!("{error}");
            process::exit(1);
        }
    }
}
