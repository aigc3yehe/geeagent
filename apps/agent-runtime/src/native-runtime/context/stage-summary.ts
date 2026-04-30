export type StageSummaryStatus =
  | "not_started"
  | "running"
  | "succeeded"
  | "failed"
  | "blocked"
  | "approval_pending"
  | "cancelled";

export type StageSummaryToolRecord = {
  invocation_id?: string;
  tool_name: string;
  status: StageSummaryStatus;
  input_summary?: string | null;
  output?: unknown;
  output_summary?: string | null;
  error?: string | null;
  approval_request_id?: string | null;
  artifact_refs?: StageSummaryArtifactRef[];
};

export type StageSummaryArtifactRef = {
  artifact_id?: string;
  kind?: string;
  uri?: string;
  path?: string;
  title?: string;
  summary?: string;
  status?: StageSummaryStatus;
};

export type StageSummaryInput = {
  stage_id?: string;
  run_id?: string;
  session_id?: string;
  status?: StageSummaryStatus;
  objective?: string;
  latest_user_request: string;
  prior_summary?: string;
  completed_steps?: string[];
  decisions?: string[];
  next_steps?: string[];
  blockers?: string[];
  approvals_pending?: string[];
  tool_records?: StageSummaryToolRecord[];
  artifact_refs?: StageSummaryArtifactRef[];
  max_tool_summary_chars?: number;
};

export type StageSummaryCapsule = {
  capsule_version: 1;
  stage_id: string | null;
  run_id: string | null;
  session_id: string | null;
  status: StageSummaryStatus;
  objective: string | null;
  latest_user_request: string;
  prior_summary: string | null;
  completed_steps: string[];
  decisions: string[];
  next_steps: string[];
  blockers: string[];
  approvals_pending: string[];
  tool_records: Array<
    Omit<StageSummaryToolRecord, "output" | "output_summary" | "artifact_refs"> & {
      output_summary: string | null;
      artifact_refs: StageSummaryArtifactRef[];
    }
  >;
  artifact_refs: StageSummaryArtifactRef[];
  counts: {
    tools_total: number;
    tools_succeeded: number;
    tools_failed: number;
    tools_pending: number;
    artifacts_total: number;
  };
  limits: {
    tool_summary_chars: number;
  };
};

const DEFAULT_TOOL_SUMMARY_CHARS = 700;
const DEFAULT_LIST_ITEM_CHARS = 320;
const MIN_TOOL_SUMMARY_CHARS = 120;
const MAX_TOOL_SUMMARY_CHARS = 2_000;

const STATUS_RANK: Record<StageSummaryStatus, number> = {
  failed: 6,
  approval_pending: 5,
  blocked: 4,
  cancelled: 3,
  running: 2,
  not_started: 1,
  succeeded: 0,
};

export function buildStageSummaryCapsule(
  input: StageSummaryInput,
): StageSummaryCapsule {
  const limits = {
    tool_summary_chars: boundedInteger(
      input.max_tool_summary_chars,
      DEFAULT_TOOL_SUMMARY_CHARS,
      MIN_TOOL_SUMMARY_CHARS,
      MAX_TOOL_SUMMARY_CHARS,
    ),
  };
  const toolRecords = normalizeToolRecords(input.tool_records ?? [], limits.tool_summary_chars);
  const artifactRefs = normalizeArtifactRefs(input.artifact_refs ?? []);
  const approvalsPending = normalizeTextList(input.approvals_pending ?? [], DEFAULT_LIST_ITEM_CHARS);
  const blockers = normalizeTextList(input.blockers ?? [], DEFAULT_LIST_ITEM_CHARS);
  const status = resolveStageStatus(input.status ?? "running", {
    toolRecords,
    blockers,
    approvalsPending,
  });

  return {
    capsule_version: 1,
    stage_id: optionalText(input.stage_id),
    run_id: optionalText(input.run_id),
    session_id: optionalText(input.session_id),
    status,
    objective: optionalText(input.objective),
    latest_user_request: input.latest_user_request,
    prior_summary: optionalText(input.prior_summary),
    completed_steps: normalizeTextList(input.completed_steps ?? [], DEFAULT_LIST_ITEM_CHARS),
    decisions: normalizeTextList(input.decisions ?? [], DEFAULT_LIST_ITEM_CHARS),
    next_steps: normalizeTextList(input.next_steps ?? [], DEFAULT_LIST_ITEM_CHARS),
    blockers,
    approvals_pending: approvalsPending,
    tool_records: toolRecords,
    artifact_refs: artifactRefs,
    counts: {
      tools_total: toolRecords.length,
      tools_succeeded: toolRecords.filter((record) => record.status === "succeeded").length,
      tools_failed: toolRecords.filter((record) => record.status === "failed").length,
      tools_pending: toolRecords.filter((record) => isOpenStatus(record.status)).length,
      artifacts_total:
        artifactRefs.length +
        toolRecords.reduce((count, record) => count + record.artifact_refs.length, 0),
    },
    limits,
  };
}

