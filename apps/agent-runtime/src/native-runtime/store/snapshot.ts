import { loadChatReadiness } from "../../chat-runtime.js";
import { resolveConfigDir } from "../paths.js";
import { refreshAgentProfiles } from "./agent-profiles.js";
import { activeConversation, summarizeConversation } from "./conversations.js";
import {
  loadRuntimeStore,
  loadSecurityPreferences,
} from "./persistence.js";
import {
  profilesWithEffectiveSkills,
  skillSourcesSnapshot,
} from "./skill-sources.js";
import { loadTerminalAccessRuleRecords } from "./terminal-permissions.js";
import type { AgentProfile, RuntimeSnapshot, RuntimeStore } from "./types.js";

function activeAgentProfile(store: RuntimeStore): AgentProfile {
  return (
    store.agent_profiles.find((profile) => profile.id === store.active_agent_profile_id) ??
    store.agent_profiles[0]
  );
}

export async function snapshotFromStore(
  store: RuntimeStore,
  configDir: string,
): Promise<RuntimeSnapshot> {
  await refreshAgentProfiles(store, configDir);
  const skillSources = await skillSourcesSnapshot(
    configDir,
    store.agent_profiles.map((profile) => profile.id),
  );
  const agentProfiles = await profilesWithEffectiveSkills(
    configDir,
    store.agent_profiles,
    skillSources,
  );
  const activeProfile =
    agentProfiles.find((profile) => profile.id === store.active_agent_profile_id) ??
    agentProfiles[0] ??
    activeAgentProfile(store);
  const chatRuntime = await snapshotChatRuntime(store, configDir);
  const active = activeConversation(store);

  return {
    quick_input_hint: store.quick_input_hint,
    quick_reply: store.quick_reply,
    context_budget: store.context_budget,
    active_agent_profile: activeProfile,
    agent_profiles: agentProfiles,
    interaction_capabilities: store.interaction_capabilities,
    last_request_outcome: store.last_request_outcome,
    last_run_state: store.last_run_state,
    chat_runtime: chatRuntime,
    conversations: store.conversations.map((conversation) =>
      summarizeConversation(store, conversation),
    ),
    active_conversation: active,
    automations: store.automations,
    module_runs: store.module_runs,
    execution_sessions: store.execution_sessions,
    kernel_sessions: store.kernel_sessions,
    transcript_events: store.transcript_events,
    tasks: store.tasks,
    approval_requests: store.approval_requests,
    terminal_access_rules: await loadTerminalAccessRuleRecords(configDir),
    security_preferences: await loadSecurityPreferences(configDir),
    host_action_intents: store.host_action_intents ?? [],
    skill_sources: skillSources,
    workspace_focus: store.workspace_focus,
    workspace_runtime: store.workspace_runtime,
  };
}

export async function loadSnapshot(configDirOverride?: string): Promise<RuntimeSnapshot> {
  const configDir = resolveConfigDir(configDirOverride);
  const store = await loadRuntimeStore(configDir);
  return snapshotFromStore(store, configDir);
}

async function loadReadiness(configDir: string): Promise<Record<string, unknown>> {
  try {
    return await loadChatReadiness(configDir);
  } catch (error) {
    return {
      status: "needs_setup",
      active_provider: null,
      detail: error instanceof Error ? error.message : String(error),
    };
  }
}

async function snapshotChatRuntime(
  store: RuntimeStore,
  configDir: string,
): Promise<Record<string, unknown>> {
  if (isActiveRunState(store.last_run_state) && isRecord(store.chat_runtime)) {
    return store.chat_runtime;
  }
  return loadReadiness(configDir);
}

function isActiveRunState(value: unknown): boolean {
  if (!isRecord(value)) {
    return false;
  }
  const status = stringField(value, "status");
  return (
    status === "running" ||
    status === "queued" ||
    status === "waiting_review" ||
    status === "waiting_input"
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringField(record: Record<string, unknown>, key: string): string | null {
  const value = record[key];
  return typeof value === "string" ? value : null;
}
