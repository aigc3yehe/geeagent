use std::{collections::BTreeMap, path::PathBuf, process};

use clap::{Parser, Subcommand};
use geeagent_desktop_shell_lib::{
    native_bridge_get_shell_snapshot_json, native_bridge_list_agent_profiles_json,
    native_bridge_perform_task_action_json, native_bridge_set_active_agent_profile_json,
    native_bridge_submit_quick_prompt_json, native_bridge_submit_workspace_message_json,
};
use serde::Deserialize;

#[derive(Parser, Debug)]
#[command(name = "geeagent_cli")]
#[command(about = "GeeAgent first-party local runtime CLI")]
struct Cli {
    #[arg(long)]
    config_dir: Option<PathBuf>,
    #[arg(long)]
    json: bool,
    #[command(subcommand)]
    command: CliCommand,
}

#[derive(Subcommand, Debug)]
enum CliCommand {
    Status,
    Snapshot,
    Agent {
        #[command(subcommand)]
        command: AgentCommand,
    },
    Chat {
        #[arg(required = true)]
        message: Vec<String>,
    },
    Quick {
        #[arg(required = true)]
        prompt: Vec<String>,
    },
    Task {
        #[command(subcommand)]
        command: TaskCommand,
    },
}

#[derive(Subcommand, Debug)]
enum AgentCommand {
    List,
    Current,
    Use { profile_id: String },
}

#[derive(Subcommand, Debug)]
enum TaskCommand {
    List,
    Approve { task_id: String },
    Retry { task_id: String },
}

#[derive(Debug, Deserialize)]
struct CliAgentProfile {
    id: String,
    name: String,
    tagline: String,
    source: String,
    version: String,
}

#[derive(Debug, Deserialize)]
struct CliChatRuntime {
    status: String,
    active_provider: Option<String>,
    detail: String,
}

#[derive(Debug, Deserialize)]
struct CliConversationMessage {
    role: String,
    content: String,
}

#[derive(Debug, Deserialize)]
struct CliConversation {
    title: String,
    messages: Vec<CliConversationMessage>,
}

#[derive(Debug, Deserialize)]
struct CliTask {
    task_id: String,
    title: String,
    summary: String,
    current_stage: String,
    status: String,
    approval_request_id: Option<String>,
}

#[derive(Debug, Deserialize)]
struct CliApprovalRequest {
    approval_request_id: String,
    task_id: String,
    action_title: String,
    reason: String,
}

#[derive(Debug, Deserialize)]
struct CliRequestOutcome {
    kind: String,
    detail: String,
    task_id: Option<String>,
    module_run_id: Option<String>,
}

#[derive(Debug, Deserialize)]
struct CliSnapshot {
    quick_reply: String,
    active_agent_profile: CliAgentProfile,
    chat_runtime: CliChatRuntime,
    active_conversation: CliConversation,
    tasks: Vec<CliTask>,
    approval_requests: Vec<CliApprovalRequest>,
    last_request_outcome: Option<CliRequestOutcome>,
}

fn main() {
    let cli = Cli::parse();
    let exit_code = match run(cli) {
        Ok(()) => 0,
        Err(error) => {
            eprintln!("{error}");
            1
        }
    };
    process::exit(exit_code);
}

