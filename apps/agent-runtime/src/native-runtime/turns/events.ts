import { activeConversation } from "../store/conversations.js";
import { currentTimestamp } from "../store/defaults.js";
import type { RuntimeConversation, RuntimeStore } from "../store/types.js";
import { runtimeProjectPath } from "../paths.js";
import type { SdkToolArtifactRef, SdkToolEvent, TurnRoute } from "../sdk-turn-runner.js";
import { isRecord, summarizePrompt } from "./state.js";
import type { JsonRecord, TurnReplayCursor } from "./types.js";
import type { RuntimeRunPlan } from "./planning.js";

const ITERATIVE_TURN_MAX_STEPS = 8;

export function beginTurnReplay(
  store: RuntimeStore,
  surface: TurnRoute["surface"],
  userContent: string,
): TurnReplayCursor {
  const [sessionId, userMessageId] = appendUserMessageForActiveConversation(
    store,
    surface,
    userContent,
  );
  const assistantMessageId = nextAssistantMessageIdForActiveConversation(store);
  appendSessionStateForSession(store, sessionId, turnSetupSummary(surface));
  return { sessionId, userMessageId, assistantMessageId, stepCount: 0 };
}

function appendUserMessageForActiveConversation(
  store: RuntimeStore,
  surface: TurnRoute["surface"],
  content: string,
): [string, string] {
  const sessionId = ensureExecutionSessionForActiveConversation(store, surface);
  const conversation = activeConversation(store);
  const messageId = userMessageId(conversation);
  conversation.messages.push({
    message_id: messageId,
    role: "user",
    content,
    timestamp: currentTimestamp(),
  });
  conversation.status = "active";
  appendTranscriptEvent(store, sessionId, {
    kind: "user_message",
    message_id: messageId,
    content,
  });
  return [sessionId, messageId];
}

export function appendAssistantMessageForActiveConversation(
  store: RuntimeStore,
  sessionId: string,
  content: string,
  messageId?: string,
): string {
  const conversation = activeConversation(store);
  const resolvedMessageId = messageId ?? assistantMessageId(conversation);
  const trimmed = content.trim();
  conversation.messages.push({
    message_id: resolvedMessageId,
    role: "assistant",
    content: trimmed,
    timestamp: currentTimestamp(),
  });
  conversation.status = "active";
  appendTranscriptEvent(store, sessionId, {
    kind: "assistant_message",
    message_id: resolvedMessageId,
    content: trimmed,
  });
  return resolvedMessageId;
}

export function appendAssistantDeltaForActiveConversation(
  store: RuntimeStore,
  sessionId: string,
  delta: string,
  messageId?: string,
): string | null {
  if (!delta) {
    return null;
  }
  const conversation = activeConversation(store);
  const resolvedMessageId = messageId ?? assistantMessageId(conversation);
  appendTranscriptEvent(store, sessionId, {
    kind: "assistant_message_delta",
    message_id: resolvedMessageId,
    delta,
  });
  return resolvedMessageId;
}

function nextAssistantMessageIdForActiveConversation(store: RuntimeStore): string {
  return assistantMessageId(activeConversation(store));
}

export function appendSessionStateForSession(
  store: RuntimeStore,
  sessionId: string,
  summary: string,
): void {
  appendTranscriptEvent(store, sessionId, {
    kind: "session_state_changed",
    summary,
  });
}

export function appendRunPlanForSession(
  store: RuntimeStore,
  sessionId: string,
  plan: RuntimeRunPlan,
): void {
  appendTranscriptEvent(store, sessionId, {
    kind: "run_plan_created",
    run_plan: plan as unknown as JsonRecord,
    summary: `Run plan created with ${plan.stages.length} stage(s).`,
  });
}

export function appendRunPlanUpdatedForSession(
  store: RuntimeStore,
  sessionId: string,
  plan: RuntimeRunPlan,
  summary: string,
): void {
  appendTranscriptEvent(store, sessionId, {
    kind: "run_plan_updated",
    run_plan: plan as unknown as JsonRecord,
    run_plan_id: plan.plan_id,
    current_stage_id: plan.current_stage_id,
    summary,
  });
}

