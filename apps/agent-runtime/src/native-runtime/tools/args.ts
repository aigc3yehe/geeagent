import type { ToolOutcome, ToolRequest } from "./types.js";

export function hasValidApprovalToken(token: string | undefined): boolean {
  return token !== undefined && token.trim().length > 0;
}

export function argError(toolID: string, field: string, detail: string): ToolOutcome {
  return {
    kind: "error",
    tool_id: toolID,
    code: `args.${field}`,
    message: detail,
  };
}

export function getStringArg(request: ToolRequest, key: string): string | undefined {
  const value = request.arguments?.[key];
  return typeof value === "string" ? value : undefined;
}

export function getNumberArg(request: ToolRequest, key: string): number | undefined {
  const value = request.arguments?.[key];
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

export function getBoolArg(request: ToolRequest, key: string): boolean | undefined {
  const value = request.arguments?.[key];
  return typeof value === "boolean" ? value : undefined;
}

export function getRecordArg(
  request: ToolRequest,
  key: string,
): Record<string, unknown> | undefined {
  const value = request.arguments?.[key];
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : undefined;
}


export function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