fn run(cli: Cli) -> Result<(), String> {
    match cli.command {
        CliCommand::Status => {
            let raw = native_bridge_get_shell_snapshot_json(cli.config_dir)?;
            if cli.json {
                println!("{raw}");
                return Ok(());
            }
            let snapshot = parse_snapshot(&raw)?;
            print_status(&snapshot);
        }
        CliCommand::Snapshot => {
            let raw = native_bridge_get_shell_snapshot_json(cli.config_dir)?;
            println!("{raw}");
        }
        CliCommand::Agent { command } => match command {
            AgentCommand::List => {
                let raw_profiles = native_bridge_list_agent_profiles_json(cli.config_dir.clone())?;
                if cli.json {
                    println!("{raw_profiles}");
                    return Ok(());
                }
                let profiles = parse_profiles(&raw_profiles)?;
                let snapshot =
                    parse_snapshot(&native_bridge_get_shell_snapshot_json(cli.config_dir)?)?;
                print_agent_list(&profiles, &snapshot.active_agent_profile.id);
            }
            AgentCommand::Current => {
                let raw = native_bridge_get_shell_snapshot_json(cli.config_dir)?;
                if cli.json {
                    println!("{raw}");
                    return Ok(());
                }
                let snapshot = parse_snapshot(&raw)?;
                print_current_agent(&snapshot.active_agent_profile);
            }
            AgentCommand::Use { profile_id } => {
                let raw = native_bridge_set_active_agent_profile_json(&profile_id, cli.config_dir)?;
                if cli.json {
                    println!("{raw}");
                    return Ok(());
                }
                let snapshot = parse_snapshot(&raw)?;
                println!(
                    "Active agent switched to {} ({})",
                    snapshot.active_agent_profile.name, snapshot.active_agent_profile.id
                );
                println!("{}", snapshot.quick_reply);
            }
        },
        CliCommand::Chat { message } => {
            let message = join_words(&message, "message")?;
            let raw = native_bridge_submit_workspace_message_json(&message, cli.config_dir)?;
            if cli.json {
                println!("{raw}");
                return Ok(());
            }
            let snapshot = parse_snapshot(&raw)?;
            print_chat_result(&snapshot);
        }
        CliCommand::Quick { prompt } => {
            let prompt = join_words(&prompt, "prompt")?;
            let raw = native_bridge_submit_quick_prompt_json(&prompt, cli.config_dir)?;
            if cli.json {
                println!("{raw}");
                return Ok(());
            }
            let snapshot = parse_snapshot(&raw)?;
            print_chat_result(&snapshot);
        }
        CliCommand::Task { command } => match command {
            TaskCommand::List => {
                let raw = native_bridge_get_shell_snapshot_json(cli.config_dir)?;
                if cli.json {
                    println!("{raw}");
                    return Ok(());
                }
                let snapshot = parse_snapshot(&raw)?;
                print_tasks(&snapshot);
            }
            TaskCommand::Approve { task_id } => {
                let raw =
                    native_bridge_perform_task_action_json(&task_id, "approve", cli.config_dir)?;
                if cli.json {
                    println!("{raw}");
                    return Ok(());
                }
                let snapshot = parse_snapshot(&raw)?;
                print_task_action_result("Approved", &task_id, &snapshot);
            }
            TaskCommand::Retry { task_id } => {
                let raw =
                    native_bridge_perform_task_action_json(&task_id, "retry", cli.config_dir)?;
                if cli.json {
                    println!("{raw}");
                    return Ok(());
                }
                let snapshot = parse_snapshot(&raw)?;
                print_task_action_result("Retried", &task_id, &snapshot);
            }
        },
    }

    Ok(())
}

fn parse_snapshot(raw: &str) -> Result<CliSnapshot, String> {
    serde_json::from_str(raw).map_err(|error| format!("failed to parse snapshot JSON: {error}"))
}

fn parse_profiles(raw: &str) -> Result<Vec<CliAgentProfile>, String> {
    serde_json::from_str(raw)
        .map_err(|error| format!("failed to parse agent profiles JSON: {error}"))
}

fn join_words(words: &[String], field_name: &str) -> Result<String, String> {
    let joined = words.join(" ").trim().to_string();
    if joined.is_empty() {
        Err(format!("{field_name} cannot be empty"))
    } else {
        Ok(joined)
    }
}

