import { argError, getStringArg } from "./args.js";
import type { ToolOutcome, ToolRequest } from "./types.js";

const KNOWN_SECTIONS = [
  "home",
  "chat",
  "tasks",
  "automations",
  "apps",
  "agents",
  "settings",
] as const;

export function navigateOpenSection(request: ToolRequest): ToolOutcome {
  const section = getStringArg(request, "section");
  if (section === undefined) {
    return argError(request.tool_id, "section", "required string `section` is missing");
  }
  if (!KNOWN_SECTIONS.some((known) => known === section)) {
    return {
      kind: "error",
      tool_id: request.tool_id,
      code: "navigate.unknown_section",
      message: `unknown section \`${section}\` (expected one of ${JSON.stringify(KNOWN_SECTIONS)})`,
    };
  }
  return {
    kind: "completed",
    tool_id: request.tool_id,
    payload: {
      intent: "navigate.section",
      section,
    },
  };
}

export function navigateOpenModule(request: ToolRequest): ToolOutcome {
  const moduleID = getStringArg(request, "module_id");
  if (moduleID === undefined) {
    return argError(request.tool_id, "module_id", "required string `module_id` is missing");
  }
  if (moduleID.length === 0) {
    return argError(request.tool_id, "module_id", "must not be empty");
  }
  return {
    kind: "completed",
    tool_id: request.tool_id,
    payload: {
      intent: "navigate.module",
      module_id: moduleID,
    },
  };
}

export function geeAppOpenSurface(request: ToolRequest): ToolOutcome {
  const surfaceID =
    getStringArg(request, "surface_id") ??
    getStringArg(request, "gear_id") ??
    getStringArg(request, "module_id");
  if (surfaceID === undefined) {
    return argError(
      request.tool_id,
      "surface_id",
      "required string `surface_id` or `gear_id` is missing",
    );
  }
  if (surfaceID.length === 0) {
    return argError(request.tool_id, "surface_id", "must not be empty");
  }
  return {
    kind: "completed",
    tool_id: request.tool_id,
    payload: {
      intent: "navigate.module",
      module_id: surfaceID,
    },
  };
}
