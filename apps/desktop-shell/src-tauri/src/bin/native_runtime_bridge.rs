use std::path::PathBuf;

use geeagent_desktop_shell_lib::{
    native_bridge_create_workspace_conversation_json, native_bridge_get_shell_snapshot_json,
    native_bridge_perform_task_action_json, native_bridge_set_active_workspace_conversation_json,
    native_bridge_submit_workspace_message_json,
};

fn usage() -> &'static str {
    "usage: native_runtime_bridge <get-snapshot|create-conversation|set-active-conversation|perform-task-action|submit-workspace-message> [args]"
}

fn take_flag_value(args: &[String], flag: &str) -> Option<String> {
    args.windows(2)
        .find(|window| window[0] == flag)
        .map(|window| window[1].clone())
}

fn config_dir_override(args: &[String]) -> Option<PathBuf> {
    take_flag_value(args, "--config-dir").map(PathBuf::from)
}

fn required_flag(args: &[String], flag: &str) -> Result<String, String> {
    take_flag_value(args, flag).ok_or_else(|| format!("missing required flag `{flag}`"))
}

fn print_result(result: Result<String, String>) -> i32 {
    match result {
        Ok(payload) => {
            println!("{payload}");
            0
        }
        Err(error) => {
            eprintln!("{error}");
            1
        }
    }
}

fn main() {
    let args = std::env::args().skip(1).collect::<Vec<_>>();
    let Some(command) = args.first().cloned() else {
        eprintln!("{}", usage());
        std::process::exit(2);
    };

    let exit_code = match command.as_str() {
        "get-snapshot" => print_result(native_bridge_get_shell_snapshot_json(config_dir_override(
            &args,
        ))),
        "create-conversation" => print_result(native_bridge_create_workspace_conversation_json(
            config_dir_override(&args),
        )),
        "set-active-conversation" => {
            let conversation_id = required_flag(&args, "--conversation-id");
            match conversation_id {
                Ok(conversation_id) => {
                    print_result(native_bridge_set_active_workspace_conversation_json(
                        &conversation_id,
                        config_dir_override(&args),
                    ))
                }
                Err(error) => {
                    eprintln!("{error}");
                    2
                }
            }
        }
        "perform-task-action" => {
            let task_id = required_flag(&args, "--task-id");
            let action = required_flag(&args, "--action");
            match (task_id, action) {
                (Ok(task_id), Ok(action)) => print_result(native_bridge_perform_task_action_json(
                    &task_id,
                    &action,
                    config_dir_override(&args),
                )),
                (Err(error), _) | (_, Err(error)) => {
                    eprintln!("{error}");
                    2
                }
            }
        }
        "submit-workspace-message" => {
            let message = required_flag(&args, "--message");
            match message {
                Ok(message) => print_result(tauri::async_runtime::block_on(
                    native_bridge_submit_workspace_message_json(
                        &message,
                        config_dir_override(&args),
                    ),
                )),
                Err(error) => {
                    eprintln!("{error}");
                    2
                }
            }
        }
        _ => {
            eprintln!("{}", usage());
            2
        }
    };

    std::process::exit(exit_code);
}
