import type { RuntimeHostActionCompletion } from "../../protocol.js";
import {
  currentRuntimePlanStage,
  nextRuntimeRunPlan,
  type RuntimeRunPlan,
  type RuntimePlanStage,
} from "./planning.js";
import { isRecord, summarizePrompt } from "./state.js";

export type RuntimeStageConclusionStatus =
  | "completed"
  | "partial"
  | "blocked"
  | "plan_changed"
  | "needs_user_input";

export type RuntimeStageAdvanceDecision = {
  concluded: boolean;
  status?: RuntimeStageConclusionStatus;
  summary?: string;
  nextPlan?: RuntimeRunPlan | null;
};

type GearExecutionProof = {
  gearID: string;
  capabilityID: string;
};

const GEAR_INVOKE_TOOL_IDS = new Set([
  "gee.gear.invoke",
  "gear_invoke",
  "mcp__gee__gear_invoke",
]);

const GEAR_DISCOVERY_TOOL_IDS = new Set([
  "gee.gear.listCapabilities",
  "gear_list_capabilities",
  "mcp__gee__gear_list_capabilities",
]);

export function advanceRunPlanAfterHostCompletions(
  plan: RuntimeRunPlan,
  completions: RuntimeHostActionCompletion[],
): RuntimeStageAdvanceDecision {
  const stage = currentRuntimePlanStage(plan);
  if (!stage || completions.length === 0) {
    return { concluded: false };
  }

  const blockingCompletion = completions.find((completion) => completion.status === "failed");
  if (blockingCompletion) {
    return {
      concluded: true,
      status: "blocked",
      summary: stageBlockedSummary(stage, blockingCompletion),
      nextPlan: null,
    };
  }

  if (stage.required_capabilities.length === 0) {
    return { concluded: false };
  }

  const matched = completions.find((completion) =>
    completionMatchesStageRequiredCapability(completion, stage),
  );
  if (!matched) {
    return { concluded: false };
  }

  const nextPlan = nextRuntimeRunPlan(plan);
  return {
    concluded: true,
    status: "completed",
    summary: stageCompletedSummary(stage, matched, nextPlan),
    nextPlan,
  };
}

export function terminalRunPlanBlocker(
  plan: RuntimeRunPlan,
): string | null {
  const stage = currentRuntimePlanStage(plan);
  if (!stage) {
    return `Run plan ${plan.plan_id} points at missing stage ${plan.current_stage_id}.`;
  }
  if (stage.required_capabilities.length === 0) {
    return null;
  }
  return (
    `Run plan stage \`${stage.stage_id}\` has not produced a structured result for ` +
    `required capability ${stage.required_capabilities.join(", ")}.`
  );
}

export function shouldCompleteVerificationStage(plan: RuntimeRunPlan): boolean {
  const stage = currentRuntimePlanStage(plan);
  return Boolean(stage && stage.required_capabilities.length === 0);
}

function completionMatchesStageRequiredCapability(
  completion: RuntimeHostActionCompletion,
  stage: RuntimePlanStage,
): boolean {
  const ref = capabilityRefFromCompletion(completion);
  return Boolean(ref && stage.required_capabilities.includes(ref));
}

function capabilityRefFromCompletion(
  completion: RuntimeHostActionCompletion,
): string | null {
  const proof = gearExecutionProofFromCompletion(completion);
  return proof ? `${proof.gearID}/${proof.capabilityID}` : null;
}

