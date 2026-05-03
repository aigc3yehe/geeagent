import { currentTimestamp } from "./defaults.js";
import type { RuntimeStore } from "./types.js";

export type RuntimeRunReplayExport = {
  schema_version: 1;
  run_id: string;
  exported_at: string;
  event_count: number;
  conversation_ids: string[];
  execution_session_ids: string[];
  sdk_session_ids: string[];
  parent_run_ids: string[];
  host_action_runs: Record<string, unknown>[];
  approval_requests: Record<string, unknown>[];
  artifact_ids: string[];
  artifact_refs: RuntimeRunArtifactRef[];
  diagnostics: {
    duplicate_event_ids: string[];
    missing_parent_event_ids: string[];
    missing_sequence_numbers: number[];
    out_of_order_event_ids: string[];
  };
  events: Record<string, unknown>[];
};

export type RuntimeRunReplayProjection = {
  schema_version: 1;
  run_id: string;
  row_count: number;
  artifact_ids: string[];
  artifact_refs: RuntimeRunArtifactRef[];
  diagnostics: RuntimeRunReplayExport["diagnostics"];
  rows: RuntimeRunProjectionRow[];
};

export type RuntimeRunArtifactRef = {
  artifact_id: string;
  kind: string | null;
  title: string | null;
  path: string | null;
  summary: string | null;
  sha256: string | null;
  byte_count: number | null;
  token_estimate: number | null;
  mime_type: string | null;
  source_event_id: string | null;
  source_event_sequence: number | null;
  source_invocation_id: string | null;
  source_tool_name: string | null;
  source_host_action_id: string | null;
};

export type RuntimeRunProjectionRow = {
  row_id: string;
  run_id: string;
  sequence: number;
  event_id: string | null;
  event_kind: string;
  projection_kind:
    | "user_message"
    | "assistant_delta"
    | "assistant_message"
    | "plan"
    | "focus"
    | "stage"
    | "tool"
    | "tool_result"
    | "stage_capsule"
    | "runtime_state"
    | "diagnostic";
  label: string;
  status: string | null;
  summary: string;
  stage_id: string | null;
  tool_name: string | null;
  projection_scope: "main_timeline" | "worked" | "inspector";
  expandable: boolean;
  artifact_ids: string[];
};

export type RuntimeRunWaitKind =
  | "completed"
  | "model_wait"
  | "host_wait"
  | "tool_wait"
  | "approval_wait"
  | "event_silence"
  | "store_mirror_failure"
  | "session_lost";

export type RuntimeRunWaitClassification = {
  run_id: string;
  wait_kind: RuntimeRunWaitKind;
  status: "complete" | "waiting" | "blocked" | "failed" | "diagnostic";
  detail: string;
  evidence: {
    run_id: string;
    last_event_kind: string | null;
    last_event_sequence: number | null;
    last_tool_use_id: string | null;
    pending_tool_use_id: string | null;
    pending_host_action_ids: string[];
    pending_host_action_payloads: Record<string, unknown>[];
    pending_approval_id: string | null;
    sdk_session_id: string | null;
    gateway_request_id: string | null;
    diagnostics: RuntimeRunReplayExport["diagnostics"];
  };
};

