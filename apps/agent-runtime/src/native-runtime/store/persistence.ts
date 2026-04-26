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
  };

  if (!store.agent_profiles.some((profile) => profile.id === store.active_agent_profile_id)) {
    const profile = store.agent_profiles[0] ?? defaultAgentProfile();
    store.agent_profiles = store.agent_profiles.length > 0 ? store.agent_profiles : [profile];
    store.active_agent_profile_id = profile.id;
  }

  if (!store.conversations.some((item) => item.conversation_id === store.active_conversation_id)) {
    store.active_conversation_id = store.conversations[0]?.conversation_id ?? "conv_01";
  }
  syncConversationStatuses(store);
  return store;
}
