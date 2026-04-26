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
    active_provider: "sdk/xenodia",
    detail: "The SDK is driving the agent loop through the local Xenodia model gateway.",
  };
}

export function claudeSdkDegradedChatRuntimeRecord(reason: string): JsonRecord {
  return {
    status: "degraded",
    active_provider: "sdk/xenodia",
    detail: `The SDK through the Xenodia gateway degraded during this turn. ${summarizePrompt(reason, 220)}`,
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
      : "The SDK runtime completed the turn.",
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
  return `The SDK + Xenodia could not complete this run. ${summarizePrompt(reason, 180)}`;
}

export function claudeSdkFailureAssistantReply(reason: string): string {
  return `The SDK + Xenodia did not complete this run successfully: ${summarizePrompt(reason, 220)}. I did not present it as completed.`;
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
