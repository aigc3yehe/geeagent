import {
  persistRuntimeStore,
} from "../store/persistence.js";
import {
  terminalAccessLabelForScope,
  upsertTerminalAccessRule,
  type TerminalAccessDecision,
} from "../store/terminal-permissions.js";
import type { RuntimeStore } from "../store/types.js";
import {
  resumeSdkRuntimeApproval,
  type PendingTerminalApproval,
  type SdkTurnResult,
  type TurnRoute,
} from "../sdk-turn-runner.js";
import {
  appendAssistantMessageForActiveConversation,
  appendSessionStateForSession,
  appendToolEvents,
  appendToolResultForExistingInvocation,
  appendTranscriptEvent,
  appendTurnStep,
  beginTurnReplay,
  ensureExecutionSessionForActiveConversation,
  executionSessionIdForConversation,
  finalizeTurnReplay,
  nextApprovalRequestIdForTask,
  quickModuleRunId,
  quickTaskId,
} from "./events.js";
import {
  activateConversationForTask,
  asRecord,
  assistantReplyFromTurn,
  claudeSdkChatRuntimeRecord,
  claudeSdkDegradedChatRuntimeRecord,
  claudeSdkFailedQuickReply,
  claudeSdkFailureAssistantReply,
  claudeSdkQuickReply,
  errorMessage,
  findApproval,
  findModuleRunForTask,
  findTask,
  moduleRunIdForTask,
  normalizeApprovalDecision,
  normalizeTerminalScope,
  runtimeRunState,
  stringField,
  summarizePrompt,
  toolStepCount,
  isRecord,
} from "./state.js";
import type { JsonRecord, TurnReplayCursor } from "./types.js";

export function installClaudeSdkTerminalApproval(
  store: RuntimeStore,
  route: TurnRoute,
  userContent: string,
  pending: PendingTerminalApproval,
  options: { cursor?: TurnReplayCursor } = {},
): string {
  const taskId = quickTaskId(store);
  const approvalRequestId = nextApprovalRequestIdForTask(store, taskId);
  const moduleRunId = quickModuleRunId(store);
  const conversationId = store.active_conversation_id;
  const commandSummary = pending.input_summary ?? summarizePrompt(pending.command, 160);
  const taskTitle = `Terminal approval: ${summarizePrompt(pending.command, 44)}`;
  const approvalDetail = `Terminal approval required: ${commandSummary}`;

  const cursor = options.cursor ?? beginTurnReplay(store, route.surface, userContent);
  appendTurnStep(
    cursor,
    store,
    "delegating this turn into the SDK loop through the Xenodia gateway so the agent can reason and request host-reviewed tools",
  );
  appendTurnStep(
    cursor,
    store,
    "the SDK loop requested terminal access that GeeAgent has not seen before, so the host stopped for an explicit review choice",
  );
  appendTranscriptEvent(store, cursor.sessionId, {
    kind: "tool_invocation",
    invocation: {
      invocation_id: `toolinv_${approvalRequestId}`,
      session_id: cursor.sessionId,
      originating_message_id: cursor.userMessageId,
      tool_name: "Bash",
      input_summary: pending.input_summary ?? null,
      status: "running",
      approval_request_id: approvalRequestId,
      created_at: "now",
      updated_at: "now",
    },
  });
  finalizeTurnReplay(
    store,
    cursor,
    "the SDK loop paused because GeeAgent requires an explicit terminal permission decision before Bash can continue",
  );

  store.tasks.unshift({
    task_id: taskId,
    conversation_id: conversationId,
    title: taskTitle,
    summary: `Waiting for terminal review: ${commandSummary}`,
    current_stage: "review_pending",
    status: "waiting_review",
    importance_level: "important",
    progress_percent: 64,
    artifact_count: 0,
    approval_request_id: approvalRequestId,
  });
  store.module_runs.unshift({
    module_run: {
      module_run_id: moduleRunId,
      task_id: taskId,
      module_id: "geeagent.runtime.sdk",
      capability_id: "terminal_permission_review",
      status: "waiting_review",
      stage: "review_pending",
      attempt_count: 1,
      result_summary: `Paused for terminal review before Bash can run: ${commandSummary}`,
      artifacts: [],
      created_at: "now",
      updated_at: "now",
    },
    recoverability: {
      retry_safe: false,
      resume_supported: true,
      hint: "Review this terminal request to let the SDK loop continue.",
    },
  });
  store.approval_requests.unshift({
    approval_request_id: approvalRequestId,
    run_id: cursor.runId,
    task_id: taskId,
    action_title: `Review terminal access: ${summarizePrompt(pending.command, 72)}`,
    reason: "This terminal command needs your approval before GeeAgent runs it.",
    risk_tags: ["terminal", "shell", "permission"],
    review_required: true,
    status: "open",
    parameters: [
      { label: "Command", value: pending.command },
      ...(pending.cwd ? [{ label: "Working directory", value: pending.cwd }] : []),
    ],
    machine_context: {
      kind: "sdk_runtime_terminal",
      source: route.source,
      surface: route.surface,
      user_prompt: userContent,
      run_id: cursor.runId,
      runtime_session_id: pending.runtime_session_id,
      runtime_request_id: pending.runtime_request_id,
      scope: pending.scope,
      command: pending.command,
      cwd: pending.cwd ?? null,
    },
  });

  store.workspace_focus = { mode: "task", task_id: taskId };
  store.quick_reply = "Terminal review needed before Bash can continue.";
  store.chat_runtime = claudeSdkChatRuntimeRecord();
  store.last_run_state = runtimeRunState(
    conversationId,
    "waiting_review",
    "terminal_permission_review_required",
    "GeeAgent paused the SDK run because this terminal access has no stored permission.",
    true,
    taskId,
    moduleRunId,
  );
  store.last_request_outcome = {
    source: route.source,
    kind: "task_handoff",
    detail: approvalDetail,
    task_id: taskId,
    module_run_id: null,
  };
  return taskId;
}