fn print_status(snapshot: &CliSnapshot) {
    let active_provider = snapshot
        .chat_runtime
        .active_provider
        .as_deref()
        .unwrap_or("—");
    println!(
        "Agent: {} ({})",
        snapshot.active_agent_profile.name, snapshot.active_agent_profile.id
    );
    println!("Tagline: {}", snapshot.active_agent_profile.tagline);
    println!(
        "Chat runtime: {} via {}",
        snapshot.chat_runtime.status, active_provider
    );
    println!("Runtime detail: {}", snapshot.chat_runtime.detail);
    println!(
        "Current conversation: {}",
        snapshot.active_conversation.title
    );
    println!("Tasks: {}", summarize_task_counts(&snapshot.tasks));
    println!("Approvals waiting: {}", snapshot.approval_requests.len());
    println!("Quick reply: {}", snapshot.quick_reply);
}

fn print_agent_list(profiles: &[CliAgentProfile], active_profile_id: &str) {
    for profile in profiles {
        let marker = if profile.id == active_profile_id {
            "*"
        } else {
            " "
        };
        println!(
            "{marker} {} ({}) · {} · {}",
            profile.name, profile.id, profile.source, profile.tagline
        );
    }
}

fn print_current_agent(profile: &CliAgentProfile) {
    println!("{} ({})", profile.name, profile.id);
    println!("{}", profile.tagline);
    println!("source: {} · version: {}", profile.source, profile.version);
}

fn print_chat_result(snapshot: &CliSnapshot) {
    println!(
        "Agent: {} ({})",
        snapshot.active_agent_profile.name, snapshot.active_agent_profile.id
    );
    if let Some(reply) = latest_assistant_reply(snapshot) {
        println!();
        println!("{reply}");
    }
    println!();
    println!("Quick reply: {}", snapshot.quick_reply);
    if let Some(outcome) = &snapshot.last_request_outcome {
        println!("Outcome: {} · {}", outcome.kind, outcome.detail);
        if let Some(task_id) = &outcome.task_id {
            println!("Task: {task_id}");
        }
        if let Some(module_run_id) = &outcome.module_run_id {
            println!("Module run: {module_run_id}");
        }
    }
}

fn print_tasks(snapshot: &CliSnapshot) {
    if snapshot.tasks.is_empty() {
        println!("No tasks.");
        return;
    }

    for task in &snapshot.tasks {
        let approval_marker = if task.approval_request_id.is_some() {
            " · review"
        } else {
            ""
        };
        println!(
            "{} · {} · {}{}",
            task.task_id, task.status, task.title, approval_marker
        );
        println!("  stage: {}", task.current_stage);
        println!("  {}", task.summary);
    }

    if !snapshot.approval_requests.is_empty() {
        println!();
        println!("Open approvals:");
        for approval in &snapshot.approval_requests {
            println!(
                "{} · task {} · {}",
                approval.approval_request_id, approval.task_id, approval.action_title
            );
            println!("  {}", approval.reason);
        }
    }
}

fn print_task_action_result(action: &str, task_id: &str, snapshot: &CliSnapshot) {
    println!("{action} task {task_id}.");
    println!("{}", snapshot.quick_reply);
    if let Some(outcome) = &snapshot.last_request_outcome {
        println!("Outcome: {} · {}", outcome.kind, outcome.detail);
    }
}

fn latest_assistant_reply(snapshot: &CliSnapshot) -> Option<&str> {
    snapshot
        .active_conversation
        .messages
        .iter()
        .rev()
        .find(|message| message.role == "assistant")
        .map(|message| message.content.trim())
        .filter(|content| !content.is_empty())
}

fn summarize_task_counts(tasks: &[CliTask]) -> String {
    if tasks.is_empty() {
        return "0 total".to_string();
    }

    let mut counts = BTreeMap::<&str, usize>::new();
    for task in tasks {
        *counts.entry(task.status.as_str()).or_default() += 1;
    }

    counts
        .into_iter()
        .map(|(status, count)| format!("{count} {status}"))
        .collect::<Vec<_>>()
        .join(", ")
}