export function exportRuntimeRun(
  store: RuntimeStore,
  runId: string,
): RuntimeRunReplayExport {
  const normalizedRunId = runId.trim();
  if (!normalizedRunId) {
    throw new Error("export-runtime-run requires a non-empty run_id");
  }

  const events = store.transcript_events
    .map((event, sourceIndex) => ({ event, sourceIndex }))
    .filter(({ event }) => eventRunId(event) === normalizedRunId)
    .map(({ event, sourceIndex }, runIndex) => {
      const cloned = cloneRecord(event);
      const payload = isRecord(cloned.payload) && !stringField(cloned.payload, "run_id")
        ? { ...cloned.payload, run_id: normalizedRunId }
        : cloned.payload;
      return {
        ...cloned,
        payload,
        run_id: normalizedRunId,
        sequence: numberField(cloned, "sequence") ?? runIndex + 1,
        source_index: sourceIndex,
      };
    });

  if (events.length === 0) {
    throw new Error(`runtime run \`${normalizedRunId}\` has no transcript events`);
  }

  const executionSessionIds = uniqueStrings(
    events.map((event) => stringField(event, "session_id")),
  );
  const executionSessions = store.execution_sessions
    .filter((session) => {
      const sessionId = stringField(session, "session_id");
      return sessionId ? executionSessionIds.includes(sessionId) : false;
    })
    .map(cloneRecord);
  const hostActionRuns = (store.host_action_runs ?? [])
    .filter((record) => record.run_id === normalizedRunId)
    .map((record) => cloneRecord(record as unknown));
  const approvalRequests = store.approval_requests
    .filter((request) => approvalRunId(request) === normalizedRunId)
    .map(cloneRecord);
  const material = [...events, ...hostActionRuns, ...approvalRequests];
  const artifactRefs = collectRunArtifactRefs(
    events,
    hostActionRuns,
    approvalRequests,
    toolNameByInvocationId(events),
  );

  return {
    schema_version: 1,
    run_id: normalizedRunId,
    exported_at: currentTimestamp(),
    event_count: events.length,
    conversation_ids: uniqueStrings(
      executionSessions.map((session) => stringField(session, "conversation_id")),
    ),
    execution_session_ids: executionSessionIds,
    sdk_session_ids: collectNamedStrings(material, ["sdk_session_id", "runtime_session_id"]),
    parent_run_ids: collectNamedStrings(material, ["parent_run_id"]),
    host_action_runs: hostActionRuns,
    approval_requests: approvalRequests,
    artifact_ids: artifactIdsFromRefs(artifactRefs),
    artifact_refs: artifactRefs,
    diagnostics: eventDiagnostics(events),
    events,
  };
}

export function projectRuntimeRun(
  store: RuntimeStore,
  runId: string,
): RuntimeRunReplayProjection {
  return projectRuntimeRunReplay(exportRuntimeRun(store, runId));
}

export function projectRuntimeRunReplay(input: unknown): RuntimeRunReplayProjection {
  const replay = normalizeReplayImport(input);
  const sortedEvents = [...replay.events].sort((left, right) => {
    const leftSequence = numberField(left, "sequence") ?? Number.MAX_SAFE_INTEGER;
    const rightSequence = numberField(right, "sequence") ?? Number.MAX_SAFE_INTEGER;
    if (leftSequence !== rightSequence) {
      return leftSequence - rightSequence;
    }
    return (numberField(left, "source_index") ?? 0) - (numberField(right, "source_index") ?? 0);
  });
  const rows = sortedEvents.map((event, index) =>
    projectReplayEvent(replay.run_id, event, index + 1),
  );
  return {
    schema_version: 1,
    run_id: replay.run_id,
    row_count: rows.length,
    artifact_ids: replay.artifact_ids,
    artifact_refs: replay.artifact_refs,
    diagnostics: eventDiagnostics(replay.events),
    rows,
  };
}

