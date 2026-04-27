import { createConversation, QUICK_CONVERSATION_TAG } from "./store/conversations.js";
import { loadRuntimeStore, persistRuntimeStore } from "./store/persistence.js";
import { snapshotFromStore } from "./store/snapshot.js";
import type {
  RuntimeHostActionCompletion,
  RuntimeHostActionIntent,
} from "../protocol.js";
import type { RuntimeSnapshot, RuntimeStore } from "./store/types.js";
import {
  resumeSdkRuntimeHostActions,
  runSdkRuntimeTurn,
  type SdkToolEvent,
  type SdkTurnResult,
  type TurnRoute,
} from "./sdk-turn-runner.js";
import {
  applyClaudeSdkTerminalDenial,
  applySimpleModuleRetry,
  installClaudeSdkTerminalApproval,
  resolveApproval,
} from "./turns/approvals.js";
import { routeLocalGearIntent, type RoutedGearIntent } from "./turns/gear-intents.js";
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
  appendToolResultForExistingInvocation,
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
  runtimeRunState,
  stringField,
  toolStepCount,
} from "./turns/state.js";
import type { PreparedTurnContext, TurnReplayCursor } from "./turns/types.js";

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
  const prepared = prepareTurnContext(store, route, trimmed);
  await applyClaudeSdkTurn(store, configDir, route, prepared, trimmed);
  await persistRuntimeStore(configDir, store);
  return snapshotFromStore(store, configDir);
}

