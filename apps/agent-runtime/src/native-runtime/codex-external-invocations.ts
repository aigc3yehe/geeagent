import { randomUUID } from "node:crypto";

import { EXPORT_STANDARD } from "./codex-export.js";
import {
  loadRuntimeStore,
  persistRuntimeStore,
} from "./store/persistence.js";
import { currentTimestamp } from "./store/defaults.js";
import type {
  RuntimeExternalInvocationRecord,
  RuntimeExternalInvocationStatus,
} from "./store/types.js";

type CreateExternalInvocationInput = {
  tool: "gee_invoke_capability" | "gee_open_surface";
  capability_ref?: string;
  gear_id?: string;
  capability_id?: string;
  surface_id?: string;
  args?: Record<string, unknown>;
  caller?: Record<string, unknown>;
};

type CompleteExternalInvocationInput = {
  external_invocation_id?: unknown;
  status?: unknown;
  result?: unknown;
  artifacts?: unknown;
  warnings?: unknown;
  recovery?: unknown;
  code?: unknown;
  message?: unknown;
};

export type ExternalInvocationResult = RuntimeExternalInvocationRecord & {
  standard: string;
};

const TERMINAL_STATUSES = new Set([
  "success",
  "partial",
  "blocked",
  "failed",
  "degraded",
]);

export async function createExternalInvocation(
  configDir: string,
  input: CreateExternalInvocationInput,
): Promise<ExternalInvocationResult> {
  const store = await loadRuntimeStore(configDir);
  const now = currentTimestamp();
  const record: RuntimeExternalInvocationRecord = {
    external_invocation_id: `gee_ext_${randomUUID()}`,
    tool: input.tool,
    status: "pending",
    created_at: now,
    updated_at: now,
    caller: input.caller,
    capability_ref: input.capability_ref,
    gear_id: input.gear_id,
    capability_id: input.capability_id,
    surface_id: input.surface_id,
    args: input.args,
    fallback_attempted: false,
  };
  store.external_invocations = [record, ...(store.external_invocations ?? [])].slice(0, 200);
  await persistRuntimeStore(configDir, store);
  return withStandard(record);
}

export async function completeExternalInvocation(
  configDir: string,
  input: CompleteExternalInvocationInput,
): Promise<ExternalInvocationResult> {
  const invocationID =
    typeof input.external_invocation_id === "string" ? input.external_invocation_id.trim() : "";
  if (!invocationID) {
    throw new Error("external invocation completion requires `external_invocation_id`");
  }
  const status = normalizeCompletionStatus(input.status);
  const store = await loadRuntimeStore(configDir);
  const records = store.external_invocations ?? [];
  const index = records.findIndex((record) => record.external_invocation_id === invocationID);
  if (index < 0) {
    throw new Error(`unknown external invocation \`${invocationID}\``);
  }

  const current = records[index];
  if (isTerminalExternalInvocationStatus(current.status)) {
    return withStandard(current);
  }
  const updated: RuntimeExternalInvocationRecord = {
    ...current,
    status,
    updated_at: currentTimestamp(),
    result: input.result,
    artifacts: Array.isArray(input.artifacts) ? input.artifacts : current.artifacts,
    warnings: Array.isArray(input.warnings) ? input.warnings : current.warnings,
    recovery: input.recovery ?? current.recovery,
    error:
      status === "failed" || status === "blocked" || status === "degraded"
        ? {
            code: stringValue(input.code) ?? "gee.external_invocation.failed",
            message: stringValue(input.message) ?? "External Gee invocation failed.",
          }
        : undefined,
    fallback_attempted: false,
  };
  records[index] = updated;
  store.external_invocations = records;
  await persistRuntimeStore(configDir, store);
  return withStandard(updated);
}

export async function getExternalInvocation(
  configDir: string,
  invocationID: string,
): Promise<ExternalInvocationResult | null> {
  const store = await loadRuntimeStore(configDir);
  const record = (store.external_invocations ?? []).find(
    (item) => item.external_invocation_id === invocationID,
  );
  return record ? withStandard(record) : null;
}

export async function waitForExternalInvocation(
  configDir: string,
  invocationID: string,
  waitMs: number,
): Promise<ExternalInvocationResult | null> {
  const deadline = Date.now() + Math.max(0, Math.min(waitMs, 60_000));
  let latest = await getExternalInvocation(configDir, invocationID);
  while (latest && !isTerminalExternalInvocationStatus(latest.status) && Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 250));
    latest = await getExternalInvocation(configDir, invocationID);
  }
  return latest;
}

export function parseExternalInvocationCompletion(
  raw: string | undefined,
): CompleteExternalInvocationInput {
  if (!raw || !raw.trim()) {
    throw new Error("external invocation completion JSON is required");
  }
  const parsed = JSON.parse(raw) as unknown;
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("external invocation completion must be a JSON object");
  }
  return parsed as CompleteExternalInvocationInput;
}

export function isTerminalExternalInvocationStatus(
  status: RuntimeExternalInvocationStatus,
): boolean {
  return TERMINAL_STATUSES.has(status);
}

function normalizeCompletionStatus(value: unknown): RuntimeExternalInvocationStatus {
  if (
    value === "running" ||
    value === "success" ||
    value === "partial" ||
    value === "blocked" ||
    value === "failed" ||
    value === "degraded"
  ) {
    return value;
  }
  throw new Error("external invocation completion status must be running, success, partial, blocked, failed, or degraded");
}

function withStandard(record: RuntimeExternalInvocationRecord): ExternalInvocationResult {
  return {
    ...record,
    standard: EXPORT_STANDARD,
  };
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0 ? value : undefined;
}
