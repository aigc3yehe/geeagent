import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname } from "node:path";

import { runtimeSecurityPath, runtimeStorePath } from "../paths.js";
import { defaultAgentProfile, defaultRuntimeStore } from "./defaults.js";
import { syncConversationStatuses } from "./conversations.js";
import type { RuntimeSecurityPreferences, RuntimeStore } from "./types.js";

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export async function loadRuntimeStore(configDir: string): Promise<RuntimeStore> {
  try {
    const raw = await readFile(runtimeStorePath(configDir), "utf8");
    return normalizeRuntimeStore(JSON.parse(raw));
  } catch (error) {
    if (isMissingFileError(error)) {
      return defaultRuntimeStore();
    }
    throw new Error(
      `failed to load runtime store at ${runtimeStorePath(configDir)}: ${errorMessage(error)}`,
    );
  }
}

function isMissingFileError(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    (error as { code?: unknown }).code === "ENOENT"
  );
}

function errorMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }
  return String(error);
}

export async function persistRuntimeStore(
  configDir: string,
  store: RuntimeStore,
): Promise<void> {
  const path = runtimeStorePath(configDir);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify(store, null, 2)}\n`, "utf8");
}

export async function loadSecurityPreferences(
  configDir: string,
): Promise<RuntimeSecurityPreferences> {
  try {
    const raw = await readFile(runtimeSecurityPath(configDir), "utf8");
    const parsed = JSON.parse(raw) as Partial<RuntimeSecurityPreferences>;
    return {
      highest_authorization_enabled: parsed.highest_authorization_enabled === true,
    };
  } catch {
    return { highest_authorization_enabled: false };
  }
}

export async function persistSecurityPreferences(
  configDir: string,
  preferences: RuntimeSecurityPreferences,
): Promise<void> {
  const path = runtimeSecurityPath(configDir);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify(preferences, null, 2)}\n`, "utf8");
}

function normalizeRuntimeStore(value: unknown): RuntimeStore {
  const fallback = defaultRuntimeStore();
  if (!isRecord(value)) {
    return fallback;
  }

  const activeProfileId =
    typeof value.active_agent_profile_id === "string"
      ? value.active_agent_profile_id
      : fallback.active_agent_profile_id;
  const agentProfiles = Array.isArray(value.agent_profiles)
    ? value.agent_profiles
    : fallback.agent_profiles;
  const conversations = Array.isArray(value.conversations)
    ? value.conversations
    : fallback.conversations;

  const store: RuntimeStore = {
    ...fallback,
    ...value,
    agent_profiles: agentProfiles as RuntimeStore["agent_profiles"],
    active_agent_profile_id: activeProfileId,
    conversations: conversations as RuntimeStore["conversations"],
    active_conversation_id:
      typeof value.active_conversation_id === "string"
        ? value.active_conversation_id
        : fallback.active_conversation_id,
    host_action_intents: Array.isArray(value.host_action_intents)
      ? (value.host_action_intents as RuntimeStore["host_action_intents"])
      : fallback.host_action_intents,
    host_action_runs: Array.isArray(value.host_action_runs)
      ? (value.host_action_runs as RuntimeStore["host_action_runs"])
      : fallback.host_action_runs,
  };

  if (!store.agent_profiles.some((profile) => profile.id === store.active_agent_profile_id)) {
    const profile = store.agent_profiles[0] ?? defaultAgentProfile();
    store.agent_profiles = store.agent_profiles.length > 0 ? store.agent_profiles : [profile];
    store.active_agent_profile_id = profile.id;
  }

  if (!store.conversations.some((item) => item.conversation_id === store.active_conversation_id)) {
    store.active_conversation_id = store.conversations[0]?.conversation_id ?? "conv_01";
  }
  pruneOrphanConversationRuntimeHistory(store);
  syncConversationStatuses(store);
  return store;
}

function pruneOrphanConversationRuntimeHistory(store: RuntimeStore): void {
  const conversationIds = new Set(
    store.conversations
      .map((conversation) => conversation.conversation_id)
      .filter((conversationId): conversationId is string => typeof conversationId === "string"),
  );
  store.execution_sessions = store.execution_sessions.filter((session) => {
    if (!isRecord(session)) {
      return true;
    }
    const conversationId = session.conversation_id;
    return typeof conversationId !== "string" || conversationIds.has(conversationId);
  });

  const sessionIds = new Set(
    store.execution_sessions
      .map((session) => (isRecord(session) ? session.session_id : undefined))
      .filter((sessionId): sessionId is string => typeof sessionId === "string"),
  );
  store.transcript_events = store.transcript_events.filter((event) => {
    if (!isRecord(event)) {
      return true;
    }
    const sessionId = event.session_id;
    return typeof sessionId !== "string" || sessionIds.has(sessionId);
  });

  const hadHostActionRuns = (store.host_action_runs ?? []).length > 0;
  store.host_action_runs = (store.host_action_runs ?? []).filter((record) => {
    if (!isRecord(record)) {
      return true;
    }
    const conversationId = record.conversation_id;
    const sessionId = record.session_id;
    return (
      (typeof conversationId !== "string" || conversationIds.has(conversationId)) &&
      (typeof sessionId !== "string" || sessionIds.has(sessionId))
    );
  });

  const trackedHostActionIds = new Set(
    (store.host_action_runs ?? [])
      .map((record) => record.host_action_id)
      .filter((hostActionId): hostActionId is string => typeof hostActionId === "string"),
  );
  if (hadHostActionRuns || trackedHostActionIds.size > 0) {
    store.host_action_intents = (store.host_action_intents ?? []).filter((intent) =>
      trackedHostActionIds.has(intent.host_action_id),
    );
  }
}