export function applyClaudeSdkTerminalDenial(
  store: RuntimeStore,
  route: TurnRoute,
  userContent: string,
  reason: string,
  options: { cursor?: TurnReplayCursor } = {},
): void {
  const assistantReply =
    `This terminal access request was not executed. GeeAgent's terminal permission file blocked it: ${summarizePrompt(reason, 220)}.`;
  const cursor = options.cursor ?? beginTurnReplay(store, route.surface, userContent);
  appendTurnStep(
    cursor,
    store,
    "delegating this turn into the SDK loop through the Xenodia gateway so the agent can reason about the request",
  );
  appendTurnStep(
    cursor,
    store,
    "the host matched the requested Bash access against GeeAgent's terminal permission file and blocked it before execution",
  );
  appendAssistantMessageForActiveConversation(store, cursor.sessionId, assistantReply);
  finalizeTurnReplay(
    store,
    cursor,
    "the SDK loop hit a terminal permission deny rule and GeeAgent stopped the turn without executing Bash",
  );
  store.quick_reply = `Terminal access denied by Gee permissions. ${summarizePrompt(reason, 120)}`;
  store.chat_runtime = claudeSdkChatRuntimeRecord();
  store.last_run_state = runtimeRunState(
    store.active_conversation_id,
    "waiting_input",
    "terminal_permission_denied",
    summarizePrompt(reason, 220),
    true,
    null,
    null,
  );
  store.last_request_outcome = {
    source: route.source,
    kind: "clarify_needed",
    detail: assistantReply,
    task_id: null,
    module_run_id: null,
  };
}

export async function resolveApproval(
  store: RuntimeStore,
  configDir: string,
  approvalRequestId: string,
  decision: string,
): Promise<void> {
  const normalizedDecision = normalizeApprovalDecision(decision);
  const approval = findApproval(store, approvalRequestId);
  if (approval.status !== "open") {
    throw new Error("approval request is not open");
  }
  approval.status =
    normalizedDecision === "deny" ? "rejected" : "approved";
  const taskId = stringField(approval, "task_id");
  const machineContext = isRecord(approval.machine_context)
    ? approval.machine_context
    : undefined;

  if (isSdkRuntimeTerminalContext(machineContext)) {
    const scope = normalizeTerminalScope(machineContext.scope, machineContext);
    if (normalizedDecision === "always_allow") {
      await upsertTerminalAccessRule(
        configDir,
        scope,
        "allow",
        terminalAccessLabelForScope(scope),
      );
    } else if (normalizedDecision === "deny") {
      await upsertTerminalAccessRule(
        configDir,
        scope,
        "deny",
        terminalAccessLabelForScope(scope),
      );
    }
    markSdkRuntimeApprovalResumeStarted(
      store,
      approvalRequestId,
      taskId,
      machineContext,
      normalizedDecision === "deny" ? "deny" : "allow",
    );
    await persistRuntimeStore(configDir, store);
    await resolveSdkRuntimeTerminalApproval(
      store,
      approvalRequestId,
      taskId,
      machineContext,
      normalizedDecision === "deny" ? "deny" : "allow",
    );
    return;
  }

  resolveGenericApproval(store, approvalRequestId, taskId, normalizedDecision);
}

