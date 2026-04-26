export type AgentProfile = {
  id: string;
  name: string;
  tagline: string;
  personality_prompt: string;
  appearance: Record<string, unknown>;
  skills?: Array<{ id: string; path?: string }>;
  allowed_tool_ids?: string[];
  source: string;
  version: string;
  file_state?: Record<string, unknown>;
};

export type RuntimeConversationMessage = {
  message_id: string;
  role: "assistant" | "user" | string;
  content: string;
  timestamp: string;
};

export type RuntimeConversation = {
  conversation_id: string;
  title: string;
  status: string;
  messages: RuntimeConversationMessage[];
};

export type RuntimeConversationSummary = {
  conversation_id: string;
  title: string;
  status: string;
  last_message_preview: string;
  last_timestamp: string;
  is_active: boolean;
};

export type RuntimeStore = {
  quick_input_hint: string;
  quick_reply: string;
  context_budget: Record<string, unknown>;
  agent_profiles: AgentProfile[];
  active_agent_profile_id: string;
  interaction_capabilities: Record<string, unknown>;
  last_request_outcome: Record<string, unknown> | null;
  last_run_state: Record<string, unknown> | null;
  chat_runtime: Record<string, unknown>;
  conversations: RuntimeConversation[];
  active_conversation_id: string;
  automations: unknown[];
  module_runs: unknown[];
  execution_sessions: unknown[];
  kernel_sessions: unknown[];
  transcript_events: unknown[];
  tasks: unknown[];
  approval_requests: unknown[];
  workspace_focus: Record<string, unknown>;
  workspace_runtime: Record<string, unknown>;
};

export type RuntimeSecurityPreferences = {
  highest_authorization_enabled: boolean;
};

export type RuntimeSnapshot = Omit<
  RuntimeStore,
  "active_agent_profile_id" | "active_conversation_id" | "conversations"
> & {
  active_agent_profile: AgentProfile;
  conversations: RuntimeConversationSummary[];
  active_conversation: RuntimeConversation;
  terminal_access_rules: unknown[];
  security_preferences: RuntimeSecurityPreferences;
};