export function classifyRuntimeRunWait(
  store: RuntimeStore,
  runId: string,
): RuntimeRunWaitClassification {
  const normalizedRunId = runId.trim();
  if (!normalizedRunId) {
    throw new Error("classify-runtime-run-wait requires a non-empty run_id");
  }
  const events = normalizedRunEvents(store, normalizedRunId);
  const diagnostics = eventDiagnostics(events);
  const lastEvent = events.at(-1) ?? null;
  const lastPayload = isRecord(lastEvent?.payload) ? lastEvent.payload : {};
  const lastEventKind = stringField(lastPayload, "kind");
  const pendingToolUseIds = pendingToolInvocationIds(events);
  const pendingHostActionIds = (store.host_action_runs ?? [])
    .filter((record) => record.run_id === normalizedRunId && record.status === "pending")
    .map((record) => record.host_action_id);
  const pendingHostActionPayloads = pendingHostActionIds
    .map((hostActionId) => pendingHostActionPayload(store, hostActionId))
    .filter((payload): payload is Record<string, unknown> => Boolean(payload));
  const pendingApproval = store.approval_requests.find(
    (request) => approvalRunId(request) === normalizedRunId && isOpenApproval(request),
  );
  const material = [
    ...events,
    ...(store.host_action_runs ?? []).filter((record) => record.run_id === normalizedRunId),
    ...(pendingApproval ? [pendingApproval] : []),
  ];
  const evidence: RuntimeRunWaitClassification["evidence"] = {
    run_id: normalizedRunId,
    last_event_kind: lastEventKind,
    last_event_sequence: lastEvent ? numberField(lastEvent, "sequence") : null,
    last_tool_use_id: latestToolUseId(events),
    pending_tool_use_id: pendingToolUseIds[0] ?? null,
    pending_host_action_ids: pendingHostActionIds,
    pending_host_action_payloads: pendingHostActionPayloads,
    pending_approval_id: isRecord(pendingApproval)
      ? stringField(pendingApproval, "approval_request_id")
      : null,
    sdk_session_id: collectNamedStrings(material, ["sdk_session_id", "runtime_session_id"])[0] ?? null,
    gateway_request_id: collectNamedStrings(material, ["gateway_request_id", "runtime_request_id"])[0] ?? null,
    diagnostics,
  };

  const lastRunStopReason = lastRunStopReasonForRun(store, normalizedRunId);
  if (lastRunStopReason === "sdk_host_action_session_lost") {
    return waitClassification(
      normalizedRunId,
      "session_lost",
      "failed",
      "The SDK session lineage was lost while GeeAgent was handling host-action results.",
      evidence,
    );
  }
  if (pendingApproval) {
    return waitClassification(
      normalizedRunId,
      "approval_wait",
      "waiting",
      "The run is waiting for an approval decision.",
      evidence,
    );
  }
  if (pendingHostActionIds.length > 0) {
    return waitClassification(
      normalizedRunId,
      "host_wait",
      "waiting",
      "The run is waiting for native host action results.",
      evidence,
    );
  }
  if (pendingToolUseIds.length > 0) {
    return waitClassification(
      normalizedRunId,
      "tool_wait",
      "waiting",
      "The run has an SDK tool invocation without a matching tool result.",
      evidence,
    );
  }
  if (events.length === 0) {
    return waitClassification(
      normalizedRunId,
      "event_silence",
      "diagnostic",
      "No transcript events exist for this run id.",
      evidence,
    );
  }
  if (
    diagnostics.duplicate_event_ids.length > 0 ||
    diagnostics.missing_parent_event_ids.length > 0 ||
    diagnostics.missing_sequence_numbers.length > 0 ||
    diagnostics.out_of_order_event_ids.length > 0
  ) {
    return waitClassification(
      normalizedRunId,
      "store_mirror_failure",
      "diagnostic",
      "The run event mirror has replay diagnostics that must be inspected before trusting projection state.",
      evidence,
    );
  }
  if (lastEventKind === "assistant_message") {
    return waitClassification(
      normalizedRunId,
      "completed",
      "complete",
      "The run has produced its final assistant message and has no pending host action, approval, or unmatched tool invocation.",
      evidence,
    );
  }
  return waitClassification(
    normalizedRunId,
    "model_wait",
    "waiting",
    "The run has events but no pending host action, approval, or unmatched tool invocation.",
    evidence,
  );
}

function normalizeReplayImport(input: unknown): RuntimeRunReplayExport {
  if (!isRecord(input) || input.schema_version !== 1) {
    throw new Error("runtime replay import requires schema_version 1");
  }
  const runId = stringField(input, "run_id");
  if (!runId) {
    throw new Error("runtime replay import requires a non-empty run_id");
  }
  const rawEvents = Array.isArray(input.events) ? input.events : null;
  if (!rawEvents) {
    throw new Error("runtime replay import requires an events array");
  }
  const events = rawEvents.map((event, index) => normalizeReplayEvent(runId, event, index));
  const hostActionRuns = recordArrayField(input, "host_action_runs");
  const approvalRequests = recordArrayField(input, "approval_requests");
  const importedArtifactRefs = normalizeArtifactRefs(input.artifact_refs);
  const artifactRefs = importedArtifactRefs.length > 0
    ? importedArtifactRefs
    : collectRunArtifactRefs(events, hostActionRuns, approvalRequests, toolNameByInvocationId(events));
  return {
    schema_version: 1,
    run_id: runId,
    exported_at: stringField(input, "exported_at") ?? "",
    event_count: events.length,
    conversation_ids: stringArrayField(input, "conversation_ids"),
    execution_session_ids: stringArrayField(input, "execution_session_ids"),
    sdk_session_ids: stringArrayField(input, "sdk_session_ids"),
    parent_run_ids: stringArrayField(input, "parent_run_ids"),
    host_action_runs: hostActionRuns,
    approval_requests: approvalRequests,
    artifact_ids: uniqueStrings([
      ...stringArrayField(input, "artifact_ids"),
      ...artifactRefs.map((artifact) => artifact.artifact_id),
    ]),
    artifact_refs: artifactRefs,
    diagnostics: eventDiagnostics(events),
    events,
  };
}