function markSdkRuntimeApprovalResumeStarted(
  store: RuntimeStore,
  approvalRequestId: string,
  taskId: string,
  machineContext: JsonRecord,
  decision: TerminalAccessDecision,
): void {
  activateConversationForTask(store, taskId);
  const command = stringField(machineContext, "command") || "Bash tool request";
  const task = findTask(store, taskId);
  task.approval_request_id = null;
  task.current_stage = decision === "deny" ? "denial_resuming" : "approval_resuming";
  task.status = "running";
  task.progress_percent = Math.max(Number(task.progress_percent) || 0, 76);
  task.summary =
    decision === "deny"
      ? `Terminal access denied. GeeAgent is returning that decision to the paused SDK run: ${summarizePrompt(command, 160)}`
      : `Terminal access approved. GeeAgent is resuming the paused SDK run: ${summarizePrompt(command, 160)}`;

  const moduleRun = findModuleRunForTask(store, taskId);
  if (moduleRun) {
    const module = asRecord(moduleRun.module_run);
    module.status = "running";
    module.stage = task.current_stage;
    module.result_summary = task.summary;
    module.updated_at = "now";
  }

  const sessionId = ensureExecutionSessionForActiveConversation(store, "cli_workspace_chat");
  appendSessionStateForSession(
    store,
    sessionId,
    decision === "deny"
      ? `terminal access denied, sending the deny decision back into the paused SDK run: ${summarizePrompt(command, 120)}`
      : `terminal access approved, resuming the paused SDK run: ${summarizePrompt(command, 120)}`,
  );

  const detail =
    decision === "deny"
      ? "Terminal access denied. GeeAgent is returning that decision to the paused run."
      : "Terminal access approved. GeeAgent is resuming the paused run.";
  store.workspace_focus = { mode: "task", task_id: taskId };
  store.quick_reply = detail;
  store.last_run_state = runtimeRunState(
    store.active_conversation_id,
    "running",
    decision === "deny" ? "terminal_denial_resume_in_progress" : "terminal_approval_resume_in_progress",
    detail,
    true,
    taskId,
    moduleRunIdForTask(store, taskId),
  );
  store.last_request_outcome = {
    source: "workspace_chat",
    kind: "task_handoff",
    detail,
    task_id: taskId,
    module_run_id: moduleRunIdForTask(store, taskId),
  };
}

