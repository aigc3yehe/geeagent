import { activeConversation, syncConversationStatuses } from "../store/conversations.js";
import { sdkRuntimeBashScope, type TerminalAccessScope } from "../store/terminal-permissions.js";
import type { RuntimeStore } from "../store/types.js";
import type { SdkTurnResult } from "../sdk-turn-runner.js";
import type { JsonRecord } from "./types.js";

function activeConversationId(store: RuntimeStore): string | null {
  return activeConversation(store).conversation_id ?? null;
}

export function runtimeRunState(
  conversationId: string | null,
  status: string,
  stopReason: string,
  detail: string,
  resumable: boolean,
  taskId: string | null,
  moduleRunId: string | null,
): JsonRecord {
  return {
    conversation_id: conversationId,
    status,
    stop_reason: stopReason,
    detail,
    resumable,
    task_id: taskId,
    module_run_id: moduleRunId,
  };
}

export function claudeSdkChatRuntimeRecord(): JsonRecord {
  return {
    status: "live",
    active_provider: "model_gateway",
    detail: "GeeAgent is ready for workspace chat and tool-assisted tasks.",
  };
}

export function claudeSdkDegradedChatRuntimeRecord(reason: string): JsonRecord {
  return {
    status: "degraded",
    active_provider: "model_gateway",
    detail: `GeeAgent could not complete the latest run. ${userFacingFailureReason(reason)}`,
  };
}

export function claudeSdkCompletedRunState(
  store: RuntimeStore,
  assistantReply: string,
): JsonRecord {
  return runtimeRunState(
    activeConversationId(store),
    "completed",
    "claude_sdk_completed",
    assistantReply.trim()
      ? summarizePrompt(assistantReply, 220)
      : "The agent runtime completed the turn.",
    false,
    null,
    null,
  );
}

export function claudeSdkFailedRunState(store: RuntimeStore, error: string): JsonRecord {
  return runtimeRunState(
    activeConversationId(store),
    "failed",
    "claude_sdk_failed",
    summarizePrompt(error, 220),
    false,
    null,
    null,
  );
}

export function claudeSdkQuickReply(assistantReply: string, stepCount: number): string {
  const summary = summarizePrompt(assistantReply, 140);
  return stepCount === 0 || summary.length === 0
    ? summary
    : `Completed ${stepCount} tool step(s). ${summary}`;
}

export function claudeSdkFailedQuickReply(reason: string): string {
  return `GeeAgent couldn’t complete that request. ${userFacingFailureReason(reason)}`;
}

export function claudeSdkFailureAssistantReply(reason: string): string {
  return `I couldn’t complete that request. ${userFacingFailureReason(reason)} I stopped without marking it complete.`;
}

export function userFacingFailureReason(reason: string): string {
  const extracted = extractProviderErrorMessage(reason);
  const source = extracted || reason;
  const lowered = source.toLowerCase();

  if (
    lowered.includes("model_unsupported_multimodal") ||
    lowered.includes("does not support image input")
  ) {
    return "The current chat model cannot read images. Switch to a vision-capable model in Settings, or resend the request without image attachments.";
  }

  if (
    lowered.includes("api key") ||
    lowered.includes("provider configuration") ||
    lowered.includes("not configured") ||
    lowered.includes("missing provider")
  ) {
    return "Chat is waiting for model provider configuration. Open Settings and add or select a working provider before retrying.";
  }

  if (
    lowered.includes("no new event") ||
    lowered.includes("timed out") ||
    lowered.includes("timeout")
  ) {
    return "The run stalled before producing a final reply. You can retry from this conversation; the incomplete run was preserved as a failure.";
  }

  if (
    lowered.includes("session is no longer alive") ||
    lowered.includes("session-lost") ||
    lowered.includes("interrupted")
  ) {
    return "The run lost its live session before it could continue. Retry from this conversation so GeeAgent can start a fresh run.";
  }

  const sanitized = sanitizeUserFacingFailureDetail(source);
  return sanitized
    ? `The run stopped before producing a final reply. ${summarizePrompt(sanitized, 180)}`
    : "The run stopped before producing a final reply.";
}

