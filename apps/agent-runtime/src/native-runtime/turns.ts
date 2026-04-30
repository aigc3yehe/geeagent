import { createConversation, QUICK_CONVERSATION_TAG } from "./store/conversations.js";
import { loadChatReadiness, type ChatReadiness } from "../chat-runtime.js";
import { loadRuntimeStore, persistRuntimeStore } from "./store/persistence.js";
import { snapshotFromStore } from "./store/snapshot.js";
import type {
  RuntimeHostActionCompletion,
  RuntimeHostActionIntent,
} from "../protocol.js";
import type {
  RuntimeHostActionRunRecord,
  RuntimeHostActionRunSource,
  RuntimeSnapshot,
  RuntimeStore,
} from "./store/types.js";
import {
  buildStageSummaryCapsule,
  renderStageSummaryCapsule,
  type StageSummaryArtifactRef,
  type StageSummaryStatus,
} from "./context/stage-summary.js";
import {
  closeSdkRuntimeSession,
  resumeSdkRuntimeHostActions,
  runSdkRuntimeTurn,
  updateSdkRuntimeRunPlan,
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
import {
  composeClaudeSdkTurnPrompt,
  isTransientQuickPrompt,
  prepareTurnContext,
  quickConversationTitle,
  routeQuickPromptToBestConversation,
  transientRuntimeSessionId,
} from "./turns/context.js";
import {
  appendAssistantDeltaForActiveConversation,
  appendAssistantMessageForActiveConversation,
  appendCapabilityFocusForSession,
  appendRunPlanForSession,
  appendRunPlanUpdatedForSession,
  appendSessionStateForSession,
  appendStageConclusionForSession,
  appendStageStartedForSession,
  appendToolEvents,
  appendToolResultForHostBridgeCompletion,
  appendToolResultForExistingInvocation,
  beginTurnReplay,
  executionSessionIdForConversation,
  finalizeTurnReplay,
  latestRunPlanForSession,
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
  isRecord,
  runtimeRunState,
  stringField,
  summarizePrompt,
  toolStepCount,
} from "./turns/state.js";
import type { PreparedTurnContext, TurnReplayCursor } from "./turns/types.js";
import { requiresGeeGearBridgeFirst } from "./turns/gear-intents.js";
import {
  buildRuntimeRunPlan,
  currentRuntimePlanStage,
  nextRuntimeRunPlan,
  type RuntimeRunPlan,
} from "./turns/planning.js";
import {
  advanceRunPlanAfterHostCompletions,
  terminalRunPlanBlocker,
  type RuntimeStageAdvanceDecision,
} from "./turns/stage-advancer.js";

const GEAR_COMPLETION_SDK_IDLE_TIMEOUT_MS = 75_000;

type HostActionCompletionContext = {
  sessionId: string;
  conversationId: string;
  source: RuntimeHostActionRunSource | null;
};

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
  const completionContext = hostActionCompletionContext(store, completions);
  if (completionContext) {
    store.active_conversation_id = completionContext.conversationId;
  }
  store.host_action_intents = [];

  const runtimeSessionId =
    completionContext?.sessionId ??
    executionSessionIdForConversation(store.active_conversation_id);
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
  markHostActionRunsCompleted(store, completions);
  const stageProgress = applyStageAdvancerForHostCompletions(
    store,
    runtimeSessionId,
    completions,
  );

  const resumedTurn = await resumeSdkRuntimeHostActions(
    configDir,
    runtimeSessionId,
    completions,
    GEAR_COMPLETION_SDK_IDLE_TIMEOUT_MS,
    (delta) => appendLiveAssistantDelta(store, configDir, runtimeSessionId, delta),
  );
  if (resumedTurn) {
    await applyResumedSdkHostActionTurn(
      store,
      configDir,
      runtimeSessionId,
      resumedTurn,
      completions,
      stageProgress,
    );
    return snapshotFromStore(store, configDir);
  }

  await applyUnresumableHostActionCompletions(
    store,
    configDir,
    runtimeSessionId,
    completions,
    completionContext,
  );
  return snapshotFromStore(store, configDir);
}