async function resolveSdkRuntimeTerminalApproval(
  store: RuntimeStore,
  approvalRequestId: string,
  taskId: string,
  machineContext: JsonRecord,
  decision: TerminalAccessDecision,
): Promise<void> {
  activateConversationForTask(store, taskId);
  const source = stringField(machineContext, "source") || "workspace_chat";
  const surface = stringField(machineContext, "surface") || "cli_workspace_chat";
  const route: TurnRoute = {
    mode: source === "quick_input" ? "quick_prompt" : "workspace_message",
    source: source === "quick_input" ? "quick_input" : "workspace_chat",
    surface: surface === "cli_quick_input" ? "cli_quick_input" : "cli_workspace_chat",
  };
  const command = stringField(machineContext, "command") || "Bash tool request";

  let sdkTurn: SdkTurnResult;
  try {
    sdkTurn = await resumeSdkRuntimeApproval(
      runtimeSessionIdFromContext(machineContext),
      runtimeRequestIdFromContext(machineContext),
      decision,
    );
  } catch (error) {
    const reason = errorMessage(error);
    sdkTurn =
      decision === "allow"
        ? {
            assistant_chunks: [],
            tool_events: [],
            auto_approved_tools: 0,
            failed_reason: reason,
          }
        : {
            assistant_chunks: [],
            tool_events: [],
            auto_approved_tools: 0,
          };
  }

  if (sdkTurn.pending_terminal_approval) {
    const sessionId = executionSessionIdForConversation(store.active_conversation_id);
    appendToolResultForExistingInvocation(
      store,
      sessionId,
      `toolinv_${approvalRequestId}`,
      "succeeded",
    );
    installFollowUpClaudeSdkTerminalApproval(
      store,
      route,
      taskId,
      stringField(machineContext, "user_prompt") || "",
      sdkTurn.pending_terminal_approval,
    );
    return;
  }

  if (decision === "deny") {
    sdkTurn.assistant_chunks = [
      `This terminal access request was not executed. GeeAgent blocked it based on your choice: ${summarizePrompt(command, 220)}.`,
    ];
  } else if (sdkTurn.terminal_access_denied_reason) {
    sdkTurn.assistant_chunks = [
      `This terminal access request was not executed. GeeAgent's terminal permission file blocked it: ${summarizePrompt(sdkTurn.terminal_access_denied_reason, 220)}.`,
    ];
  } else if (sdkTurn.failed_reason) {
    sdkTurn.assistant_chunks = [
      claudeSdkFailureAssistantReply(sdkTurn.failed_reason),
    ];
  }

  const assistantReply = assistantReplyFromTurn(
    sdkTurn,
    "The SDK completed the resumed run without a text summary.",
  );
  appendClaudeSdkRuntimeFollowUp(
    store,
    route.surface,
    decision === "deny"
      ? `terminal access denied, resuming the paused SDK run with a deny decision: ${summarizePrompt(command, 120)}`
      : sdkTurn.failed_reason
        ? "approval granted, resuming the paused SDK run and committing the failed result truthfully"
        : `approval granted, resuming the paused SDK run with terminal access allowed: ${summarizePrompt(command, 120)}`,
    sdkTurn,
    assistantReply,
    decision === "deny"
      ? "the paused SDK run received the terminal denial and GeeAgent committed the blocked result back into the active conversation"
      : sdkTurn.failed_reason
        ? "the resumed SDK run failed after terminal approval, and GeeAgent committed that failed result back into the active conversation"
        : "the same SDK run continued after the terminal approval decision and GeeAgent committed the resulting tool trace back into the active conversation",
  );

  const summary = sdkTurn.failed_reason
    ? sdkTurn.failed_reason
    : sdkTurn.terminal_access_denied_reason
      ? sdkTurn.terminal_access_denied_reason
      : summarizePrompt(assistantReply, 180);
  const finalFailed = decision === "deny" || Boolean(sdkTurn.failed_reason);
  appendToolResultForExistingInvocation(
    store,
    executionSessionIdForConversation(store.active_conversation_id),
    `toolinv_${approvalRequestId}`,
    finalFailed ? "failed" : "succeeded",
    undefined,
    finalFailed ? summary : undefined,
  );
  updateTaskAfterSdkApproval(store, taskId, decision, sdkTurn, summary);
}

function installFollowUpClaudeSdkTerminalApproval(
  store: RuntimeStore,
  route: TurnRoute,
  taskId: string,
  userContent: string,
  pending: PendingTerminalApproval,
): void {
  activateConversationForTask(store, taskId);
  const approvalRequestId = nextApprovalRequestIdForTask(store, taskId);
  const commandSummary = pending.input_summary ?? summarizePrompt(pending.command, 160);
  const sessionId = ensureExecutionSessionForActiveConversation(store, route.surface);
  appendSessionStateForSession(
    store,
    sessionId,
    `the SDK run needs another terminal review before it can continue: ${summarizePrompt(pending.command, 140)}`,
  );
  appendTranscriptEvent(store, sessionId, {
    kind: "tool_invocation",
    invocation: {
      invocation_id: `toolinv_${approvalRequestId}`,
      session_id: sessionId,
      originating_message_id: `approval_follow_up_${approvalRequestId}`,
      tool_name: "Bash",
      input_summary: pending.input_summary ?? null,
      status: "running",
      approval_request_id: approvalRequestId,
      created_at: "now",
      updated_at: "now",
    },
  });
  store.approval_requests.unshift({
    approval_request_id: approvalRequestId,
    task_id: taskId,
    action_title: `Review terminal access: ${summarizePrompt(pending.command, 72)}`,
    reason: "This terminal command needs your approval before GeeAgent runs it.",
    risk_tags: ["terminal", "shell", "permission"],
    review_required: true,
    status: "open",
    parameters: [
      { label: "Command", value: pending.command },
      ...(pending.cwd ? [{ label: "Working directory", value: pending.cwd }] : []),
    ],
    machine_context: {
      kind: "sdk_runtime_terminal",
      source: route.source,
      surface: route.surface,
      user_prompt: userContent,
      runtime_session_id: pending.runtime_session_id,
      runtime_request_id: pending.runtime_request_id,
      scope: pending.scope,
      command: pending.command,
      cwd: pending.cwd ?? null,
    },
  });
  const task = findTask(store, taskId);
  task.approval_request_id = approvalRequestId;
  task.status = "waiting_review";
  task.current_stage = "review_pending";
  task.summary = `Waiting for terminal review: ${commandSummary}`;
  store.workspace_focus = { mode: "task", task_id: taskId };
  store.quick_reply = "Another terminal review is needed before Bash can continue.";
  store.last_run_state = runtimeRunState(
    store.active_conversation_id,
    "waiting_review",
    "terminal_permission_review_required",
    `GeeAgent paused the same SDK run for another terminal permission review: ${summarizePrompt(pending.command, 180)}`,
    true,
    taskId,
    moduleRunIdForTask(store, taskId),
  );
  store.last_request_outcome = {
    source: route.source,
    kind: "task_handoff",
    detail: `Another terminal approval required: ${commandSummary}`,
    task_id: taskId,
    module_run_id: moduleRunIdForTask(store, taskId),
  };
}