export function appendCapabilityFocusForSession(
  store: RuntimeStore,
  sessionId: string,
  plan: RuntimeRunPlan,
): void {
  appendTranscriptEvent(store, sessionId, {
    kind: "capability_focus_locked",
    run_plan_id: plan.plan_id,
    stage_id: plan.focus.stage_id,
    focus_gear_ids: plan.focus.focus_gear_ids,
    focus_capability_ids: plan.focus.focus_capability_ids,
    summary:
      plan.focus.focus_capability_ids.length > 0
        ? `Capability focus locked to ${plan.focus.focus_capability_ids.join(", ")}.`
        : "Capability focus has no preselected capability ids; discovery remains scoped by the active plan.",
  });
}

export function appendStageStartedForSession(
  store: RuntimeStore,
  sessionId: string,
  plan: RuntimeRunPlan,
): void {
  const stage = plan.stages.find((candidate) => candidate.stage_id === plan.current_stage_id);
  appendTranscriptEvent(store, sessionId, {
    kind: "stage_started",
    run_plan_id: plan.plan_id,
    stage_id: plan.current_stage_id,
    title: stage?.title ?? plan.current_stage_id,
    objective: stage?.objective ?? null,
    required_capabilities: stage?.required_capabilities ?? [],
    summary: stage
      ? `Stage started: ${stage.title}. ${stage.objective}`
      : `Stage started: ${plan.current_stage_id}.`,
  });
}

export function appendStageConclusionForSession(
  store: RuntimeStore,
  sessionId: string,
  plan: RuntimeRunPlan,
  status: "completed" | "partial" | "blocked" | "plan_changed" | "needs_user_input",
  summary: string,
): void {
  const stage = plan.stages.find((candidate) => candidate.stage_id === plan.current_stage_id);
  appendTranscriptEvent(store, sessionId, {
    kind: "stage_concluded",
    run_plan_id: plan.plan_id,
    stage_id: plan.current_stage_id,
    title: stage?.title ?? plan.current_stage_id,
    status,
    summary,
  });
}

export function latestRunPlanForSession(
  store: RuntimeStore,
  sessionId: string,
): RuntimeRunPlan | null {
  const plans = store.transcript_events
    .filter((event) => isRecord(event) && event.session_id === sessionId)
    .map((event) => (isRecord(event) ? event.payload : null))
    .filter((payload): payload is Record<string, unknown> => isRecord(payload))
    .filter((payload) => payload.kind === "run_plan_created" || payload.kind === "run_plan_updated")
    .map((payload) => payload.run_plan)
    .filter(isRuntimeRunPlan);
  return plans.at(-1) ?? null;
}

export function appendTurnStep(
  cursor: TurnReplayCursor,
  store: RuntimeStore,
  detail: string,
): void {
  cursor.stepCount += 1;
  appendSessionStateForSession(
    store,
    cursor.sessionId,
    turnStepSummary(cursor.stepCount, detail),
  );
}

export function finalizeTurnReplay(
  store: RuntimeStore,
  cursor: TurnReplayCursor,
  reason: string,
  stageCapsule?: string,
): void {
  const payload: JsonRecord = {
    kind: "session_state_changed",
    summary: turnFinalizeSummary(Math.max(cursor.stepCount, 1), reason),
  };
  if (stageCapsule?.trim()) {
    payload.stage_capsule = stageCapsule;
  }
  appendTranscriptEvent(store, cursor.sessionId, payload);
}

export function appendToolEvents(
  store: RuntimeStore,
  sessionId: string,
  originatingMessageId: string,
  events: SdkToolEvent[],
): void {
  for (const event of events) {
    if (event.kind === "invocation") {
      appendTranscriptEvent(store, sessionId, {
        kind: "tool_invocation",
        invocation: {
          invocation_id: event.invocation_id,
          session_id: sessionId,
          originating_message_id: originatingMessageId,
          tool_name: event.tool_name,
          input_summary: event.input_summary ?? null,
          status: "running",
          approval_request_id: null,
          created_at: "now",
          updated_at: "now",
        },
      });
    } else {
      appendTranscriptEvent(store, sessionId, {
        kind: "tool_result",
        invocation_id: event.invocation_id,
        status: event.status,
        summary: event.summary ?? null,
        error: event.error ?? null,
        artifacts: transcriptArtifacts(event.artifacts),
      });
    }
  }
}