function normalizeReplayEvent(
  runId: string,
  event: unknown,
  index: number,
): Record<string, unknown> {
  const cloned = cloneRecord(event);
  const payload = isRecord(cloned.payload) ? cloned.payload : {};
  const payloadWithRunId = stringField(payload, "run_id") ? payload : { ...payload, run_id: runId };
  return {
    ...cloned,
    run_id: stringField(cloned, "run_id") ?? runId,
    sequence: numberField(cloned, "sequence") ?? index + 1,
    payload: payloadWithRunId,
  };
}

function normalizedRunEvents(
  store: RuntimeStore,
  runId: string,
): Record<string, unknown>[] {
  return store.transcript_events
    .map((event, sourceIndex) => ({ event, sourceIndex }))
    .filter(({ event }) => eventRunId(event) === runId)
    .map(({ event, sourceIndex }, index) => ({
      ...normalizeReplayEvent(runId, event, index),
      source_index: sourceIndex,
    }));
}

function projectReplayEvent(
  runId: string,
  event: Record<string, unknown>,
  fallbackSequence: number,
): RuntimeRunProjectionRow {
  const payload = isRecord(event.payload) ? event.payload : {};
  const eventKind = stringField(payload, "kind") ?? "unknown";
  const sequence = numberField(event, "sequence") ?? fallbackSequence;
  const eventArtifactIds = artifactIdsFromRefs(
    collectArtifactRefsFromValue(payload, {
      sourceEventId: stringField(event, "event_id"),
      sourceEventSequence: sequence,
      sourceInvocationId: stringField(payload, "invocation_id"),
      sourceToolName: null,
      sourceHostActionId: stringField(payload, "host_action_id"),
    }),
  );
  const base = {
    row_id: `row_${runId}_${String(sequence).padStart(4, "0")}`,
    run_id: runId,
    sequence,
    event_id: stringField(event, "event_id"),
    event_kind: eventKind,
    status: null,
    stage_id: stringField(payload, "stage_id"),
    tool_name: null,
    projection_scope: "worked" as const,
    expandable: false,
    artifact_ids: eventArtifactIds,
  };

  switch (eventKind) {
    case "user_message":
      return {
        ...base,
        projection_kind: "user_message",
        label: "User",
        summary: summarizeProjectionText(stringField(payload, "content") ?? ""),
        projection_scope: "main_timeline",
      };
    case "assistant_message_delta":
      return {
        ...base,
        projection_kind: "assistant_delta",
        label: "Assistant delta",
        summary: summarizeProjectionText(stringField(payload, "delta") ?? ""),
        projection_scope: "main_timeline",
      };
    case "assistant_message":
      return {
        ...base,
        projection_kind: "assistant_message",
        label: "Assistant",
        summary: summarizeProjectionText(stringField(payload, "content") ?? ""),
        projection_scope: "main_timeline",
      };
    case "run_plan_created":
    case "run_plan_updated":
      return {
        ...base,
        projection_kind: "plan",
        label: eventKind === "run_plan_created" ? "Plan" : "Plan updated",
        status: eventKind === "run_plan_created" ? "created" : "updated",
        summary: projectionSummary(payload, "Runtime plan event"),
        expandable: true,
      };
    case "capability_focus_locked":
      return {
        ...base,
        projection_kind: "focus",
        label: "Capability focus",
        status: "locked",
        summary: projectionSummary(payload, "Capability focus updated"),
        expandable: true,
      };
    case "stage_started":
      return {
        ...base,
        projection_kind: "stage",
        label: "Stage started",
        status: "running",
        summary: projectionSummary(payload, stringField(payload, "title") ?? "Stage started"),
        expandable: true,
      };
    case "stage_concluded":
      return {
        ...base,
        projection_kind: "stage",
        label: "Stage concluded",
        status: stringField(payload, "status"),
        summary: projectionSummary(payload, "Stage concluded"),
        expandable: true,
      };
    case "tool_invocation": {
      const invocation = isRecord(payload.invocation) ? payload.invocation : {};
      return {
        ...base,
        projection_kind: "tool",
        label: "Tool invocation",
        status: stringField(invocation, "status") ?? "running",
        summary: summarizeProjectionText(
          stringField(invocation, "input_summary") ??
            stringField(invocation, "tool_name") ??
            "Tool invocation",
        ),
        tool_name: stringField(invocation, "tool_name"),
        expandable: true,
      };
    }
    case "tool_result":
      return {
        ...base,
        projection_kind: "tool_result",
        label: "Tool result",
        status: stringField(payload, "status"),
        summary: projectionSummary(payload, "Tool result"),
        projection_scope: "worked",
        expandable: true,
      };
    case "session_state_changed":
      if (typeof payload.stage_capsule === "string" && payload.stage_capsule.trim()) {
        return {
          ...base,
          projection_kind: "stage_capsule",
          label: "Stage capsule",
          status: "written",
          summary: projectionSummary(payload, "Stage capsule written"),
          projection_scope: "inspector",
          expandable: true,
        };
      }
      return {
        ...base,
        projection_kind: "runtime_state",
        label: "Runtime state",
        summary: projectionSummary(payload, "Runtime state changed"),
        projection_scope: "inspector",
      };
    default:
      return {
        ...base,
        projection_kind: "diagnostic",
        label: "Unknown runtime event",
        summary: `Unknown runtime event kind: ${eventKind}`,
        projection_scope: "inspector",
        expandable: true,
      };
  }
}