export function renderStageSummaryCapsule(capsule: StageSummaryCapsule): string {
  const sections = [
    "[GEEAGENT STAGE SUMMARY CAPSULE]",
    "Purpose: deterministic model-facing continuation context for the current runtime stage. Treat this as state, not as a new user request.",
    renderMetadata(capsule),
    renderOptionalBlock("Objective", capsule.objective),
    renderVerbatimLatestRequest(capsule.latest_user_request),
    renderOptionalBlock("Prior summary", capsule.prior_summary),
    renderList("Completed steps", capsule.completed_steps),
    renderList("Decisions", capsule.decisions),
    renderToolRecords(capsule.tool_records),
    renderArtifactRefs("Artifacts", capsule.artifact_refs),
    renderList("Blockers", capsule.blockers),
    renderList("Approvals pending", capsule.approvals_pending),
    renderList("Next steps", capsule.next_steps),
    renderStatusInstruction(capsule.status),
    "[/GEEAGENT STAGE SUMMARY CAPSULE]",
  ].filter((section) => section.length > 0);

  return sections.join("\n\n");
}

function normalizeToolRecords(
  records: StageSummaryToolRecord[],
  maxSummaryChars: number,
): StageSummaryCapsule["tool_records"] {
  return records.map((record) => ({
    invocation_id: optionalText(record.invocation_id) ?? undefined,
    tool_name: normalizeRequiredText(record.tool_name, "unknown_tool"),
    status: normalizeStageStatus(record.status),
    input_summary: optionalBoundedText(record.input_summary, DEFAULT_LIST_ITEM_CHARS),
    output_summary: summarizeToolOutput(record, maxSummaryChars),
    error: optionalBoundedText(record.error, maxSummaryChars),
    approval_request_id: optionalText(record.approval_request_id),
    artifact_refs: normalizeArtifactRefs(record.artifact_refs ?? []),
  }));
}

function normalizeArtifactRefs(records: StageSummaryArtifactRef[]): StageSummaryArtifactRef[] {
  return records.map((record) => ({
    artifact_id: optionalText(record.artifact_id) ?? undefined,
    kind: optionalText(record.kind) ?? undefined,
    uri: optionalText(record.uri) ?? undefined,
    path: optionalText(record.path) ?? undefined,
    title: optionalText(record.title) ?? undefined,
    summary: optionalBoundedText(record.summary, DEFAULT_LIST_ITEM_CHARS) ?? undefined,
    status: record.status ? normalizeStageStatus(record.status) : undefined,
  }));
}

function resolveStageStatus(
  requested: StageSummaryStatus,
  signals: {
    toolRecords: StageSummaryCapsule["tool_records"];
    blockers: string[];
    approvalsPending: string[];
  },
): StageSummaryStatus {
  const requestedStatus = normalizeStageStatus(requested);
  const observed: StageSummaryStatus[] = [requestedStatus];
  if (requestedStatus !== "succeeded") {
    observed.push(...signals.toolRecords.map((record) => record.status));
  }
  if (signals.approvalsPending.length > 0) {
    observed.push("approval_pending");
  }
  if (signals.blockers.length > 0) {
    observed.push("blocked");
  }
  return observed.reduce((highest, status) =>
    STATUS_RANK[status] > STATUS_RANK[highest] ? status : highest,
  );
}

function normalizeStageStatus(status: StageSummaryStatus): StageSummaryStatus {
  switch (status) {
    case "not_started":
    case "running":
    case "succeeded":
    case "failed":
    case "blocked":
    case "approval_pending":
    case "cancelled":
      return status;
    default:
      return "running";
  }
}

function summarizeToolOutput(
  record: StageSummaryToolRecord,
  maxSummaryChars: number,
): string | null {
  const explicitSummary = optionalBoundedText(record.output_summary, maxSummaryChars);
  if (explicitSummary !== null) {
    return explicitSummary;
  }
  if (record.output === undefined || record.output === null) {
    return null;
  }
  if (typeof record.output === "string") {
    return truncateText(collapseWhitespace(record.output), maxSummaryChars);
  }
  return truncateText(stableSerialize(record.output), maxSummaryChars);
}

function stableSerialize(value: unknown): string {
  if (value === undefined) {
    return "undefined";
  }
  if (value === null || typeof value !== "object") {
    return JSON.stringify(value) ?? String(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map((item) => stableSerialize(item)).join(",")}]`;
  }
  const record = value as Record<string, unknown>;
  const entries = Object.keys(record)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${stableSerialize(record[key])}`);
  return `{${entries.join(",")}}`;
}