function appendClaudeSdkRuntimeFollowUp(
  store: RuntimeStore,
  surface: TurnRoute["surface"],
  controlSummary: string,
  sdkTurn: SdkTurnResult,
  assistantReply: string,
  finalizeReason: string,
): void {
  const sessionId = ensureExecutionSessionForActiveConversation(store, surface);
  appendSessionStateForSession(store, sessionId, controlSummary);
  appendToolEvents(store, sessionId, `approval_follow_up_${Date.now()}`, sdkTurn.tool_events);
  appendAssistantMessageForActiveConversation(store, sessionId, assistantReply);
  appendSessionStateForSession(store, sessionId, finalizeReason);
}

function isSdkRuntimeTerminalContext(
  context: JsonRecord | undefined,
): context is JsonRecord {
  return Boolean(
    context &&
    (context.kind === "sdk_runtime_terminal" || context.kind === "sdk_bridge_terminal"),
  );
}

function runtimeSessionIdFromContext(context: JsonRecord): string {
  return stringField(context, "runtime_session_id") ||
    stringField(context, "bridge_session_id");
}

function runtimeRequestIdFromContext(context: JsonRecord): string {
  return stringField(context, "runtime_request_id") ||
    stringField(context, "bridge_request_id");
}

function updateTaskAfterSdkApproval(
  store: RuntimeStore,
  taskId: string,
  decision: TerminalAccessDecision,
  sdkTurn: SdkTurnResult,
  summary: string,
): void {
  const failed = decision === "deny" || Boolean(sdkTurn.failed_reason);
  const task = findTask(store, taskId);
  task.summary = summary;
  task.approval_request_id = null;
  task.current_stage =
    decision === "deny" ? "rejected_waiting_input" : failed ? "finalized_failed" : "finalized";
  task.progress_percent =
    decision === "deny" ? 68 : failed ? 72 : 100;
  task.status =
    decision === "deny" ? "waiting_input" : failed ? "failed" : "completed";

  const moduleRun = findModuleRunForTask(store, taskId);
  if (moduleRun) {
    const module = asRecord(moduleRun.module_run);
    module.result_summary = summary;
    module.updated_at = "now";
    module.status = failed ? "failed" : "completed";
    module.stage = "finalized";
    moduleRun.recoverability =
      decision === "deny"
        ? {
            retry_safe: false,
            resume_supported: false,
            hint: "Terminal access was denied by review.",
          }
        : null;
  }

  store.quick_reply =
    decision === "deny"
      ? "Terminal access denied. GeeAgent kept the run blocked without executing Bash."
      : sdkTurn.failed_reason
        ? claudeSdkFailedQuickReply(sdkTurn.failed_reason)
        : claudeSdkQuickReply(assistantReplyFromTurn(sdkTurn, summary), toolStepCount(sdkTurn));
  store.chat_runtime = sdkTurn.failed_reason
    ? claudeSdkDegradedChatRuntimeRecord(sdkTurn.failed_reason)
    : claudeSdkChatRuntimeRecord();
  store.last_run_state =
    decision === "deny"
      ? runtimeRunState(
          store.active_conversation_id,
          "waiting_input",
          "terminal_permission_denied",
          "The terminal request was denied and the run is waiting for more input.",
          true,
          taskId,
          moduleRunIdForTask(store, taskId),
        )
      : sdkTurn.failed_reason
        ? runtimeRunState(
            store.active_conversation_id,
            "failed",
            "claude_sdk_failed_after_approval",
            summarizePrompt(sdkTurn.failed_reason, 220),
            false,
            taskId,
            moduleRunIdForTask(store, taskId),
          )
        : runtimeRunState(
            store.active_conversation_id,
            "completed",
            "approval_resumed_and_completed",
            summary,
            false,
            taskId,
            moduleRunIdForTask(store, taskId),
          );
  store.last_request_outcome = {
    source: "workspace_chat",
    kind: decision === "deny" || sdkTurn.failed_reason ? "clarify_needed" : "chat_reply",
    detail: store.quick_reply,
    task_id: taskId,
    module_run_id: moduleRunIdForTask(store, taskId),
  };
  store.workspace_focus = { mode: "task", task_id: taskId };
}