export async function submitRoutedWorkspaceMessage(
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
  routeQuickPromptToBestConversation(store, trimmed);
  const prepared = prepareTurnContext(store, route, trimmed);
  await applyClaudeSdkTurn(store, configDir, route, prepared, trimmed);
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

export async function completeHostActionTurn(
  configDir: string,
  completions: RuntimeHostActionCompletion[],
): Promise<RuntimeSnapshot> {
  const store = await loadRuntimeStore(configDir);
  store.host_action_intents = [];

  const runtimeSessionId = executionSessionIdForConversation(store.active_conversation_id);
  appendSessionStateForSession(
    store,
    runtimeSessionId,
    "native Gear actions completed; returning structured host results to the SDK runtime so the agent can write the user-facing reply",
  );

  for (const completion of completions) {
    appendToolResultForExistingInvocation(
      store,
      runtimeSessionId,
      completion.host_action_id,
      completion.status,
      completion.summary,
      completion.error,
    );
  }

  const resumedTurn = await resumeSdkRuntimeHostActions(
    configDir,
    runtimeSessionId,
    completions,
  );
  if (resumedTurn) {
    await applyResumedSdkHostActionTurn(store, configDir, runtimeSessionId, resumedTurn);
    return snapshotFromStore(store, configDir);
  }

  const activeProfile = store.agent_profiles.find(
    (profile) => profile.id === store.active_agent_profile_id,
  );
  if (!activeProfile) {
    throw new Error("active agent profile not found");
  }

  const route: TurnRoute = {
    mode: "workspace_message",
    source: "workspace_chat",
    surface: "cli_workspace_chat",
  };
  let sdkTurn: SdkTurnResult;
  const sdkRuntimeSessionId = `${runtimeSessionId}:gear-completion`;
  try {
    sdkTurn = await runSdkRuntimeTurn(
      configDir,
      sdkRuntimeSessionId,
      route,
      activeProfile,
      composeGearCompletionPrompt(store, completions),
      [],
      {
        availableTools: [],
        autoApproveTools: [],
        disallowedTools: [],
        enableGeeHostTools: false,
      },
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
    sdkTurn.failed_reason =
      "The agent tried to request terminal access while summarizing Gear results. Gear completion replies must be text-only and cannot pause for terminal approval.";
  }
  if (sdkTurn.terminal_access_denied_reason) {
    sdkTurn.failed_reason = sdkTurn.terminal_access_denied_reason;
  }
  if (sdkTurn.failed_reason) {
    sdkTurn.assistant_chunks = [
      claudeSdkFailureAssistantReply(sdkTurn.failed_reason),
    ];
  }

  const originatingMessageId = lastUserMessageId(store) ?? "host-action-user";
  appendToolEvents(store, runtimeSessionId, originatingMessageId, sdkTurn.tool_events);
  const assistantReply = assistantReplyFromTurn(
    sdkTurn,
    "The Gear action completed, but the agent did not produce a text summary.",
  );
  appendAssistantMessageForActiveConversation(store, runtimeSessionId, assistantReply);
  appendSessionStateForSession(
    store,
    runtimeSessionId,
    sdkTurn.failed_reason
      ? "the SDK runtime failed while composing the Gear completion reply"
      : "the SDK runtime composed the final user-facing reply from Gear host results",
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
    kind: "host_action_completed",
    detail: quickReply,
    task_id: null,
    module_run_id: null,
  };

  await persistRuntimeStore(configDir, store);
  return snapshotFromStore(store, configDir);
}

async function applyResumedSdkHostActionTurn(
  store: RuntimeStore,
  configDir: string,
  runtimeSessionId: string,
  sdkTurn: SdkTurnResult,
): Promise<void> {
  const originatingMessageId = lastUserMessageId(store) ?? "host-action-user";
  appendToolEvents(store, runtimeSessionId, originatingMessageId, sdkTurn.tool_events);

  if (sdkTurn.pending_host_actions && sdkTurn.pending_host_actions.length > 0) {
    appendSessionStateForSession(
      store,
      runtimeSessionId,
      "the agent inspected the Gear result and requested another native Gear host action inside the same SDK run",
    );
    appendDirectiveHostActionInvocations(
      store,
      runtimeSessionId,
      originatingMessageId,
      sdkTurn,
    );
    markHostActionsPending(
      store,
      {
        mode: "workspace_message",
        source: "workspace_chat",
        surface: "cli_workspace_chat",
      },
      sdkTurn.pending_host_actions,
    );
    await persistRuntimeStore(configDir, store);
    return;
  }

  if (sdkTurn.pending_terminal_approval) {
    sdkTurn.failed_reason =
      "The agent requested terminal access while continuing a Gear host-action run. This bridge currently supports same-run Gear continuation only.";
  }
  if (sdkTurn.terminal_access_denied_reason) {
    sdkTurn.failed_reason = sdkTurn.terminal_access_denied_reason;
  }
  if (sdkTurn.failed_reason) {
    sdkTurn.assistant_chunks = [
      claudeSdkFailureAssistantReply(sdkTurn.failed_reason),
    ];
  }

  const assistantReply = assistantReplyFromTurn(
    sdkTurn,
    "The Gear action completed, but the agent did not produce a text summary.",
  );
  appendAssistantMessageForActiveConversation(store, runtimeSessionId, assistantReply);
  appendSessionStateForSession(
    store,
    runtimeSessionId,
    sdkTurn.failed_reason
      ? "the SDK runtime failed while continuing after Gear host results"
      : "the SDK runtime continued after Gear host results and completed the active user turn",
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
    source: "workspace_chat",
    kind: "host_action_completed",
    detail: quickReply,
    task_id: null,
    module_run_id: null,
  };

  await persistRuntimeStore(configDir, store);
}

async function applyClaudeSdkTurn(
  store: RuntimeStore,
  configDir: string,
  route: TurnRoute,
  prepared: PreparedTurnContext,
  text: string,
): Promise<void> {
  store.host_action_intents = [];
  if (route.mode === "quick_prompt" && !prepared.shouldReuseActiveConversation) {
    createConversation(store, quickConversationTitle(text), [QUICK_CONVERSATION_TAG]);
  }

  const routedGearIntent = routeLocalGearIntent(text);
  if (routedGearIntent) {
    recordRoutedGearHostTurn(store, route, text, routedGearIntent);
    return;
  }

  const runtimeSessionId = executionSessionIdForConversation(store.active_conversation_id);
  const cursor = beginTurnReplay(store, route.surface, text);
  appendSessionStateForSession(
    store,
    cursor.sessionId,
    "delegating this turn into the SDK loop through the Xenodia gateway so the agent can reason and use tools inside one real run",
  );
  store.quick_reply = "GeeAgent is working on this request.";
  store.chat_runtime = claudeSdkChatRuntimeRecord();
  store.last_run_state = runtimeRunState(
    store.active_conversation_id,
    "running",
    "sdk_runtime_running",
    "GeeAgent is running the active turn and will stream tool activity into this conversation.",
    false,
    null,
    null,
  );
  store.last_request_outcome = {
    source: route.source,
    kind: "chat_reply",
    detail: "GeeAgent is working on this request.",
    task_id: null,
    module_run_id: null,
  };
  await persistRuntimeStore(configDir, store);

  let sdkTurn: SdkTurnResult;
  try {
    sdkTurn = await runSdkRuntimeTurn(
      configDir,
      runtimeSessionId,
      route,
      prepared.activeAgentProfile,
      composeClaudeSdkTurnPrompt(route, prepared, text),
      [],
      {
        onToolEvent: (event) => appendLiveSdkToolEvent(store, configDir, cursor, event),
      },
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
    installClaudeSdkTerminalApproval(store, route, text, sdkTurn.pending_terminal_approval, {
      cursor,
    });
    return;
  }
  if (sdkTurn.pending_host_actions && sdkTurn.pending_host_actions.length > 0) {
    installClaudeSdkHostActions(store, route, text, sdkTurn, cursor);
    return;
  }
  if (sdkTurn.terminal_access_denied_reason) {
    applyClaudeSdkTerminalDenial(store, route, text, sdkTurn.terminal_access_denied_reason, {
      cursor,
    });
    return;
  }
  if (sdkTurn.failed_reason) {
    sdkTurn.assistant_chunks = [
      claudeSdkFailureAssistantReply(sdkTurn.failed_reason),
    ];
  }

  const assistantReply = recordLiveClaudeSdkTurnCompletion(store, cursor, sdkTurn);
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

async function appendLiveSdkToolEvent(
  store: RuntimeStore,
  configDir: string,
  cursor: TurnReplayCursor,
  event: SdkToolEvent,
): Promise<void> {
  appendToolEvents(store, cursor.sessionId, cursor.userMessageId, [event]);
  await persistRuntimeStore(configDir, store);
}

function recordRoutedGearHostTurn(
  store: RuntimeStore,
  route: TurnRoute,
  text: string,
  routed: RoutedGearIntent,
): void {
  store.host_action_intents = routed.hostActions;
  const toolEvents = routed.hostActions.map((action) => ({
      kind: "invocation" as const,
      invocation_id: action.host_action_id,
      tool_name: action.tool_id,
      input_summary: JSON.stringify(action.arguments ?? {}),
    }));

  const cursor = beginTurnReplay(store, route.surface, text);
  appendSessionStateForSession(
    store,
    cursor.sessionId,
    "routing this Gear request through the native Gee host; the final reply will be generated by the agent after host results return",
  );
  appendToolEvents(store, cursor.sessionId, cursor.userMessageId, toolEvents);
  store.quick_reply = "Running the Gear action in the native host.";
  store.chat_runtime = claudeSdkChatRuntimeRecord();
  store.last_run_state = runtimeRunState(
    store.active_conversation_id,
    "running",
    "gear_host_action_running",
    "GeeAgent is applying the Gear action in the native host before asking the agent to summarize the result.",
    false,
    null,
    null,
  );
  store.last_request_outcome = {
    source: route.source,
    kind: "host_action_pending",
    detail: "Running the Gear action in the native host.",
    task_id: null,
    module_run_id: null,
  };
}

function installClaudeSdkHostActions(
  store: RuntimeStore,
  route: TurnRoute,
  text: string,
  sdkTurn: SdkTurnResult,
  existingCursor?: TurnReplayCursor,
): void {
  const hostActions = sdkTurn.pending_host_actions ?? [];
  store.host_action_intents = hostActions;
  const cursor = existingCursor ?? beginTurnReplay(store, route.surface, text);
  if (!existingCursor) {
    appendSessionStateForSession(
      store,
      cursor.sessionId,
      "delegating this turn into the SDK loop so the agent can plan Gear work through small host bridge tools",
    );
    appendToolEvents(store, cursor.sessionId, cursor.userMessageId, sdkTurn.tool_events);
  }
  appendDirectiveHostActionInvocations(
    store,
    cursor.sessionId,
    cursor.userMessageId,
    sdkTurn,
  );
  appendSessionStateForSession(
    store,
    cursor.sessionId,
    "the agent requested native Gear host action(s); GeeAgent paused the same SDK run until the macOS host returns structured results",
  );
  finalizeTurnReplay(
    store,
    cursor,
    "the SDK runtime is waiting on native Gear host action results before continuing this same user turn",
  );
  markHostActionsPending(store, route, hostActions);
}

function appendDirectiveHostActionInvocations(
  store: RuntimeStore,
  sessionId: string,
  originatingMessageId: string,
  sdkTurn: SdkTurnResult,
): void {
  if (sdkTurn.pending_host_action_mode !== "directive") {
    return;
  }
  const hostActions = sdkTurn.pending_host_actions ?? [];
  appendToolEvents(
    store,
    sessionId,
    originatingMessageId,
    hostActions.map((action) => ({
      kind: "invocation" as const,
      invocation_id: action.host_action_id,
      tool_name: action.tool_id,
      input_summary: JSON.stringify(action.arguments ?? {}),
    })),
  );
}

function markHostActionsPending(
  store: RuntimeStore,
  route: TurnRoute,
  hostActions: RuntimeHostActionIntent[],
): void {
  store.host_action_intents = hostActions;
  store.quick_reply = "Running the Gear action in the native host.";
  store.chat_runtime = claudeSdkChatRuntimeRecord();
  store.last_run_state = runtimeRunState(
    store.active_conversation_id,
    "running",
    "gear_host_action_running",
    "GeeAgent is applying the Gear action in the native host before returning structured results to the active agent run.",
    false,
    null,
    null,
  );
  store.last_request_outcome = {
    source: route.source,
    kind: "host_action_pending",
    detail: "Running the Gear action in the native host.",
    task_id: null,
    module_run_id: null,
  };
}

function composeGearCompletionPrompt(
  store: RuntimeStore,
  completions: RuntimeHostActionCompletion[],
): string {
  const userRequest = lastUserMessageContent(store) ?? "The user requested a Gear action.";
  const resultLines = completions.map((completion) => {
    const summary = completion.summary?.trim();
    const error = completion.error?.trim();
    const resultJSON = completion.result_json?.trim();
    const detail = completion.status === "succeeded"
      ? (summary || "completed without a text summary")
      : (error || summary || "failed without a text error");
    const result = resultJSON ? `\n  Structured result: ${resultJSON}` : "";
    return `- ${completion.tool_id} (${completion.host_action_id}): ${completion.status}. ${detail}${result}`;
  });
  return [
    "You are GeeAgent continuing the same user turn after native Gear host actions completed.",
    "Write the final user-facing reply in the user's language.",
    "Use the Gear tool results below as the source of truth.",
    "Do not claim the action succeeded if any required Gear result failed.",
    "Do not expose raw JSON unless it helps the user.",
    "Keep the reply concise and natural.",
    "",
    "Original user request:",
    userRequest,
    "",
    "Gear host results:",
    ...resultLines,
  ].join("\n");
}

function lastUserMessageContent(store: RuntimeStore): string | null {
  const messages = store.conversations.find(
    (conversation) => conversation.conversation_id === store.active_conversation_id,
  )?.messages ?? [];
  for (let index = messages.length - 1; index >= 0; index -= 1) {
    const message = messages[index];
    if (message.role === "user") {
      return message.content;
    }
  }
  return null;
}

function lastUserMessageId(store: RuntimeStore): string | null {
  const messages = store.conversations.find(
    (conversation) => conversation.conversation_id === store.active_conversation_id,
  )?.messages ?? [];
  for (let index = messages.length - 1; index >= 0; index -= 1) {
    const message = messages[index];
    if (message.role === "user") {
      return message.message_id;
    }
  }
  return null;
}

async function applyTransientClaudeSdkQuickTurn(
  store: RuntimeStore,
  configDir: string,
  route: TurnRoute,
  prepared: PreparedTurnContext,
  text: string,
): Promise<void> {
  store.host_action_intents = [];
  const routedGearIntent = routeLocalGearIntent(text);
  if (routedGearIntent) {
    recordRoutedGearHostTurn(store, route, text, routedGearIntent);
    return;
  }

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
    (sdkTurn.pending_host_actions && sdkTurn.pending_host_actions.length > 0) ||
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

function recordLiveClaudeSdkTurnCompletion(
  store: RuntimeStore,
  cursor: TurnReplayCursor,
  sdkTurn: SdkTurnResult,
): string {
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