function renderMetadata(capsule: StageSummaryCapsule): string {
  return [
    `Status: ${capsule.status}`,
    capsule.stage_id ? `Stage id: ${capsule.stage_id}` : "",
    capsule.run_id ? `Run id: ${capsule.run_id}` : "",
    capsule.session_id ? `Session id: ${capsule.session_id}` : "",
    `Tool counts: ${capsule.counts.tools_succeeded} succeeded, ${capsule.counts.tools_failed} failed, ${capsule.counts.tools_pending} pending/open, ${capsule.counts.tools_total} total.`,
    `Artifact refs: ${capsule.counts.artifacts_total}.`,
  ]
    .filter(Boolean)
    .join("\n");
}

function renderVerbatimLatestRequest(request: string): string {
  return ["Latest user request, verbatim:", "```", request, "```"].join("\n");
}

function renderOptionalBlock(title: string, value: string | null): string {
  return value ? `${title}:\n${value}` : "";
}

function renderList(title: string, values: string[]): string {
  if (values.length === 0) {
    return "";
  }
  return `${title}:\n${values.map((value) => `- ${value}`).join("\n")}`;
}

function renderToolRecords(records: StageSummaryCapsule["tool_records"]): string {
  if (records.length === 0) {
    return "";
  }
  const rendered = records.map((record, index) => {
    const lines = [
      `${index + 1}. ${record.tool_name} [${record.status}]${record.invocation_id ? ` (${record.invocation_id})` : ""}`,
      record.input_summary ? `   input: ${record.input_summary}` : "",
      record.output_summary ? `   output summary: ${record.output_summary}` : "",
      record.error ? `   error: ${record.error}` : "",
      record.approval_request_id
        ? `   approval request: ${record.approval_request_id}`
        : "",
      record.artifact_refs.length > 0
        ? `   artifacts: ${record.artifact_refs.map(renderArtifactRefInline).join("; ")}`
        : "",
    ];
    return lines.filter(Boolean).join("\n");
  });
  return `Tool records:\n${rendered.join("\n")}`;
}

function renderArtifactRefs(title: string, records: StageSummaryArtifactRef[]): string {
  if (records.length === 0) {
    return "";
  }
  return `${title}:\n${records.map((record) => `- ${renderArtifactRefInline(record)}`).join("\n")}`;
}

function renderArtifactRefInline(record: StageSummaryArtifactRef): string {
  const label =
    record.title ?? record.path ?? record.uri ?? record.artifact_id ?? record.kind ?? "artifact";
  const fields = [
    record.kind ? `kind=${record.kind}` : "",
    record.status ? `status=${record.status}` : "",
    record.path ? `path=${record.path}` : "",
    record.uri ? `uri=${record.uri}` : "",
    record.summary ? `summary=${record.summary}` : "",
  ].filter(Boolean);
  return fields.length > 0 ? `${label} (${fields.join(", ")})` : label;
}

function renderStatusInstruction(status: StageSummaryStatus): string {
  switch (status) {
    case "succeeded":
      return "Continuation instruction: the stage is marked succeeded. Do not redo completed work unless the latest user request asks for it.";
    case "failed":
      return "Continuation instruction: the stage failed. Do not present it as completed; explain or recover from the failure.";
    case "blocked":
      return "Continuation instruction: the stage is blocked. Do not claim success until the blocker is resolved.";
    case "approval_pending":
      return "Continuation instruction: approval is pending. Do not execute or claim completion of approval-gated work until approval is granted.";
    case "cancelled":
      return "Continuation instruction: the stage was cancelled. Do not continue cancelled work unless the user explicitly restarts it.";
    case "not_started":
      return "Continuation instruction: the stage has not started. Begin from the latest user request if work should proceed.";
    case "running":
      return "Continuation instruction: the stage is in progress. Continue from the latest truthful state.";
  }
}

function isOpenStatus(status: StageSummaryStatus): boolean {
  return status === "not_started" || status === "running" || status === "approval_pending";
}

function normalizeTextList(values: string[], maxChars: number): string[] {
  return values
    .map((value) => optionalBoundedText(value, maxChars))
    .filter((value): value is string => value !== null);
}

function optionalText(value: string | null | undefined): string | null {
  if (value === undefined || value === null) {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function optionalBoundedText(
  value: string | null | undefined,
  maxChars: number,
): string | null {
  const text = optionalText(value);
  return text === null ? null : truncateText(collapseWhitespace(text), maxChars);
}

function normalizeRequiredText(value: string, fallback: string): string {
  const text = optionalText(value);
  return text ?? fallback;
}

function collapseWhitespace(value: string): string {
  return value.trim().replace(/\s+/g, " ");
}

function truncateText(value: string, maxChars: number): string {
  if (value.length <= maxChars) {
    return value;
  }
  return `${value.slice(0, Math.max(0, maxChars - 3))}...`;
}

function boundedInteger(
  value: number | undefined,
  fallback: number,
  min: number,
  max: number,
): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return fallback;
  }
  return Math.min(max, Math.max(min, Math.floor(value)));
}