function eventRunId(event: unknown): string | null {
  const topLevelRunId = stringField(event, "run_id");
  if (topLevelRunId) {
    return topLevelRunId;
  }
  const payload = isRecord(event) ? event.payload : null;
  return stringField(payload, "run_id");
}

function approvalRunId(request: unknown): string | null {
  const topLevelRunId = stringField(request, "run_id");
  if (topLevelRunId) {
    return topLevelRunId;
  }
  const machineContext = isRecord(request) ? request.machine_context : null;
  return stringField(machineContext, "run_id");
}

function pendingToolInvocationIds(events: Record<string, unknown>[]): string[] {
  const invoked = new Set<string>();
  const completed = new Set<string>();
  for (const event of events) {
    const payload: Record<string, unknown> = isRecord(event.payload) ? event.payload : {};
    if (payload.kind === "tool_invocation" && isRecord(payload.invocation)) {
      const invocationId = stringField(payload.invocation, "invocation_id");
      if (invocationId) {
        invoked.add(invocationId);
      }
    }
    if (payload.kind === "tool_result") {
      const invocationId = stringField(payload, "invocation_id");
      if (invocationId) {
        completed.add(invocationId);
      }
    }
  }
  return [...invoked].filter((invocationId) => !completed.has(invocationId));
}

function latestToolUseId(events: Record<string, unknown>[]): string | null {
  for (let index = events.length - 1; index >= 0; index -= 1) {
    const event = events[index];
    const rawPayload = event?.payload;
    const payload: Record<string, unknown> = isRecord(rawPayload) ? rawPayload : {};
    if (payload.kind === "tool_invocation" && isRecord(payload.invocation)) {
      const invocationId = stringField(payload.invocation, "invocation_id");
      if (invocationId) {
        return invocationId;
      }
    }
    if (payload.kind === "tool_result") {
      const invocationId = stringField(payload, "invocation_id");
      if (invocationId) {
        return invocationId;
      }
    }
  }
  return null;
}

function pendingHostActionPayload(
  store: RuntimeStore,
  hostActionId: string,
): Record<string, unknown> | null {
  const found = (store.host_action_intents ?? []).find(
    (intent) => intent.host_action_id === hostActionId,
  );
  return found ? cloneRecord(found) : null;
}

function isOpenApproval(request: unknown): boolean {
  const status = stringField(request, "status");
  return status === "open" || status === "waiting_review" || status === "pending";
}

function lastRunStopReasonForRun(store: RuntimeStore, runId: string): string | null {
  if (stringField(store.last_run_state, "stop_reason") !== "sdk_host_action_session_lost") {
    return null;
  }
  const conversationId = stringField(store.last_run_state, "conversation_id");
  if (!conversationId) {
    return "sdk_host_action_session_lost";
  }
  const runConversationIds = exportConversationIdsForRun(store, runId);
  return runConversationIds.includes(conversationId) ? "sdk_host_action_session_lost" : null;
}