export function appendToolResultForExistingInvocation(
  store: RuntimeStore,
  sessionId: string,
  invocationId: string,
  status: "succeeded" | "failed",
  summary?: string,
  error?: string,
  artifacts: SdkToolArtifactRef[] = [],
): void {
  const hasInvocation = store.transcript_events.some(
    (event) =>
      isRecord(event) &&
      event.session_id === sessionId &&
      isRecord(event.payload) &&
      event.payload.kind === "tool_invocation" &&
      isRecord(event.payload.invocation) &&
      event.payload.invocation.invocation_id === invocationId,
  );
  const hasResult = store.transcript_events.some(
    (event) =>
      isRecord(event) &&
      event.session_id === sessionId &&
      isRecord(event.payload) &&
      event.payload.kind === "tool_result" &&
      event.payload.invocation_id === invocationId,
  );
  if (!hasInvocation || hasResult) {
    return;
  }
  appendTranscriptEvent(store, sessionId, {
    kind: "tool_result",
    invocation_id: invocationId,
    status,
    summary: summary ?? null,
    error: error ?? null,
    artifacts: transcriptArtifacts(artifacts),
  });
}

export function appendToolResultForHostBridgeCompletion(
  store: RuntimeStore,
  sessionId: string,
  toolID: string,
  status: "succeeded" | "failed",
  summary?: string,
  error?: string,
): void {
  const toolName = hostBridgeToolName(toolID);
  if (!toolName) {
    return;
  }

  const completed = new Set<string>();
  for (const event of store.transcript_events) {
    if (!isRecord(event) || event.session_id !== sessionId) {
      continue;
    }
    const payload = event.payload;
    if (
      isRecord(payload) &&
      payload.kind === "tool_result" &&
      typeof payload.invocation_id === "string"
    ) {
      completed.add(payload.invocation_id);
    }
  }

  for (let index = 0; index < store.transcript_events.length; index += 1) {
    const event = store.transcript_events[index];
    if (
      !isRecord(event) ||
      event.session_id !== sessionId ||
      !isRecord(event.payload) ||
      event.payload.kind !== "tool_invocation" ||
      !isRecord(event.payload.invocation)
    ) {
      continue;
    }
    const invocation = event.payload.invocation;
    if (
      invocation.tool_name === toolName &&
      typeof invocation.invocation_id === "string" &&
      !completed.has(invocation.invocation_id)
    ) {
      appendTranscriptEvent(store, sessionId, {
        kind: "tool_result",
        invocation_id: invocation.invocation_id,
        status,
        summary: summary ?? null,
        error: error ?? null,
        artifacts: [],
      });
      return;
    }
  }
}

function hostBridgeToolName(toolID: string): string | null {
  switch (toolID) {
    case "gee.app.openSurface":
      return "app_open_surface";
    case "gee.gear.listCapabilities":
      return "gear_list_capabilities";
    case "gee.gear.invoke":
      return "gear_invoke";
    default:
      return null;
  }
}

export function appendTranscriptEvent(
  store: RuntimeStore,
  sessionId: string,
  payload: JsonRecord,
): void {
  const eventId = nextTranscriptEventId(store, sessionId);
  const parentEventId = lastTranscriptEventId(store, sessionId);
  store.transcript_events.push({
    event_id: eventId,
    session_id: sessionId,
    parent_event_id: parentEventId,
    created_at: "now",
    payload,
  });
  const session = store.execution_sessions.find(
    (candidate) => isRecord(candidate) && candidate.session_id === sessionId,
  );
  if (isRecord(session)) {
    session.updated_at = "now";
  }
}

export function ensureExecutionSessionForActiveConversation(
  store: RuntimeStore,
  surface: TurnRoute["surface"],
): string {
  const conversation = activeConversation(store);
  return ensureExecutionSessionForConversation(store, conversation.conversation_id, surface);
}

