import {
  argError,
  getStringArg,
  getStringArrayArg,
  normalizeGearInvokeArgumentsEnvelope,
} from "./args.js";
import { validateGearCapabilityArgs } from "../capabilities/gear-validation.js";
import type { ToolOutcome, ToolRequest } from "./types.js";

const DISCLOSURE_LEVELS = new Set(["summary", "capabilities", "schema"]);

export function geeGearListCapabilities(request: ToolRequest): ToolOutcome {
  const detail = getStringArg(request, "detail") ?? "summary";
  if (!DISCLOSURE_LEVELS.has(detail)) {
    return argError(
      request.tool_id,
      "detail",
      "expected `detail` to be one of summary, capabilities, or schema",
    );
  }

  const payload: Record<string, unknown> = {
    intent: "gear.list_capabilities",
    detail,
  };
  const gearID = getStringArg(request, "gear_id");
  const capabilityID = getStringArg(request, "capability_id");
  const focusGearIDs = getStringArrayArg(request, "focus_gear_ids") ?? [];
  const focusCapabilityIDs = getStringArrayArg(request, "focus_capability_ids") ?? [];
  const runPlanID = getStringArg(request, "run_plan_id");
  const stageID = getStringArg(request, "stage_id");
  if (gearID) {
    payload.gear_id = gearID;
  }
  if (capabilityID) {
    payload.capability_id = capabilityID;
  }
  if (focusGearIDs.length > 0) {
    payload.focus_gear_ids = focusGearIDs;
  }
  if (focusCapabilityIDs.length > 0) {
    payload.focus_capability_ids = focusCapabilityIDs;
  }
  if (runPlanID) {
    payload.run_plan_id = runPlanID;
  }
  if (stageID) {
    payload.stage_id = stageID;
  }

  return {
    kind: "completed",
    tool_id: request.tool_id,
    payload,
  };
}

export function geeGearInvoke(request: ToolRequest): ToolOutcome {
  const envelope = normalizeGearInvokeArgumentsEnvelope(request.arguments);
  if (!envelope.ok) {
    return {
      kind: "error",
      tool_id: request.tool_id,
      code: envelope.code,
      message: envelope.message,
    };
  }

  const gearID = envelope.gear_id;
  const capabilityID = envelope.capability_id;
  const args = envelope.args;
  const validation = validateGearCapabilityArgs(gearID, capabilityID, args);
  if (!validation.ok) {
    return {
      kind: "error",
      tool_id: request.tool_id,
      code: validation.code,
      message: validation.message,
    };
  }

  return {
    kind: "completed",
    tool_id: request.tool_id,
    payload: {
      intent: "gear.invoke",
      gear_id: gearID,
      capability_id: capabilityID,
      args,
    },
  };
}