function exportConversationIdsForRun(store: RuntimeStore, runId: string): string[] {
  const events = normalizedRunEvents(store, runId);
  const executionSessionIds = uniqueStrings(
    events.map((event) => stringField(event, "session_id")),
  );
  return uniqueStrings(
    store.execution_sessions
      .filter((session) => {
        const sessionId = stringField(session, "session_id");
        return sessionId ? executionSessionIds.includes(sessionId) : false;
      })
      .map((session) => stringField(session, "conversation_id")),
  );
}

function waitClassification(
  runId: string,
  waitKind: RuntimeRunWaitKind,
  status: RuntimeRunWaitClassification["status"],
  detail: string,
  evidence: RuntimeRunWaitClassification["evidence"],
): RuntimeRunWaitClassification {
  return {
    run_id: runId,
    wait_kind: waitKind,
    status,
    detail,
    evidence,
  };
}

function eventDiagnostics(events: Record<string, unknown>[]): {
  duplicate_event_ids: string[];
  missing_parent_event_ids: string[];
  missing_sequence_numbers: number[];
  out_of_order_event_ids: string[];
} {
  const seen = new Set<string>();
  const duplicateEventIds = new Set<string>();
  const eventIds = new Set<string>();
  const sequences = new Set<number>();
  const outOfOrderEventIds = new Set<string>();
  let previousSequence = 0;
  for (const event of events) {
    const eventId = stringField(event, "event_id");
    if (!eventId) {
      continue;
    }
    if (seen.has(eventId)) {
      duplicateEventIds.add(eventId);
    }
    seen.add(eventId);
    eventIds.add(eventId);
    const sequence = numberField(event, "sequence");
    if (sequence) {
      sequences.add(sequence);
      if (sequence < previousSequence) {
        outOfOrderEventIds.add(eventId);
      }
      previousSequence = sequence;
    }
  }

  const missingParentEventIds = new Set<string>();
  for (const event of events) {
    const parentEventId = stringField(event, "parent_event_id");
    if (parentEventId && !eventIds.has(parentEventId)) {
      missingParentEventIds.add(parentEventId);
    }
  }

  const missingSequenceNumbers: number[] = [];
  const largestSequence = sequences.size > 0 ? Math.max(...sequences) : 0;
  for (let sequence = 1; sequence <= largestSequence; sequence += 1) {
    if (!sequences.has(sequence)) {
      missingSequenceNumbers.push(sequence);
    }
  }

  return {
    duplicate_event_ids: [...duplicateEventIds],
    missing_parent_event_ids: [...missingParentEventIds],
    missing_sequence_numbers: missingSequenceNumbers,
    out_of_order_event_ids: [...outOfOrderEventIds],
  };
}

function projectionSummary(payload: Record<string, unknown>, fallback: string): string {
  return summarizeProjectionText(
    stringField(payload, "summary") ??
      stringField(payload, "objective") ??
      stringField(payload, "title") ??
      fallback,
  );
}

function summarizeProjectionText(value: string): string {
  const normalized = value.trim().replace(/\s+/g, " ");
  if (normalized.length <= 240) {
    return normalized;
  }
  return `${normalized.slice(0, 237)}...`;
}

type ArtifactRefProvenance = {
  sourceEventId: string | null;
  sourceEventSequence: number | null;
  sourceInvocationId: string | null;
  sourceToolName: string | null;
  sourceHostActionId: string | null;
};

function collectRunArtifactRefs(
  events: Record<string, unknown>[],
  hostActionRuns: Record<string, unknown>[],
  approvalRequests: Record<string, unknown>[],
  invocationToolNames: Map<string, string>,
): RuntimeRunArtifactRef[] {
  const refs: RuntimeRunArtifactRef[] = [];
  for (const event of events) {
    const payload = isRecord(event.payload) ? event.payload : event;
    const invocationId = stringField(payload, "invocation_id");
    refs.push(
      ...collectArtifactRefsFromValue(
        payload,
        {
          sourceEventId: stringField(event, "event_id"),
          sourceEventSequence: numberField(event, "sequence"),
          sourceInvocationId: invocationId,
          sourceToolName: invocationId ? invocationToolNames.get(invocationId) ?? null : null,
          sourceHostActionId: stringField(payload, "host_action_id"),
        },
        invocationToolNames,
      ),
    );
  }
  for (const hostActionRun of hostActionRuns) {
    refs.push(
      ...collectArtifactRefsFromValue(
        hostActionRun,
        {
          sourceEventId: null,
          sourceEventSequence: null,
          sourceInvocationId: null,
          sourceToolName: stringField(hostActionRun, "tool_id"),
          sourceHostActionId: stringField(hostActionRun, "host_action_id"),
        },
        invocationToolNames,
      ),
    );
  }
  for (const approvalRequest of approvalRequests) {
    refs.push(
      ...collectArtifactRefsFromValue(
        approvalRequest,
        {
          sourceEventId: null,
          sourceEventSequence: null,
          sourceInvocationId: null,
          sourceToolName: null,
          sourceHostActionId: null,
        },
        invocationToolNames,
      ),
    );
  }
  return dedupeArtifactRefs(refs);
}

