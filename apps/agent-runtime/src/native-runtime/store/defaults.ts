import type { AgentProfile, RuntimeStore } from "./types.js";

export function currentTimestamp(): string {
  return new Date().toISOString();
}

export function defaultAgentProfile(): AgentProfile {
  return {
    id: "gee",
    name: "Gee",
    tagline: "Local-first workbench operator",
    personality_prompt:
      "You are Gee, a calm and capable local-first workbench operator who helps the user move work forward without hiding complexity.",
    appearance: { kind: "abstract" },
    skills: [{ id: "workspace.chat" }, { id: "workspace.tasks" }],
    source: "first_party",
    version: "1.0.0",
    file_state: {
      visual_files: [],
      supplemental_files: [],
      can_reload: false,
      can_delete: false,
    },
  };
}

export function defaultRuntimeStore(now = currentTimestamp()): RuntimeStore {
  const profile = defaultAgentProfile();
  return {
    quick_input_hint:
      "Ask GeeAgent to review a draft, check your queue, or run a task.",
    quick_reply:
      "GeeAgent is standing by. Use quick input or the workspace chat to start a task.",
    context_budget: {
      max_tokens: 256000,
      used_tokens: 35,
      reserved_output_tokens: 8192,
      usage_ratio: 0.00013671875,
      estimate_source: "estimated",
      summary_state: "watching",
      next_summary_at_ratio: 0.95,
      compacted_messages_count: 0,
    },
    agent_profiles: [profile],
    active_agent_profile_id: profile.id,
    interaction_capabilities: {
      surface: "desktop_live",
      can_send_messages: true,
      can_use_quick_input: true,
      can_mutate_runtime: true,
      can_run_first_party_actions: true,
      read_only_reason: null,
    },
    last_request_outcome: null,
    last_run_state: null,
    chat_runtime: {
      status: "needs_setup",
      active_provider: null,
      detail: "Live chat is waiting for provider configuration.",
    },
    conversations: [
      {
        conversation_id: "conv_01",
        title: "New Conversation",
        status: "active",
        tags: [],
        messages: [
          {
            message_id: "msg_assistant_01",
            role: "assistant",
            content:
              "New conversation ready. Tell GeeAgent what to do next, or use quick input for a lighter command.",
            timestamp: now,
          },
        ],
      },
    ],
    active_conversation_id: "conv_01",
    automations: [],
    module_runs: [],
    execution_sessions: [],
    kernel_sessions: [],
    transcript_events: [],
    tasks: [],
    approval_requests: [],
    workspace_focus: { mode: "default", task_id: null },
    workspace_runtime: {
      active_section: "home",
      sections: ["home", "chat", "tasks", "automations", "apps", "settings"],
      apps: [
        {
          app_id: "media.library",
          display_name: "Media Library",
          install_state: "installed",
          display_mode: "full_canvas",
        },
      ],
      agent_skins: [{ skin_id: "default.operator", display_name: "Default Operator" }],
    },
    host_action_intents: [],
  };
}
