import { createConversation } from "./store/conversations.js";
import { loadRuntimeStore, persistRuntimeStore } from "./store/persistence.js";
import { snapshotFromStore } from "./store/snapshot.js";
import type { RuntimeSnapshot, RuntimeStore } from "./store/types.js";
import { runSdkRuntimeTurn, type SdkTurnResult, type TurnRoute } from "./sdk-turn-runner.js";
import {
  applyClaudeSdkTerminalDenial,
  applySimpleModuleRetry,
  installClaudeSdkTerminalApproval,
  resolveApproval,
} from "./turns/approvals.js";
import {
  composeClaudeSdkTurnPrompt,
  isTransientQuickPrompt,
  prepareTurnContext,
  quickConversationTitle,
  routeQuickPromptToBestConversation,
  transientRuntimeSessionId,
} from "./turns/context.js";
import {
  appendAssistantMessageForActiveConversation,
  appendSessionStateForSession,
  appendToolEvents,
  beginTurnReplay,
  executionSessionIdForConversation,
  finalizeTurnReplay,
} from "./turns/events.js";
import {
  assistantReplyFromTurn,
  claudeSdkChatRuntimeRecord,
  claudeSdkCompletedRunState,
  claudeSdkDegradedChatRuntimeRecord,
  claudeSdkFailedQuickReply,
  claudeSdkFailedRunState,
  claudeSdkFailureAssistantReply,
  claudeSdkQuickReply,
  errorMessage,
  findTask,
  stringField,
  toolStepCount,
} from "./turns/state.js";
import type { PreparedTurnContext } from "./turns/types.js";

export async function submitWorkspaceMessage(
  configDir: string,
  message: string,
): Promise<RuntimeSnapshot> {
  const trimmed = message.trim();
  if (!trimmed) {
    throw new Error("message cannot be empty");
  }

  const store = await loadRuntimeStore(configDir);
  const route: TurnRoute = {
    mode: "workspace_message",
    source: "workspace_chat",
    surface: "cli_workspace_chat",
  };
  const prepared = prepareTurnContext(store, route, trimmed);
  await applyClaudeSdkTurn(store, configDir, route, prepared, trimmed);
  await persistRuntimeStore(configDir, store);
  return snapshotFromStore(store, configDir);
}

export async function submitQuickPrompt(
  configDir: string,
  prompt: string,
): Promise<RuntimeSnapshot> {
  const trimmed = prompt.trim();
  if (!trimmed) {
    throw new Error("prompt cannot be empty");
  }

  const store = await loadRuntimeStore(configDir);
  const route: TurnRoute = {
    mode: "quick_prompt",
    source: "quick_input",
    surface: "cli_quick_input",
  };
  const routedConversation = routeQuickPromptToBestConversation(store, trimmed);
  const isTransient = !routedConversation && isTransientQuickPrompt(trimmed);
  const prepared = prepareTurnContext(store, route, trimmed);
  if (isTransient) {
    await applyTransientClaudeSdkQuickTurn(store, configDir, route, prepared, trimmed);
  } else {
    await applyClaudeSdkTurn(store, configDir, route, prepared, trimmed);
  }
  await persistRuntimeStore(configDir, store);
  return snapshotFromStore(store, configDir);
}

export async function performTaskAction(
  configDir: string,
  taskId: string,
  action: string,
): Promise<RuntimeSnapshot> {
  const store = await loadRuntimeStore(configDir);
  switch (action) {
    case "approve":
    case "allow_once":
    case "always_allow":
    case "deny": {
      const task = findTask(store, taskId);
      const approvalRequestId = stringField(task, "approval_request_id");
      if (!approvalRequestId) {
        throw new Error("task does not have an open approval request");
      }
      await resolveApproval(store, configDir, approvalRequestId, action);
      break;
    }
    case "retry":
      applySimpleModuleRetry(store, taskId);
      break;
    default:
      throw new Error("unsupported task action");
  }
  await persistRuntimeStore(configDir, store);
  return snapshotFromStore(store, configDir);
}