function extractProviderErrorMessage(reason: string): string | null {
  const jsonStart = reason.indexOf("{");
  if (jsonStart >= 0) {
    try {
      const parsed = JSON.parse(reason.slice(jsonStart)) as unknown;
      const message = nestedString(parsed, ["error", "message"]) ?? nestedString(parsed, ["message"]);
      if (message) {
        return message;
      }
    } catch {
      // Keep the original reason below; provider errors are not guaranteed JSON.
    }
  }

  const messageMatch = reason.match(/"message"\s*:\s*"((?:\\"|[^"])*)"/);
  if (messageMatch?.[1]) {
    return messageMatch[1].replace(/\\"/g, "\"");
  }

  return null;
}

function nestedString(value: unknown, path: string[]): string | null {
  let cursor = value;
  for (const key of path) {
    if (!isRecord(cursor)) {
      return null;
    }
    cursor = cursor[key];
  }
  return typeof cursor === "string" && cursor.trim() ? cursor.trim() : null;
}

function sanitizeUserFacingFailureDetail(reason: string): string {
  return reason
    .replace(/The SDK \+ Xenodia/gi, "GeeAgent")
    .replace(/\bSDK runtime\b/gi, "agent runtime")
    .replace(/\bSDK\b/g, "runtime")
    .replace(/\bXenodia gateway\b/gi, "model gateway")
    .replace(/\bXenodia\b/g, "model provider")
    .replace(/configured backend model\s+\S+/gi, "current chat model")
    .replace(/API Error:\s*\d+\s*/gi, "")
    .replace(/\s+/g, " ")
    .trim();
}

export function toolStepCount(turn: SdkTurnResult): number {
  return turn.tool_events.filter((event) => event.kind === "invocation").length;
}

export function assistantReplyFromTurn(turn: SdkTurnResult, fallback: string): string {
  if (turn.assistant_chunks.length > 0) {
    return turn.assistant_chunks.join("\n\n");
  }
  return turn.final_result ?? turn.failed_reason ?? fallback;
}


export function findTask(store: RuntimeStore, taskId: string): JsonRecord {
  const task = store.tasks.find(
    (candidate) => isRecord(candidate) && candidate.task_id === taskId,
  );
  if (!isRecord(task)) {
    throw new Error("task not found");
  }
  return task;
}

export function findApproval(store: RuntimeStore, approvalRequestId: string): JsonRecord {
  const approval = store.approval_requests.find(
    (candidate) =>
      isRecord(candidate) && candidate.approval_request_id === approvalRequestId,
  );
  if (!isRecord(approval)) {
    throw new Error("approval request not found");
  }
  return approval;
}

export function findModuleRunForTask(
  store: RuntimeStore,
  taskId: string,
): JsonRecord | undefined {
  return store.module_runs.find(
    (candidate) =>
      isRecord(candidate) &&
      isRecord(candidate.module_run) &&
      candidate.module_run.task_id === taskId,
  ) as JsonRecord | undefined;
}

export function moduleRunIdForTask(store: RuntimeStore, taskId: string): string | null {
  const moduleRun = findModuleRunForTask(store, taskId);
  return isRecord(moduleRun?.module_run) &&
    typeof moduleRun.module_run.module_run_id === "string"
    ? moduleRun.module_run.module_run_id
    : null;
}

export function normalizeApprovalDecision(
  decision: string,
): "allow_once" | "always_allow" | "deny" {
  switch (decision) {
    case "approve":
    case "allow_once":
      return "allow_once";
    case "always_allow":
      return "always_allow";
    case "reject":
    case "deny":
      return "deny";
    default:
      throw new Error("unsupported approval decision");
  }
}

export function normalizeTerminalScope(
  rawScope: unknown,
  context: JsonRecord,
): TerminalAccessScope {
  if (
    isRecord(rawScope) &&
    (rawScope.kind === "sdk_runtime_bash" || rawScope.kind === "sdk_bridge_bash")
  ) {
    return sdkRuntimeBashScope(
      stringField(rawScope, "command") || stringField(context, "command"),
      stringField(rawScope, "cwd") || stringField(context, "cwd"),
    );
  }
  return sdkRuntimeBashScope(
    stringField(context, "command") || "Bash tool request",
    stringField(context, "cwd"),
  );
}

export function activateConversationForTask(store: RuntimeStore, taskId: string): string | null {
  const task = findTask(store, taskId);
  const conversationId = stringField(task, "conversation_id");
  if (
    conversationId &&
    store.conversations.some((conversation) => conversation.conversation_id === conversationId)
  ) {
    store.active_conversation_id = conversationId;
    syncConversationStatuses(store);
    return conversationId;
  }
  return null;
}

export function asRecord(value: unknown): JsonRecord {
  if (!isRecord(value)) {
    throw new Error("expected record");
  }
  return value;
}

export function isRecord(value: unknown): value is JsonRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function stringField(record: unknown, field: string): string {
  if (!isRecord(record)) {
    return "";
  }
  const value = record[field];
  return typeof value === "string" ? value : "";
}

export function summarizePrompt(prompt: string, maxLength: number): string {
  const trimmed = prompt.trim().replace(/\s+/g, " ");
  if (trimmed.length <= maxLength) {
    return trimmed;
  }
  return `${trimmed.slice(0, Math.max(0, maxLength - 1))}…`;
}

export function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