function collectArtifactRefsFromValue(
  value: unknown,
  provenance: ArtifactRefProvenance,
  invocationToolNames = new Map<string, string>(),
): RuntimeRunArtifactRef[] {
  const refs: RuntimeRunArtifactRef[] = [];
  const visit = (candidate: unknown, candidateProvenance: ArtifactRefProvenance): void => {
    if (Array.isArray(candidate)) {
      for (const item of candidate) {
        visit(item, candidateProvenance);
      }
      return;
    }
    if (!isRecord(candidate)) {
      return;
    }
    const nestedInvocationId =
      stringField(candidate, "invocation_id") ??
      stringField(candidate, "invocationId") ??
      candidateProvenance.sourceInvocationId;
    const nestedHostActionId =
      stringField(candidate, "host_action_id") ??
      stringField(candidate, "hostActionId") ??
      candidateProvenance.sourceHostActionId;
    const nestedToolName =
      stringField(candidate, "tool_name") ??
      stringField(candidate, "toolName") ??
      stringField(candidate, "tool_id") ??
      (nestedInvocationId ? invocationToolNames.get(nestedInvocationId) ?? null : null) ??
      candidateProvenance.sourceToolName;
    const nextProvenance: ArtifactRefProvenance = {
      ...candidateProvenance,
      sourceInvocationId: nestedInvocationId,
      sourceToolName: nestedToolName,
      sourceHostActionId: nestedHostActionId,
    };
    const artifactId =
      stringField(candidate, "artifact_id") ??
      stringField(candidate, "artifactId");
    if (artifactId) {
      refs.push({
        artifact_id: artifactId,
        kind: stringField(candidate, "kind") ?? stringField(candidate, "type"),
        title: stringField(candidate, "title"),
        path:
          stringField(candidate, "path") ??
          stringField(candidate, "payloadRef") ??
          stringField(candidate, "uri"),
        summary:
          stringField(candidate, "summary") ??
          stringField(candidate, "inlinePreviewSummary"),
        sha256: stringField(candidate, "sha256"),
        byte_count:
          numberField(candidate, "byte_count") ??
          numberField(candidate, "byteCount"),
        token_estimate:
          numberField(candidate, "token_estimate") ??
          numberField(candidate, "tokenEstimate"),
        mime_type:
          stringField(candidate, "mime_type") ??
          stringField(candidate, "mimeType"),
        source_event_id: nextProvenance.sourceEventId,
        source_event_sequence: nextProvenance.sourceEventSequence,
        source_invocation_id: nextProvenance.sourceInvocationId,
        source_tool_name: nextProvenance.sourceToolName,
        source_host_action_id: nextProvenance.sourceHostActionId,
      });
    }
    for (const nested of Object.values(candidate)) {
      visit(nested, nextProvenance);
    }
  };
  visit(value, provenance);
  return dedupeArtifactRefs(refs);
}

