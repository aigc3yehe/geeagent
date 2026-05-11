import { argError, getStringArg } from "./args.js";
import type { ToolOutcome, ToolRequest } from "./types.js";

export function geeNativeAppControl(request: ToolRequest): ToolOutcome {
  const appID = getStringArg(request, "app_id") ?? getStringArg(request, "app");
  if (!appID?.trim()) {
    return argError(request.tool_id, "app_id", "required string `app_id` is missing.");
  }

  const action = getStringArg(request, "action");
  if (!action?.trim()) {
    return argError(request.tool_id, "action", "required string `action` is missing.");
  }

  const payload: Record<string, unknown> = {
    intent: "native_app.control",
    app_id: appID.trim(),
    action: action.trim(),
  };
  const prompt = getStringArg(request, "prompt");
  const instruction = getStringArg(request, "instruction");
  if (prompt?.trim()) {
    payload.prompt = codexPromptBody(prompt);
  }
  if (instruction?.trim()) {
    payload.instruction = codexPromptBody(instruction);
  }

  return {
    kind: "completed",
    tool_id: request.tool_id,
    payload,
  };
}

export function codexPromptBody(value: string): string {
  const trimmed = value.trim();
  if (!looksLikeCodexDelegationWrapper(trimmed)) {
    return trimmed;
  }
  const taskIndex = trimmed.toLowerCase().indexOf("\ntask:");
  if (taskIndex < 0) {
    return trimmed;
  }
  const afterTaskLabel = trimmed.slice(taskIndex + "\ntask:".length);
  const firstNewline = afterTaskLabel.search(/\r?\n/);
  const body = (firstNewline >= 0 ? afterTaskLabel.slice(firstNewline + afterTaskLabel.match(/\r?\n/)![0].length) : afterTaskLabel).trim();
  return collapseExactTandemDuplicate(body);
}

function looksLikeCodexDelegationWrapper(value: string): boolean {
  return (
    value.includes("The user delegated the following task") ||
    value.includes("Use the browser/Chrome plugin") ||
    value.includes("Do not pretend completion")
  );
}

function collapseExactTandemDuplicate(value: string): string {
  if (value.length < 16 || value.length % 2 !== 0) {
    return value;
  }
  const midpoint = value.length / 2;
  const first = value.slice(0, midpoint).trim();
  const second = value.slice(midpoint).trim();
  return first && first === second ? first : value;
}