async function applyClaudeSdkTurn(
  store: RuntimeStore,
  configDir: string,
  route: TurnRoute,
  prepared: PreparedTurnContext,
  text: string,
): Promise<void> {
  if (route.mode === "quick_prompt" && !prepared.shouldReuseActiveConversation) {
    createConversation(store, quickConversationTitle(text));
  }

  const runtimeSessionId = executionSessionIdForConversation(store.active_conversation_id);
  let sdkTurn: SdkTurnResult;
  try {
    sdkTurn = await runSdkRuntimeTurn(
      configDir,
      runtimeSessionId,
      route,
      prepared.activeAgentProfile,
      composeClaudeSdkTurnPrompt(route, prepared, text),
    );
  } catch (error) {
    const reason = errorMessage(error);
    sdkTurn = {
      assistant_chunks: [claudeSdkFailureAssistantReply(reason)],
      tool_events: [],
      auto_approved_tools: 0,
      failed_reason: reason,
    };
  }

  if (sdkTurn.pending_terminal_approval) {
    installClaudeSdkTerminalApproval(store, route, text, sdkTurn.pending_terminal_approval);
    return;
  }
  if (sdkTurn.terminal_access_denied_reason) {
    applyClaudeSdkTerminalDenial(store, route, text, sdkTurn.terminal_access_denied_reason);
    return;
  }
  if (sdkTurn.failed_reason) {
    sdkTurn.assistant_chunks = [
      claudeSdkFailureAssistantReply(sdkTurn.failed_reason),
    ];
  }

  const assistantReply = recordClaudeSdkTurn(store, route, text, sdkTurn);
  const quickReply = sdkTurn.failed_reason
    ? claudeSdkFailedQuickReply(sdkTurn.failed_reason)
    : claudeSdkQuickReply(assistantReply, toolStepCount(sdkTurn));

  store.quick_reply = quickReply;
  store.chat_runtime = sdkTurn.failed_reason
    ? claudeSdkDegradedChatRuntimeRecord(sdkTurn.failed_reason)
    : claudeSdkChatRuntimeRecord();
  store.last_run_state = sdkTurn.failed_reason
    ? claudeSdkFailedRunState(store, sdkTurn.failed_reason)
    : claudeSdkCompletedRunState(store, assistantReply);
  store.last_request_outcome = {
    source: route.source,
    kind: "chat_reply",
    detail: quickReply,
    task_id: null,
    module_run_id: null,
  };
}

async function applyTransientClaudeSdkQuickTurn(
  store: RuntimeStore,
  configDir: string,
  route: TurnRoute,
  prepared: PreparedTurnContext,
  text: string,
): Promise<void> {
  const transientPrepared: PreparedTurnContext = {
    ...prepared,
    workspaceMessages: [],
    shouldReuseActiveConversation: true,
  };
  const runtimeSessionId = transientRuntimeSessionId(text);
  let sdkTurn: SdkTurnResult;
  try {
    sdkTurn = await runSdkRuntimeTurn(
      configDir,
      runtimeSessionId,
      route,
      transientPrepared.activeAgentProfile,
      composeClaudeSdkTurnPrompt(route, transientPrepared, text),
    );
  } catch (error) {
    const reason = errorMessage(error);
    sdkTurn = {
      assistant_chunks: [claudeSdkFailureAssistantReply(reason)],
      tool_events: [],
      auto_approved_tools: 0,
      failed_reason: reason,
    };
  }

  if (
    sdkTurn.pending_terminal_approval ||
    sdkTurn.terminal_access_denied_reason
  ) {
    await applyClaudeSdkTurn(store, configDir, route, prepared, text);
    return;
  }

  if (sdkTurn.failed_reason) {
    sdkTurn.assistant_chunks = [
      claudeSdkFailureAssistantReply(sdkTurn.failed_reason),
    ];
  }
  const assistantReply = assistantReplyFromTurn(
    sdkTurn,
    "GeeAgent completed the transient quick reply.",
  );
  const quickReply = sdkTurn.failed_reason
    ? claudeSdkFailedQuickReply(sdkTurn.failed_reason)
    : claudeSdkQuickReply(assistantReply, toolStepCount(sdkTurn));

  store.quick_reply = quickReply;
  store.chat_runtime = sdkTurn.failed_reason
    ? claudeSdkDegradedChatRuntimeRecord(sdkTurn.failed_reason)
    : claudeSdkChatRuntimeRecord();
  store.last_run_state = sdkTurn.failed_reason
    ? claudeSdkFailedRunState(store, sdkTurn.failed_reason)
    : claudeSdkCompletedRunState(store, assistantReply);
  store.last_request_outcome = {
    source: route.source,
    kind: "chat_reply",
    detail: quickReply,
    task_id: null,
    module_run_id: null,
  };
}

function recordClaudeSdkTurn(
  store: RuntimeStore,
  route: TurnRoute,
  userContent: string,
  sdkTurn: SdkTurnResult,
): string {
  const cursor = beginTurnReplay(store, route.surface, userContent);
  appendSessionStateForSession(
    store,
    cursor.sessionId,
    "delegating this turn into the SDK loop through the Xenodia gateway so the agent can reason and use tools inside one real run",
  );

  appendToolEvents(store, cursor.sessionId, cursor.userMessageId, sdkTurn.tool_events);

  if (sdkTurn.auto_approved_tools > 0) {
    appendSessionStateForSession(
      store,
      cursor.sessionId,
      `the host auto-approved ${sdkTurn.auto_approved_tools} SDK tool request(s) during this runtime run`,
    );
  }

  const assistantReply = assistantReplyFromTurn(
    sdkTurn,
    "The SDK completed the turn without a text summary.",
  );
  appendAssistantMessageForActiveConversation(store, cursor.sessionId, assistantReply);
  finalizeTurnReplay(
    store,
    cursor,
    sdkTurn.failed_reason
      ? "the SDK runtime surfaced a real runtime failure and GeeAgent committed that failed turn back into the active conversation"
      : "the SDK runtime completed the active turn and committed the resulting tool trace back into GeeAgent",
  );
  return assistantReply;
}

export const __turnTestHooks = {
  composeClaudeSdkTurnPrompt,
  isTransientQuickPrompt,
  routeQuickPromptToBestConversation,
};