function resolveGenericApproval(
  store: RuntimeStore,
  approvalRequestId: string,
  taskId: string,
  normalizedDecision: "allow_once" | "always_allow" | "deny",
): void {
  activateConversationForTask(store, taskId);
  const approved = normalizedDecision !== "deny";
  const task = findTask(store, taskId);
  task.status = approved ? "completed" : "waiting_input";
  task.current_stage = approved ? "approved_and_resumed" : "rejected_waiting_input";
  task.progress_percent = approved ? 100 : 68;
  task.summary = approved
    ? "Approval granted. GeeAgent resumed the paused action and finalized the result."
    : "Terminal access was denied. The paused action is intact and waiting for your next instruction.";
  task.approval_request_id = null;
  appendControlResolutionTraceForTask(
    store,
    taskId,
    approvalRequestId,
    approved
      ? "Approval received. I resumed the paused action and closed the review gate."
      : "Terminal access was denied. I kept the run intact and moved the task back to waiting input.",
    approved ? "succeeded" : "failed",
  );
  store.workspace_focus = { mode: "task", task_id: taskId };
  store.quick_reply = approved
    ? "Approved. GeeAgent resumed the paused action and moved the task out of review."
    : "Denied. GeeAgent blocked that terminal access and moved the task back to waiting input.";
  store.last_run_state = runtimeRunState(
    store.active_conversation_id,
    approved ? "completed" : "waiting_input",
    approved ? "approval_resumed_and_completed" : "terminal_permission_denied",
    approved
      ? "The paused run resumed after approval and completed successfully."
      : "The paused run remains intact and is waiting for more input after terminal access was denied.",
    !approved,
    taskId,
    moduleRunIdForTask(store, taskId),
  );
}

function appendControlResolutionTraceForTask(
  store: RuntimeStore,
  taskId: string,
  approvalRequestId: string,
  assistantMessage: string,
  status: "succeeded" | "failed",
): void {
  activateConversationForTask(store, taskId);
  const sessionId = ensureExecutionSessionForActiveConversation(store, "cli_workspace_chat");
  appendSessionStateForSession(
    store,
    sessionId,
    status === "succeeded"
      ? "approval granted, resuming the paused run and committing the prepared action"
      : "terminal access denied, returning the run to waiting input without executing the prepared action",
  );
  appendToolResultForExistingInvocation(
    store,
    sessionId,
    `toolinv_${approvalRequestId}`,
    status,
    undefined,
    status === "failed" ? stringField(findTask(store, taskId), "summary") : undefined,
  );
  appendAssistantMessageForActiveConversation(store, sessionId, assistantMessage);
  appendSessionStateForSession(
    store,
    sessionId,
    status === "succeeded"
      ? "the paused run resumed and completed after approval"
      : "the paused run stayed intact and moved back to waiting input after terminal access was denied",
  );
}

export function applySimpleModuleRetry(store: RuntimeStore, taskId: string): void {
  const moduleRun = findModuleRunForTask(store, taskId);
  if (!moduleRun) {
    throw new Error("task does not have a recoverable module run");
  }
  const module = asRecord(moduleRun.module_run);
  const recoverability = isRecord(moduleRun.recoverability)
    ? moduleRun.recoverability
    : undefined;
  if (recoverability?.retry_safe !== true) {
    throw new Error("task does not have a recoverable module run");
  }
  module.status = "queued";
  module.stage = "queued";
  module.updated_at = "now";
  moduleRun.recoverability = null;
  const task = findTask(store, taskId);
  task.status = "queued";
  task.current_stage = "retry_requested";
  task.progress_percent = Math.min(Number(task.progress_percent ?? 0), 72);
  task.summary = "Retry requested. GeeAgent queued the recoverable run again.";
  store.workspace_focus = { mode: "task", task_id: taskId };
  store.quick_reply = "Retry queued for the selected task.";
}