function ensureExecutionSessionForConversation(
  store: RuntimeStore,
  conversationId: string,
  surface: TurnRoute["surface"],
): string {
  const sessionId = executionSessionIdForConversation(conversationId);
  const existing = store.execution_sessions.find(
    (session) => isRecord(session) && session.session_id === sessionId,
  );
  if (isRecord(existing)) {
    existing.surface = surface;
    existing.updated_at = "now";
    if (!existing.project_path) {
      existing.project_path = runtimeProjectPath();
    }
    return sessionId;
  }
  store.execution_sessions.push({
    session_id: sessionId,
    conversation_id: conversationId,
    surface,
    mode: "interactive",
    project_path: runtimeProjectPath(),
    parent_session_id: null,
    persistence_policy: "persisted",
    created_at: "now",
    updated_at: "now",
  });
  return sessionId;
}

function activeConversationId(store: RuntimeStore): string | null {
  return activeConversation(store).conversation_id ?? null;
}

export function executionSessionIdForConversation(conversationId: string): string {
  return `session_${conversationId}`;
}

function nextTranscriptEventId(store: RuntimeStore, sessionId: string): string {
  const count = store.transcript_events.filter(
    (event) => isRecord(event) && event.session_id === sessionId,
  ).length;
  return `event_${sessionId}_${String(count + 1).padStart(2, "0")}`;
}

function lastTranscriptEventId(store: RuntimeStore, sessionId: string): string | null {
  const found = [...store.transcript_events]
    .reverse()
    .find((event) => isRecord(event) && event.session_id === sessionId);
  return isRecord(found) && typeof found.event_id === "string" ? found.event_id : null;
}

function userMessageId(conversation: RuntimeConversation): string {
  return `msg_user_${String(conversation.messages.length + 1).padStart(2, "0")}`;
}

function assistantMessageId(conversation: RuntimeConversation): string {
  return `msg_assistant_${String(conversation.messages.length + 2).padStart(2, "0")}`;
}

function isRuntimeRunPlan(value: unknown): value is RuntimeRunPlan {
  return (
    isRecord(value) &&
    typeof value.plan_id === "string" &&
    value.phase === "phase3.6" &&
    typeof value.current_stage_id === "string" &&
    Array.isArray(value.stages) &&
    isRecord(value.focus)
  );
}

export function quickTaskId(store: RuntimeStore): string {
  return `task_quick_${String(store.tasks.length + 1).padStart(2, "0")}`;
}

export function quickModuleRunId(store: RuntimeStore): string {
  return `run_quick_${String(store.module_runs.length + 1).padStart(2, "0")}`;
}

export function nextApprovalRequestIdForTask(store: RuntimeStore, taskId: string): string {
  const existingCount = store.approval_requests.filter(
    (approval) => isRecord(approval) && approval.task_id === taskId,
  ).length;
  return existingCount === 0
    ? `apr_${taskId}`
    : `apr_${taskId}_${existingCount + 1}`;
}

function turnSetupSummary(surface: TurnRoute["surface"]): string {
  const now = new Date().toLocaleString(undefined, { timeZoneName: "short" });
  const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone || "local";
  return `Turn setup complete. GeeAgent grounded local time ${summarizePrompt(now, 40)}, time zone ${summarizePrompt(timezone, 32)}, cwd ${summarizePrompt(runtimeProjectPath(), 64)}, and the active ${surface} surface.`;
}

function turnStepSummary(stepIndex: number, detail: string): string {
  return `Step ${stepIndex}/${ITERATIVE_TURN_MAX_STEPS}: ${summarizePrompt(detail, 120)}`;
}

function turnFinalizeSummary(stepCount: number, reason: string): string {
  return `Turn finalized after ${stepCount} grounded step${stepCount === 1 ? "" : "s"}: ${summarizePrompt(reason, 120)}`;
}

function transcriptArtifacts(artifacts: SdkToolArtifactRef[] | undefined): JsonRecord[] {
  return (artifacts ?? []).map((artifact) => ({
    artifactId: artifact.artifactId,
    type: artifact.type,
    title: artifact.title,
    payloadRef: artifact.payloadRef,
    inlinePreviewSummary: artifact.inlinePreviewSummary ?? null,
  }));
}