function normalizeArtifactRefs(value: unknown): RuntimeRunArtifactRef[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return dedupeArtifactRefs(
    value
      .map((item) => {
        const artifactId = stringField(item, "artifact_id") ?? stringField(item, "artifactId");
        if (!artifactId) {
          return null;
        }
        return {
          artifact_id: artifactId,
          kind: stringField(item, "kind") ?? stringField(item, "type"),
          title: stringField(item, "title"),
          path:
            stringField(item, "path") ??
            stringField(item, "payloadRef") ??
            stringField(item, "uri"),
          summary:
            stringField(item, "summary") ??
            stringField(item, "inlinePreviewSummary"),
          sha256: stringField(item, "sha256"),
          byte_count:
            numberField(item, "byte_count") ??
            numberField(item, "byteCount"),
          token_estimate:
            numberField(item, "token_estimate") ??
            numberField(item, "tokenEstimate"),
          mime_type:
            stringField(item, "mime_type") ??
            stringField(item, "mimeType"),
          source_event_id: stringField(item, "source_event_id") ?? stringField(item, "sourceEventId"),
          source_event_sequence:
            numberField(item, "source_event_sequence") ??
            numberField(item, "sourceEventSequence"),
          source_invocation_id:
            stringField(item, "source_invocation_id") ??
            stringField(item, "sourceInvocationId"),
          source_tool_name:
            stringField(item, "source_tool_name") ??
            stringField(item, "sourceToolName"),
          source_host_action_id:
            stringField(item, "source_host_action_id") ??
            stringField(item, "sourceHostActionId"),
        };
      })
      .filter((item): item is RuntimeRunArtifactRef => Boolean(item)),
  );
}

function dedupeArtifactRefs(refs: RuntimeRunArtifactRef[]): RuntimeRunArtifactRef[] {
  const seen = new Set<string>();
  const deduped: RuntimeRunArtifactRef[] = [];
  for (const ref of refs) {
    const key = [
      ref.artifact_id,
      ref.path ?? "",
      ref.source_event_id ?? "",
      ref.source_invocation_id ?? "",
      ref.source_host_action_id ?? "",
    ].join("\u0000");
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    deduped.push(ref);
  }
  return deduped.sort((left, right) =>
    [
      (left.source_event_sequence ?? Number.MAX_SAFE_INTEGER) -
        (right.source_event_sequence ?? Number.MAX_SAFE_INTEGER),
      left.artifact_id.localeCompare(right.artifact_id),
      (left.path ?? "").localeCompare(right.path ?? ""),
    ].find((value) => value !== 0) ?? 0,
  );
}

function artifactIdsFromRefs(refs: RuntimeRunArtifactRef[]): string[] {
  return uniqueStrings(refs.map((ref) => ref.artifact_id));
}

function toolNameByInvocationId(events: Record<string, unknown>[]): Map<string, string> {
  const toolNames = new Map<string, string>();
  for (const event of events) {
    const payload = isRecord(event.payload) ? event.payload : {};
    if (payload.kind !== "tool_invocation" || !isRecord(payload.invocation)) {
      continue;
    }
    const invocationId = stringField(payload.invocation, "invocation_id");
    const toolName = stringField(payload.invocation, "tool_name");
    if (invocationId && toolName) {
      toolNames.set(invocationId, toolName);
    }
  }
  return toolNames;
}

function collectNamedStrings(values: unknown[], keys: string[]): string[] {
  const found = new Set<string>();
  const visit = (value: unknown): void => {
    if (Array.isArray(value)) {
      for (const item of value) {
        visit(item);
      }
      return;
    }
    if (!isRecord(value)) {
      return;
    }
    for (const key of keys) {
      const matched = stringField(value, key);
      if (matched) {
        found.add(matched);
      }
    }
    for (const nested of Object.values(value)) {
      visit(nested);
    }
  };
  for (const value of values) {
    visit(value);
  }
  return [...found].sort();
}

function uniqueStrings(values: Array<string | null>): string[] {
  return [...new Set(values.filter((value): value is string => Boolean(value)))].sort();
}

function stringArrayField(record: Record<string, unknown>, key: string): string[] {
  const value = record[key];
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string" && item.trim().length > 0)
    : [];
}

function recordArrayField(record: Record<string, unknown>, key: string): Record<string, unknown>[] {
  const value = record[key];
  return Array.isArray(value) ? value.map(cloneRecord) : [];
}

function cloneRecord(value: unknown): Record<string, unknown> {
  if (!isRecord(value)) {
    return {};
  }
  return JSON.parse(JSON.stringify(value)) as Record<string, unknown>;
}

function stringField(record: unknown, key: string): string | null {
  if (!isRecord(record)) {
    return null;
  }
  const value = record[key];
  return typeof value === "string" && value.trim().length > 0 ? value : null;
}

function numberField(record: unknown, key: string): number | null {
  if (!isRecord(record)) {
    return null;
  }
  const value = record[key];
  return typeof value === "number" && Number.isInteger(value) && value > 0 ? value : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