function gearExecutionProofFromCompletion(
  completion: RuntimeHostActionCompletion,
): GearExecutionProof | null {
  if (completion.status !== "succeeded" || !isGearInvokeToolID(completion.tool_id)) {
    return null;
  }

  const parsed = parseResultJSONRecord(completion.result_json);
  if (!parsed) {
    return null;
  }

  const payload = isRecord(parsed.payload) ? parsed.payload : parsed;
  if (isGearCapabilityDisclosure(parsed, payload)) {
    return null;
  }

  const resultToolID = firstString(parsed.tool_id, parsed.tool);
  if (resultToolID && !isGearInvokeToolID(resultToolID)) {
    return null;
  }

  const intent = firstString(parsed.intent, payload.intent);
  if (intent && intent !== "gear.invoke") {
    return null;
  }

  const kind = stringValue(parsed.kind);
  const hasExecutionEnvelope =
    isRecord(parsed.payload) ||
    Boolean(resultToolID) ||
    intent === "gear.invoke" ||
    isGearExecutionKind(kind);
  if (kind && hasExecutionEnvelope && !isGearExecutionKind(kind)) {
    return null;
  }

  const executionStatus = stringValue(parsed.status);
  if (executionStatus && hasExecutionEnvelope && !isSucceededExecutionStatus(executionStatus)) {
    return null;
  }

  const gearID = stringValue(payload.gear_id);
  const capabilityID = stringValue(payload.capability_id);
  if (gearID && capabilityID) {
    if (!capabilityOutputProofSatisfied(`${gearID}/${capabilityID}`, payload)) {
      return null;
    }
    return { gearID, capabilityID };
  }
  return null;
}

function capabilityOutputProofSatisfied(
  capabilityRef: string,
  payload: Record<string, unknown>,
): boolean {
  if (capabilityRef !== "media.library/media.import_files") {
    return true;
  }
  return (
    positiveNumber(payload.available_count) ||
    positiveNumber(payload.imported_count) ||
    positiveNumber(payload.existing_count) ||
    nonEmptyArray(payload.available_items) ||
    nonEmptyArray(payload.imported_items) ||
    nonEmptyArray(payload.existing_items)
  );
}

function isGearCapabilityDisclosure(
  parsed: Record<string, unknown>,
  payload: Record<string, unknown>,
): boolean {
  if (firstString(parsed.disclosure_level, payload.disclosure_level)) {
    return true;
  }
  const intent = firstString(parsed.intent, payload.intent);
  if (intent === "gear.list_capabilities") {
    return true;
  }
  const toolID = firstString(parsed.tool_id, parsed.tool);
  return Boolean(toolID && isGearDiscoveryToolID(toolID));
}

function isGearInvokeToolID(toolID: string): boolean {
  return GEAR_INVOKE_TOOL_IDS.has(toolID);
}

function isGearDiscoveryToolID(toolID: string): boolean {
  return GEAR_DISCOVERY_TOOL_IDS.has(toolID);
}

function isGearExecutionKind(kind: string): boolean {
  return [
    "completed",
    "execution",
    "gear.execution",
    "gear.invoke",
    "gear_execution",
    "gear_invoke",
    "host_action_execution",
    "succeeded",
    "tool_execution",
  ].includes(kind.toLowerCase());
}

function isSucceededExecutionStatus(status: string): boolean {
  const normalized = status.toLowerCase();
  return normalized === "succeeded" || normalized === "completed";
}

function parseResultJSONRecord(raw: string | undefined): Record<string, unknown> | null {
  if (!raw) {
    return null;
  }
  try {
    const parsed = JSON.parse(raw) as unknown;
    return isRecord(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

function firstString(...values: unknown[]): string {
  for (const value of values) {
    const string = stringValue(value);
    if (string) {
      return string;
    }
  }
  return "";
}

function stringValue(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function positiveNumber(value: unknown): boolean {
  return typeof value === "number" && Number.isFinite(value) && value > 0;
}

function nonEmptyArray(value: unknown): boolean {
  return Array.isArray(value) && value.length > 0;
}

function stageCompletedSummary(
  stage: RuntimePlanStage,
  completion: RuntimeHostActionCompletion,
  nextPlan: RuntimeRunPlan | null,
): string {
  const result = summarizePrompt(
    capabilityRefFromCompletion(completion) ?? completion.summary ?? completion.tool_id,
    180,
  );
  const next = nextPlan
    ? ` Advancing to ${nextPlan.current_stage_id}.`
    : " No later stage remains.";
  return `Stage completed: ${stage.title}. ${result}.${next}`;
}

function stageBlockedSummary(
  stage: RuntimePlanStage,
  completion: RuntimeHostActionCompletion,
): string {
  const reason = completion.error ?? completion.summary ?? `${completion.tool_id} failed`;
  return `Stage blocked: ${stage.title}. ${summarizePrompt(reason, 220)}`;
}
