import { mkdir, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { randomUUID } from "node:crypto";

import { runtimeSecurityPath, runtimeStorePath } from "../paths.js";
import { defaultAgentProfile, defaultRuntimeStore } from "./defaults.js";
import { syncConversationStatuses } from "./conversations.js";
import type {
  RuntimeExternalInvocationRecord,
  RuntimeExternalInvocationStatus,
  RuntimeSecurityPreferences,
  RuntimeStore,
} from "./types.js";

const RUNTIME_STORE_WRITE_LOCK_TIMEOUT_MS = 10_000;
const RUNTIME_STORE_WRITE_LOCK_STALE_MS = 30_000;
const EXTERNAL_INVOCATION_HISTORY_LIMIT = 200;
const TERMINAL_EXTERNAL_INVOCATION_STATUSES = new Set<RuntimeExternalInvocationStatus>([
  "success",
  "partial",
  "blocked",
  "failed",
  "degraded",
]);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export async function loadRuntimeStore(configDir: string): Promise<RuntimeStore> {
  const path = runtimeStorePath(configDir);
  let lastError: unknown;
  const attempts = [0, 25, 75];
  for (const delayMs of attempts) {
    if (delayMs > 0) {
      await sleep(delayMs);
    }
    try {
      const raw = await readFile(path, "utf8");
      return normalizeRuntimeStore(JSON.parse(raw));
    } catch (error) {
      if (isMissingFileError(error)) {
        return defaultRuntimeStore();
      }
      lastError = error;
      if (!isRetryableRuntimeStoreReadError(error)) {
        break;
      }
    }
  }

  throw new Error(
    `failed to load runtime store at ${path}: ${errorMessage(lastError)}`,
  );
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
  await withRuntimeStoreWriteLock(configDir, async () => {
    const path = runtimeStorePath(configDir);
    await mkdir(dirname(path), { recursive: true });
    const current = await loadRuntimeStore(configDir).catch((error) => {
      if (isMissingFileError(error)) {
        return defaultRuntimeStore();
      }
      throw error;
    });
    const next = mergeRuntimeStoreForPersist(store, current);
    const tempPath = `${path}.${process.pid}.${randomUUID()}.tmp`;
    try {
      await writeFile(tempPath, `${JSON.stringify(next, null, 2)}\n`, "utf8");
      await rename(tempPath, path);
    } catch (error) {
      await rm(tempPath, { force: true }).catch(() => undefined);
      throw error;
    }
  });
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
    external_invocations: Array.isArray(value.external_invocations)
      ? (value.external_invocations as RuntimeStore["external_invocations"])
      : fallback.external_invocations,
    channel_bindings: Array.isArray(value.channel_bindings)
      ? (value.channel_bindings as RuntimeStore["channel_bindings"])
      : fallback.channel_bindings,
    channel_messages: Array.isArray(value.channel_messages)
      ? (value.channel_messages as RuntimeStore["channel_messages"])
      : fallback.channel_messages,
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

function isRetryableRuntimeStoreReadError(error: unknown): boolean {
  return error instanceof SyntaxError;
}

function sleep(delayMs: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, delayMs));
}

async function withRuntimeStoreWriteLock<T>(
  configDir: string,
  operation: () => Promise<T>,
): Promise<T> {
  const storePath = runtimeStorePath(configDir);
  const lockDir = `${storePath}.lock`;
  const deadline = Date.now() + RUNTIME_STORE_WRITE_LOCK_TIMEOUT_MS;

  await mkdir(dirname(storePath), { recursive: true });

  while (true) {
    try {
      await mkdir(lockDir);
      await writeFile(
        join(lockDir, "owner"),
        JSON.stringify({
          pid: process.pid,
          created_at: new Date().toISOString(),
        }),
        "utf8",
      ).catch(() => undefined);
      try {
        return await operation();
      } finally {
        await rm(lockDir, { recursive: true, force: true }).catch(() => undefined);
      }
    } catch (error) {
      if (!isExistingFileError(error)) {
        throw error;
      }
      if (await removeStaleRuntimeStoreWriteLock(lockDir)) {
        continue;
      }
      if (Date.now() >= deadline) {
        throw new Error(
          `timed out waiting for runtime store write lock at ${lockDir}`,
        );
      }
      await sleep(25);
    }
  }
}

async function removeStaleRuntimeStoreWriteLock(lockDir: string): Promise<boolean> {
  try {
    const info = await stat(lockDir);
    if (Date.now() - info.mtimeMs <= RUNTIME_STORE_WRITE_LOCK_STALE_MS) {
      return false;
    }
    await rm(lockDir, { recursive: true, force: true });
    return true;
  } catch (error) {
    return isMissingFileError(error);
  }
}

function mergeRuntimeStoreForPersist(
  next: RuntimeStore,
  current: RuntimeStore,
): RuntimeStore {
  return {
    ...next,
    external_invocations: mergeExternalInvocationRecords(
      next.external_invocations ?? [],
      current.external_invocations ?? [],
    ),
  };
}

function mergeExternalInvocationRecords(
  nextRecords: RuntimeExternalInvocationRecord[],
  currentRecords: RuntimeExternalInvocationRecord[],
): RuntimeExternalInvocationRecord[] {
  const byID = new Map<string, RuntimeExternalInvocationRecord>();
  for (const record of [...currentRecords, ...nextRecords]) {
    const id = typeof record.external_invocation_id === "string"
      ? record.external_invocation_id
      : "";
    if (!id) {
      continue;
    }
    const existing = byID.get(id);
    byID.set(id, existing ? preferredExternalInvocationRecord(existing, record) : record);
  }
  return [...byID.values()]
    .sort((left, right) => compareExternalInvocationRecords(right, left))
    .slice(0, EXTERNAL_INVOCATION_HISTORY_LIMIT);
}

function preferredExternalInvocationRecord(
  existing: RuntimeExternalInvocationRecord,
  candidate: RuntimeExternalInvocationRecord,
): RuntimeExternalInvocationRecord {
  const existingUpdatedAt = timestampMs(existing.updated_at);
  const candidateUpdatedAt = timestampMs(candidate.updated_at);
  if (candidateUpdatedAt > existingUpdatedAt) {
    return candidate;
  }
  if (candidateUpdatedAt < existingUpdatedAt) {
    return existing;
  }
  const existingTerminal = isTerminalExternalInvocationStatus(existing.status);
  const candidateTerminal = isTerminalExternalInvocationStatus(candidate.status);
  if (candidateTerminal && !existingTerminal) {
    return candidate;
  }
  if (existingTerminal && !candidateTerminal) {
    return existing;
  }
  return candidate;
}

function compareExternalInvocationRecords(
  left: RuntimeExternalInvocationRecord,
  right: RuntimeExternalInvocationRecord,
): number {
  const createdDelta = timestampMs(left.created_at) - timestampMs(right.created_at);
  if (createdDelta !== 0) {
    return createdDelta;
  }
  return timestampMs(left.updated_at) - timestampMs(right.updated_at);
}

function timestampMs(value: string): number {
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function isTerminalExternalInvocationStatus(
  status: RuntimeExternalInvocationStatus,
): boolean {
  return TERMINAL_EXTERNAL_INVOCATION_STATUSES.has(status);
}

function isExistingFileError(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    (error as { code?: unknown }).code === "EEXIST"
  );
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
