import { argError, getRecordArg, getStringArg } from "./args.js";
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
  if (gearID) {
    payload.gear_id = gearID;
  }
  if (capabilityID) {
    payload.capability_id = capabilityID;
  }

  return {
    kind: "completed",
    tool_id: request.tool_id,
    payload,
  };
}

export function geeGearInvoke(request: ToolRequest): ToolOutcome {
  const gearID = getStringArg(request, "gear_id");
  if (!gearID) {
    return argError(request.tool_id, "gear_id", "required string `gear_id` is missing");
  }

  const capabilityID = getStringArg(request, "capability_id");
  if (!capabilityID) {
    return argError(
      request.tool_id,
      "capability_id",
      "required string `capability_id` is missing",
    );
  }

  return {
    kind: "completed",
    tool_id: request.tool_id,
    payload: {
      intent: "gear.invoke",
      gear_id: gearID,
      capability_id: capabilityID,
      args: getRecordArg(request, "args") ?? {},
    },
  };
}