async function applyResumedSdkHostActionTurn(
  store: RuntimeStore,
  configDir: string,
  runtimeSessionId: string,
  sdkTurn: SdkTurnResult,
  completions: RuntimeHostActionCompletion[],
  stageProgress: {
    activePlan: RuntimeRunPlan | null;
    decision: RuntimeStageAdvanceDecision | null;
    blocker: string | null;
  },
): Promise<void> {
  const originatingMessageId = lastUserMessageId(store) ?? "host-action-user";
  appendToolEvents(store, runtimeSessionId, originatingMessageId, sdkTurn.tool_events);

  if (stageProgress.blocker) {
    sdkTurn.failed_reason = stageProgress.blocker;
  }
  if (sdkTurn.pending_terminal_approval) {
    sdkTurn.failed_reason =
      "The agent requested terminal access while continuing a Gear host-action run. This bridge currently supports same-run Gear continuation only.";
  }
  if (sdkTurn.terminal_access_denied_reason) {
    sdkTurn.failed_reason = sdkTurn.terminal_access_denied_reason;
  }
  if (
    sdkTurn.failed_reason &&
    ((sdkTurn.pending_host_actions && sdkTurn.pending_host_actions.length > 0) ||
      sdkTurn.pending_terminal_approval)
  ) {
    closeSdkRuntimeSession(runtimeSessionId);
  }

  if (
    !sdkTurn.failed_reason &&
    sdkTurn.pending_host_actions &&
    sdkTurn.pending_host_actions.length > 0
  ) {
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
    recordHostActionRuns(
      store,
      "sdk_same_run",
      runtimeSessionId,
      originatingMessageId,
      sdkTurn.pending_host_actions,
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

  if (!sdkTurn.failed_reason && stageProgress.activePlan) {
    stageProgress.activePlan = applyModelOnlyStageConclusionsForTurn(
      store,
      runtimeSessionId,
      stageProgress.activePlan,
      sdkTurn,
    );
  }

  if (!sdkTurn.failed_reason && stageProgress.activePlan) {
    const blocker = terminalRunPlanBlocker(stageProgress.activePlan);
    if (blocker) {
      sdkTurn.failed_reason = blocker;
    }
  }
  markMissingAssistantReplyAsFailure(
    sdkTurn,
    "after Gear host-action continuation without a final assistant reply",
  );
  const completionFailureReason = sdkTurn.failed_reason;
  if (completionFailureReason) {
    sdkTurn.assistant_chunks = [
      gearCompletionFailureReply(
        lastUserMessageContent(store) ?? "",
        completions,
        completionFailureReason,
        sdkTurn,
      ),
    ];
  }

  const assistantReply = assistantReplyFromTurn(
    sdkTurn,
    "The SDK runtime ended without a final assistant reply.",
  );
  appendAssistantMessageForActiveConversation(store, runtimeSessionId, assistantReply);
  appendSessionStateForSession(
    store,
    runtimeSessionId,
    completionFailureReason
      ? "the SDK runtime failed while continuing after Gear host results; GeeAgent recorded the structured Gear result and preserved the runtime failure for retry"
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

async function applyUnresumableHostActionCompletions(
  store: RuntimeStore,
  configDir: string,
  runtimeSessionId: string,
  completions: RuntimeHostActionCompletion[],
  completionContext: HostActionCompletionContext | null,
): Promise<void> {
  for (const completion of completions) {
    appendToolResultForHostBridgeCompletion(
      store,
      runtimeSessionId,
      completion.tool_id,
      completion.status,
      completion.summary,
      completion.error,
    );
  }

  const legacyFallback = completionContext?.source
    ? completionContext.source === "static_fallback"
    : lastRunStopReason(store) === "static_gear_fallback_running";
  const failureReason = legacyFallback
    ? "A legacy native Gear fallback completion was received, but fallback task execution is now prohibited. GeeAgent recorded the structured result and marked the turn failed instead of presenting it as complete."
    : "The same-run SDK runtime session is no longer alive, so GeeAgent cannot safely continue this Gear host-action turn.";
  const assistantReply = unresumableHostActionReply(
    lastUserMessageContent(store) ?? "",
    completions,
    failureReason,
    legacyFallback,
  );

  const runPlan = latestRunPlanForSession(store, runtimeSessionId);
  if (runPlan) {
    appendStageConclusionForSession(
      store,
      runtimeSessionId,
      runPlan,
      "blocked",
      `Stage blocked because Gear host action results could not continue inside the active SDK run: ${failureReason}`,
    );
  }

  appendAssistantMessageForActiveConversation(store, runtimeSessionId, assistantReply);
  appendSessionStateForSession(
    store,
    runtimeSessionId,
    legacyFallback
      ? "a legacy native Gear fallback completion arrived; GeeAgent recorded structured results and exposed the prohibited fallback as a failed turn"
      : "the native Gear host action completed, but the same SDK run could not be resumed; GeeAgent did not start a detached completion turn",
  );

  const quickReply = claudeSdkFailedQuickReply(failureReason);
  store.quick_reply = quickReply;
  if (!legacyFallback) {
    store.chat_runtime = claudeSdkDegradedChatRuntimeRecord(failureReason);
  }
  store.last_run_state = runtimeRunState(
    store.active_conversation_id,
    "failed",
    legacyFallback
      ? "legacy_static_gear_fallback_prohibited"
      : "sdk_host_action_session_lost",
    assistantReply,
    false,
    null,
    null,
  );
  store.last_request_outcome = {
    source: "workspace_chat",
    kind: "host_action_completed",
    detail: quickReply,
    task_id: null,
    module_run_id: null,
  };

  await persistRuntimeStore(configDir, store);
}

function applyStageAdvancerForHostCompletions(
  store: RuntimeStore,
  runtimeSessionId: string,
  completions: RuntimeHostActionCompletion[],
): {
  activePlan: RuntimeRunPlan | null;
  decision: RuntimeStageAdvanceDecision | null;
  blocker: string | null;
} {
  const runPlan = latestRunPlanForSession(store, runtimeSessionId);
  if (!runPlan) {
    return { activePlan: null, decision: null, blocker: null };
  }

  const decision = advanceRunPlanAfterHostCompletions(runPlan, completions);
  if (!decision.concluded) {
    return { activePlan: runPlan, decision, blocker: null };
  }

  appendStageConclusionForSession(
    store,
    runtimeSessionId,
    runPlan,
    decision.status ?? "partial",
    decision.summary ?? "Stage reached a runtime boundary.",
  );

  if (decision.status === "blocked") {
    return {
      activePlan: runPlan,
      decision,
      blocker: decision.summary ?? "Current run stage is blocked.",
    };
  }

  if (!decision.nextPlan) {
    return { activePlan: runPlan, decision, blocker: null };
  }

  appendRunPlanUpdatedForSession(
    store,
    runtimeSessionId,
    decision.nextPlan,
    `Run plan advanced to ${decision.nextPlan.current_stage_id}.`,
  );
  updateSdkRuntimeRunPlan(runtimeSessionId, decision.nextPlan);
  appendCapabilityFocusForSession(store, runtimeSessionId, decision.nextPlan);
  appendStageStartedForSession(store, runtimeSessionId, decision.nextPlan);
  return { activePlan: decision.nextPlan, decision, blocker: null };
}

function applyModelOnlyStageConclusionsForTurn(
  store: RuntimeStore,
  runtimeSessionId: string,
  plan: RuntimeRunPlan,
  sdkTurn: SdkTurnResult,
): RuntimeRunPlan | null {
  let cursor: RuntimeRunPlan | null = plan;
  while (cursor) {
    const stage = currentRuntimePlanStage(cursor);
    if (!stage || stage.required_capabilities.length > 0) {
      return cursor;
    }

    const summary = modelOnlyStageCompletionSummary(stage.stage_id, stage.title, sdkTurn);
    if (!summary) {
      return cursor;
    }

    appendStageConclusionForSession(store, runtimeSessionId, cursor, "completed", summary);
    const nextPlan = nextRuntimeRunPlan(cursor);
    if (!nextPlan) {
      updateSdkRuntimeRunPlan(runtimeSessionId, cursor);
      return null;
    }

    appendRunPlanUpdatedForSession(
      store,
      runtimeSessionId,
      nextPlan,
      `Run plan advanced to ${nextPlan.current_stage_id}.`,
    );
    updateSdkRuntimeRunPlan(runtimeSessionId, nextPlan);
    appendCapabilityFocusForSession(store, runtimeSessionId, nextPlan);
    appendStageStartedForSession(store, runtimeSessionId, nextPlan);
    cursor = nextPlan;
  }
  return cursor;
}

function modelOnlyStageCompletionSummary(
  stageID: string,
  title: string,
  sdkTurn: SdkTurnResult,
): string | null {
  if (stageID === "stage_research_technologies") {
    return hasSucceededNonGeeToolResult(sdkTurn)
      ? `Stage completed: ${title}. Research evidence was collected through approved SDK tool results.`
      : null;
  }
  if (stageID === "stage_synthesize_explanation") {
    return hasAssistantReplyText(sdkTurn)
      ? `Stage completed: ${title}. The active SDK run produced the user-facing explanation.`
      : null;
  }
  if (stageID === "stage_verify") {
    return hasAssistantReplyText(sdkTurn)
      ? `Stage completed: ${title}. Final verification was satisfied by the active SDK reply.`
      : null;
  }
  if (hasSucceededNonGeeToolResult(sdkTurn)) {
    return `Stage completed: ${title}. The active SDK run produced structured tool evidence.`;
  }
  if (hasAssistantReplyText(sdkTurn)) {
    return `Stage completed: ${title}. The active SDK run produced a final response.`;
  }
  return null;
}

function hasSucceededNonGeeToolResult(sdkTurn: SdkTurnResult): boolean {
  const toolNamesById = new Map<string, string>();
  for (const event of sdkTurn.tool_events) {
    if (event.kind === "invocation") {
      toolNamesById.set(event.invocation_id, event.tool_name);
    }
  }
  return sdkTurn.tool_events.some((event) => {
    if (event.kind !== "result" || event.status !== "succeeded") {
      return false;
    }
    const toolName = toolNamesById.get(event.invocation_id) ?? "";
    return !toolName.startsWith("mcp__gee__");
  });
}

function markMissingAssistantReplyAsFailure(
  sdkTurn: SdkTurnResult,
  context: string,
): void {
  if (sdkTurn.failed_reason || hasAssistantReplyText(sdkTurn)) {
    return;
  }
  sdkTurn.failed_reason =
    `The SDK runtime finished ${context}. GeeAgent marked the turn failed instead of presenting a fake completion.`;
}

function hasAssistantReplyText(sdkTurn: SdkTurnResult): boolean {
  if (sdkTurn.assistant_chunks.some((chunk) => chunk.trim().length > 0)) {
    return true;
  }
  return Boolean(sdkTurn.final_result?.trim());
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

  const readiness = await loadChatReadiness(configDir);
  if (readiness.status !== "live") {
    recordRuntimeUnavailableTurn(store, route, text, readiness);
    return;
  }

  const runtimeSessionId = executionSessionIdForConversation(store.active_conversation_id);
  const cursor = beginTurnReplay(store, route.surface, text);
  const gearBridgeFirst = requiresGeeGearBridgeFirst(text);
  const runPlan = buildRuntimeRunPlan(
    text,
    gearBridgeFirst ? "gear_first" : "default",
  );
  if (runPlan) {
    appendRunPlanForSession(store, cursor.sessionId, runPlan);
    appendCapabilityFocusForSession(store, cursor.sessionId, runPlan);
    appendStageStartedForSession(store, cursor.sessionId, runPlan);
  }
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
        onAssistantText: (delta) =>
          appendLiveAssistantDelta(
            store,
            configDir,
            cursor.sessionId,
            delta,
            cursor.assistantMessageId,
          ),
        toolBoundaryMode: gearBridgeFirst ? "gear_first" : "default",
        runPlan,
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
  if (runPlan && !sdkTurn.failed_reason) {
    const blocker = terminalRunPlanBlocker(runPlan);
    if (blocker) {
      sdkTurn.failed_reason = blocker;
    }
  }
  markMissingAssistantReplyAsFailure(sdkTurn, "without a final assistant reply");
  if (sdkTurn.failed_reason) {
    sdkTurn.assistant_chunks = [
      claudeSdkFailureAssistantReply(sdkTurn.failed_reason),
    ];
  }

  const assistantReply = recordLiveClaudeSdkTurnCompletion(store, cursor, sdkTurn, runPlan);
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

async function appendLiveAssistantDelta(
  store: RuntimeStore,
  configDir: string,
  sessionId: string,
  delta: string,
  assistantMessageId?: string,
): Promise<void> {
  appendAssistantDeltaForActiveConversation(store, sessionId, delta, assistantMessageId);
  await persistRuntimeStore(configDir, store);
}

function recordRuntimeUnavailableTurn(
  store: RuntimeStore,
  route: TurnRoute,
  text: string,
  readiness: ChatReadiness,
): void {
  const cursor = beginTurnReplay(store, route.surface, text);
  const detail = [
    "the SDK runtime is not live, so GeeAgent stopped before executing tools or Gear actions",
    `(${readiness.status}: ${readiness.detail})`,
  ].join(" ");
  appendSessionStateForSession(
    store,
    cursor.sessionId,
    detail,
  );
  const assistantReply = claudeSdkFailureAssistantReply(
    `The SDK runtime is not live. ${readiness.detail}`,
  );
  appendAssistantMessageForActiveConversation(
    store,
    cursor.sessionId,
    assistantReply,
    cursor.assistantMessageId,
  );
  finalizeTurnReplay(store, cursor, "blocked because the SDK runtime is not live");
  store.host_action_intents = [];
  store.quick_reply = claudeSdkFailedQuickReply(readiness.detail);
  store.chat_runtime = {
    status: readiness.status === "needs_setup" ? "needs_setup" : "degraded",
    active_provider: readiness.active_provider ?? null,
    detail: readiness.detail,
  };
  store.last_run_state = runtimeRunState(
    store.active_conversation_id,
    "failed",
    "sdk_runtime_not_live",
    detail,
    false,
    null,
    null,
  );
  store.last_request_outcome = {
    source: route.source,
    kind: "chat_reply",
    detail: store.quick_reply,
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
  recordHostActionRuns(
    store,
    "sdk_same_run",
    cursor.sessionId,
    cursor.userMessageId,
    hostActions,
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

function recordHostActionRuns(
  store: RuntimeStore,
  source: RuntimeHostActionRunSource,
  sessionId: string,
  userMessageId: string,
  hostActions: RuntimeHostActionIntent[],
): void {
  if (hostActions.length === 0) {
    return;
  }

  const now = new Date().toISOString();
  const hostActionIds = new Set(hostActions.map((action) => action.host_action_id));
  const existingRuns = (store.host_action_runs ?? []).filter(
    (record) => !hostActionIds.has(record.host_action_id),
  );
  const recordedRuns = hostActions.map((action) => ({
    host_action_id: action.host_action_id,
    tool_id: action.tool_id,
    session_id: sessionId,
    conversation_id: store.active_conversation_id,
    user_message_id: userMessageId,
    source,
    status: "pending" as const,
    created_at: now,
    updated_at: now,
  }));

  store.host_action_runs = [...existingRuns, ...recordedRuns].slice(-200);
}

function hostActionCompletionContext(
  store: RuntimeStore,
  completions: RuntimeHostActionCompletion[],
): HostActionCompletionContext | null {
  const completionIds = new Set(
    completions.map((completion) => completion.host_action_id),
  );
  const records = (store.host_action_runs ?? []).filter((record) =>
    completionIds.has(record.host_action_id),
  );
  const record =
    records.find((candidate) => candidate.status === "pending") ??
    records.at(-1);
  if (!record) {
    return null;
  }

  return {
    sessionId: record.session_id,
    conversationId: record.conversation_id,
    source: record.source,
  };
}

function markHostActionRunsCompleted(
  store: RuntimeStore,
  completions: RuntimeHostActionCompletion[],
): void {
  if (!store.host_action_runs || completions.length === 0) {
    return;
  }

  const now = new Date().toISOString();
  const completionStatuses = new Map<string, RuntimeHostActionRunRecord["status"]>(
    completions.map((completion) => [
      completion.host_action_id,
      completion.status === "succeeded" ? "completed" : "failed",
    ]),
  );
  store.host_action_runs = store.host_action_runs.map((record) => {
    const status = completionStatuses.get(record.host_action_id);
    if (!status) {
      return record;
    }
    return {
      ...record,
      status,
      updated_at: now,
    };
  });
}

function gearCompletionFailureReply(
  userRequest: string,
  completions: RuntimeHostActionCompletion[],
  reason: string,
  sdkTurn?: SdkTurnResult,
): string {
  const failed = completions.filter((completion) => completion.status !== "succeeded");
  if (failed.length > 0) {
    const details = failed.map((completion) =>
      completion.error || completion.summary || `${completion.tool_id} failed`
    );
    return `The Gear action did not complete: ${details.join("; ")}`;
  }

  const summaries = completions
    .map((completion) => completion.summary?.trim())
    .filter((summary): summary is string => Boolean(summary));
  const successfulToolSummaries = successfulToolResultSummaries(sdkTurn);
  const header = successfulToolSummaries.length > 0
      ? "Some Gear and follow-up local steps returned successfully, but the final agent-written reply timed out, so the user objective is not confirmed complete. The structured result was recorded in the tool steps."
      : "The Gear step returned successfully, but the final agent-written reply timed out, so the user objective is not confirmed complete. The structured result was recorded in the tool steps.";

  const sections: string[] = [];
  if (summaries.length > 0) {
    sections.push(summaries.join("\n"));
  }
  if (successfulToolSummaries.length > 0) {
    sections.push(`Follow-up completed steps:\n${successfulToolSummaries.map((summary) => `- ${summary}`).join("\n")}`);
  }

  if (sections.length > 0) {
    return `${header}\n\n${sections.join("\n\n")}`;
  }

  return `${header}\n\nSummary failure reason: ${reason}`;
}

function successfulToolResultSummaries(sdkTurn?: SdkTurnResult): string[] {
  if (!sdkTurn) {
    return [];
  }
  const toolNamesById = new Map<string, string>();
  for (const event of sdkTurn.tool_events) {
    if (event.kind === "invocation") {
      toolNamesById.set(event.invocation_id, event.tool_name);
    }
  }

  return sdkTurn.tool_events
    .filter(
      (event): event is Extract<SdkToolEvent, { kind: "result" }> =>
        event.kind === "result" && event.status === "succeeded",
    )
    .map((event) => {
      const toolName = toolNamesById.get(event.invocation_id) ?? "Tool";
      const summary = event.summary?.trim();
      return summary ? `${toolName}: ${summarizePrompt(summary, 220)}` : null;
    })
    .filter((summary): summary is string => Boolean(summary))
    .slice(-3);
}

function unresumableHostActionReply(
  userRequest: string,
  completions: RuntimeHostActionCompletion[],
  reason: string,
  legacyFallback: boolean,
): string {
  const failed = completions.filter((completion) => completion.status !== "succeeded");
  if (failed.length > 0) {
    const details = failed.map((completion) =>
      completion.error || completion.summary || `${completion.tool_id} failed`
    );
    return `The Gear action did not complete: ${details.join("; ")}`;
  }

  const summaries = completions
    .map((completion) => completion.summary?.trim())
    .filter((summary): summary is string => Boolean(summary));
  const header = legacyFallback
      ? "A legacy native Gear fallback completion arrived, but fallback execution is now prohibited, so GeeAgent marked this turn failed. The structured result was recorded in the tool steps."
      : "The Gear action completed, but the same SDK run could not be resumed. GeeAgent did not start a detached completion turn; the structured result was recorded in the tool steps.";

  if (summaries.length > 0) {
    return `${header}\n\n${summaries.join("\n")}`;
  }

  return `${header}\n\n${reason}`;
}

function lastRunStopReason(store: RuntimeStore): string | null {
  const value = store.last_run_state;
  return isRecord(value) ? stringField(value, "stop_reason") ?? null : null;
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
  const readiness = await loadChatReadiness(configDir);
  if (readiness.status !== "live") {
    recordRuntimeUnavailableTurn(store, route, text, readiness);
    return;
  }

  const transientPrepared: PreparedTurnContext = {
    ...prepared,
    workspaceMessages: [],
    stageCapsuleMessages: [],
    shouldReuseActiveConversation: true,
  };
  const runtimeSessionId = transientRuntimeSessionId(text);
  let sdkTurn: SdkTurnResult;
  try {
    const gearBridgeFirst = requiresGeeGearBridgeFirst(text);
    sdkTurn = await runSdkRuntimeTurn(
      configDir,
      runtimeSessionId,
      route,
      transientPrepared.activeAgentProfile,
      composeClaudeSdkTurnPrompt(route, transientPrepared, text),
      [],
      {
        toolBoundaryMode: gearBridgeFirst ? "gear_first" : "default",
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

  if (
    sdkTurn.pending_terminal_approval ||
    (sdkTurn.pending_host_actions && sdkTurn.pending_host_actions.length > 0) ||
    sdkTurn.terminal_access_denied_reason
  ) {
    await applyClaudeSdkTurn(store, configDir, route, prepared, text);
    return;
  }

  markMissingAssistantReplyAsFailure(sdkTurn, "during the transient quick reply");
  if (sdkTurn.failed_reason) {
    sdkTurn.assistant_chunks = [
      claudeSdkFailureAssistantReply(sdkTurn.failed_reason),
    ];
  }
  const assistantReply = assistantReplyFromTurn(
    sdkTurn,
    "The SDK runtime ended without a final assistant reply.",
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
  markMissingAssistantReplyAsFailure(sdkTurn, "without a final assistant reply");
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
    "The SDK runtime ended without a final assistant reply.",
  );
  appendAssistantMessageForActiveConversation(
    store,
    cursor.sessionId,
    assistantReply,
    cursor.assistantMessageId,
  );
  const stageCapsule = stageSummaryCapsuleForTurn(store, cursor, sdkTurn, assistantReply);
  finalizeTurnReplay(
    store,
    cursor,
    sdkTurn.failed_reason
      ? "the SDK runtime surfaced a real runtime failure and GeeAgent committed that failed turn back into the active conversation"
      : "the SDK runtime completed the active turn and committed the resulting tool trace back into GeeAgent",
    stageCapsule,
  );
  return assistantReply;
}

function recordLiveClaudeSdkTurnCompletion(
  store: RuntimeStore,
  cursor: TurnReplayCursor,
  sdkTurn: SdkTurnResult,
  runPlan?: RuntimeRunPlan | null,
): string {
  markMissingAssistantReplyAsFailure(sdkTurn, "without a final assistant reply");
  if (sdkTurn.auto_approved_tools > 0) {
    appendSessionStateForSession(
      store,
      cursor.sessionId,
      `the host auto-approved ${sdkTurn.auto_approved_tools} SDK tool request(s) during this runtime run`,
    );
  }

  if (runPlan) {
    appendStageConclusionForSession(
      store,
      cursor.sessionId,
      runPlan,
      sdkTurn.failed_reason ? "blocked" : "completed",
      sdkTurn.failed_reason
        ? `Stage blocked by runtime failure: ${sdkTurn.failed_reason}`
        : "Stage completed by the active SDK run.",
    );
  }

  const assistantReply = assistantReplyFromTurn(
    sdkTurn,
    "The SDK runtime ended without a final assistant reply.",
  );
  appendAssistantMessageForActiveConversation(
    store,
    cursor.sessionId,
    assistantReply,
    cursor.assistantMessageId,
  );
  const stageCapsule = stageSummaryCapsuleForTurn(
    store,
    cursor,
    sdkTurn,
    assistantReply,
    runPlan,
  );
  finalizeTurnReplay(
    store,
    cursor,
    sdkTurn.failed_reason
      ? "the SDK runtime surfaced a real runtime failure and GeeAgent committed that failed turn back into the active conversation"
      : "the SDK runtime completed the active turn and committed the resulting tool trace back into GeeAgent",
    stageCapsule,
  );
  return assistantReply;
}

function stageSummaryCapsuleForTurn(
  store: RuntimeStore,
  cursor: TurnReplayCursor,
  sdkTurn: SdkTurnResult,
  assistantReply: string,
  runPlan?: RuntimeRunPlan | null,
): string {
  const status: StageSummaryStatus = sdkTurn.failed_reason ? "failed" : "succeeded";
  const latestUserRequest = userMessageContentForCursor(store, cursor) ?? "";
  const capsule = buildStageSummaryCapsule({
    stage_id: runPlan?.current_stage_id ?? cursor.sessionId,
    run_id: runPlan?.plan_id ?? cursor.sessionId,
    session_id: cursor.sessionId,
    status,
    objective: runPlan?.stages.find((stage) => stage.stage_id === runPlan.current_stage_id)?.objective ??
      summarizePrompt(latestUserRequest, 240),
    latest_user_request: latestUserRequest,
    completed_steps: status === "succeeded" ? [assistantReply] : [],
    blockers: sdkTurn.failed_reason ? [sdkTurn.failed_reason] : [],
    next_steps: sdkTurn.failed_reason
      ? ["Recover from the recorded runtime failure before claiming completion."]
      : [],
    tool_records: stageToolRecordsFromTurn(sdkTurn),
  });
  return renderStageSummaryCapsule(capsule);
}

function stageToolRecordsFromTurn(sdkTurn: SdkTurnResult) {
  const resultsById = new Map(
    sdkTurn.tool_events
      .filter((event) => event.kind === "result")
      .map((event) => [event.invocation_id, event]),
  );
  return sdkTurn.tool_events
    .filter((event) => event.kind === "invocation")
    .map((invocation) => {
      const result = resultsById.get(invocation.invocation_id);
      const status: StageSummaryStatus = result?.status ?? "running";
      return {
        invocation_id: invocation.invocation_id,
        tool_name: invocation.tool_name,
        status,
        input_summary: invocation.input_summary ?? null,
        output_summary: result?.summary ?? null,
        error: result?.error ?? null,
        artifact_refs: (result?.artifacts ?? []).map(stageArtifactRefFromSdk),
      };
    });
}

function stageArtifactRefFromSdk(artifact: {
  artifactId: string;
  type: string;
  title: string;
  payloadRef: string;
  inlinePreviewSummary?: string;
}): StageSummaryArtifactRef {
  return {
    artifact_id: artifact.artifactId,
    kind: artifact.type,
    path: artifact.payloadRef,
    title: artifact.title,
    summary: artifact.inlinePreviewSummary,
  };
}

function userMessageContentForCursor(
  store: RuntimeStore,
  cursor: TurnReplayCursor,
): string | null {
  const executionSession = store.execution_sessions.find(
    (session) => isRecord(session) && session.session_id === cursor.sessionId,
  );
  const conversationId =
    (isRecord(executionSession) ? stringField(executionSession, "conversation_id") : null) ??
    (cursor.sessionId.startsWith("session_")
      ? cursor.sessionId.slice("session_".length)
      : store.active_conversation_id);
  const conversation = store.conversations.find(
    (candidate) => candidate.conversation_id === conversationId,
  );
  const found = conversation?.messages.find(
    (message) => message.message_id === cursor.userMessageId && message.role === "user",
  );
  return found?.content ?? null;
}

export const __turnTestHooks = {
  applyModelOnlyStageConclusionsForTurn,
  composeClaudeSdkTurnPrompt,
  gearCompletionFailureReply,
  isTransientQuickPrompt,
  markMissingAssistantReplyAsFailure,
  prepareTurnContext,
  routeQuickPromptToBestConversation,
  stageSummaryCapsuleForTurn,
  successfulToolResultSummaries,
  userMessageContentForCursor,
};
