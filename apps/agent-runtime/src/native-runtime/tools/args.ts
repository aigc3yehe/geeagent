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

export function getStringArrayArg(
  request: ToolRequest,
  key: string,
): string[] | undefined {
  const value = request.arguments?.[key];
  return Array.isArray(value) && value.every((item) => typeof item === "string")
    ? value
    : undefined;
}

export function getRecordArg(
  request: ToolRequest,
  key: string,
): Record<string, unknown> | undefined {
  const value = request.arguments?.[key];
  return isRecord(value)
    ? (value as Record<string, unknown>)
    : undefined;
}

export type GearInvokeEnvelopeNormalization =
  | {
      ok: true;
      gear_id: string;
      capability_id: string;
      args: Record<string, unknown>;
      arguments: Record<string, unknown>;
    }
  | {
      ok: false;
      code: string;
      message: string;
    };

const GEAR_INVOKE_ENVELOPE_KEYS = new Set([
  "gear_id",
  "capability_id",
  "args",
  "input",
  "payload",
  "arguments",
]);

export function normalizeGearInvokeArgumentsEnvelope(
  raw: Record<string, unknown> | undefined,
): GearInvokeEnvelopeNormalization {
  const outer = raw ?? {};
  const nestedEnvelope = envelopeRecord(outer, "arguments");
  if (nestedEnvelope && !nestedEnvelope.ok) {
    return nestedEnvelope;
  }
  const nested = nestedEnvelope?.value;

  const gearID = mergedRequiredString("gear_id", outer, nested);
  if (!gearID.ok) {
    return gearID;
  }
  const capabilityID = mergedRequiredString("capability_id", outer, nested);
  if (!capabilityID.ok) {
    return capabilityID;
  }

  const explicitArgs = mergeExplicitGearArgs(outer, nested);
  if (!explicitArgs.ok) {
    return explicitArgs;
  }

  const invokeArgs = { ...explicitArgs.args };
  const implicitMerge = mergeImplicitGearArgs(invokeArgs, outer, nested);
  if (!implicitMerge.ok) {
    return implicitMerge;
  }

  return {
    ok: true,
    gear_id: gearID.value,
    capability_id: capabilityID.value,
    args: invokeArgs,
    arguments: {
      gear_id: gearID.value,
      capability_id: capabilityID.value,
      args: invokeArgs,
    },
  };
}

function envelopeRecord(
  record: Record<string, unknown>,
  key: string,
):
  | { ok: true; value?: Record<string, unknown> }
  | { ok: false; code: string; message: string } {
  const value = record[key];
  if (value === undefined) {
    return { ok: true };
  }
  if (!isRecord(value)) {
    return {
      ok: false,
      code: "gear.args.arguments",
      message: "`arguments` must be an object for gee.gear.invoke.",
    };
  }
  return { ok: true, value };
}

function mergedRequiredString(
  key: "gear_id" | "capability_id",
  outer: Record<string, unknown>,
  nested: Record<string, unknown> | undefined,
):
  | { ok: true; value: string }
  | { ok: false; code: string; message: string } {
  const outerValue = optionalStringField(outer, key);
  if (!outerValue.ok) {
    return outerValue;
  }
  const nestedValue = nested ? optionalStringField(nested, key) : { ok: true as const };
  if (!nestedValue.ok) {
    return nestedValue;
  }

  const values = [outerValue.value, nestedValue.value].filter(
    (value): value is string => value !== undefined,
  );
  const uniqueValues = new Set(values);
  if (uniqueValues.size > 1) {
    return envelopeConflict(
      `conflicting \`${key}\` values were received for gee.gear.invoke.`,
    );
  }

  const value = values[0]?.trim();
  if (!value) {
    return {
      ok: false,
      code: `gear.args.${key}`,
      message: `required string \`${key}\` is missing for gee.gear.invoke.`,
    };
  }
  return { ok: true, value };
}

function optionalStringField(
  record: Record<string, unknown>,
  key: "gear_id" | "capability_id",
):
  | { ok: true; value?: string }
  | { ok: false; code: string; message: string } {
  const value = record[key];
  if (value === undefined) {
    return { ok: true };
  }
  if (typeof value !== "string" || value.trim().length === 0) {
    return {
      ok: false,
      code: `gear.args.${key}`,
      message: `required string \`${key}\` is missing for gee.gear.invoke.`,
    };
  }
  return { ok: true, value: value.trim() };
}

function mergeExplicitGearArgs(
  outer: Record<string, unknown>,
  nested: Record<string, unknown> | undefined,
):
  | { ok: true; args: Record<string, unknown> }
  | { ok: false; code: string; message: string } {
  const merged: Record<string, unknown> = {};
  for (const candidate of [
    recordCandidate(outer, "args"),
    nested ? recordCandidate(nested, "args") : undefined,
    recordCandidate(outer, "input"),
    nested ? recordCandidate(nested, "input") : undefined,
    recordCandidate(outer, "payload"),
    nested ? recordCandidate(nested, "payload") : undefined,
  ]) {
    if (!candidate) {
      continue;
    }
    if (!candidate.ok) {
      return candidate;
    }
    const result = mergeArgRecord(merged, candidate.value);
    if (!result.ok) {
      return result;
    }
  }
  return { ok: true, args: merged };
}

function recordCandidate(
  record: Record<string, unknown>,
  key: "args" | "input" | "payload",
):
  | { ok: true; value: Record<string, unknown> }
  | { ok: false; code: string; message: string }
  | undefined {
  const value = record[key];
  if (value === undefined) {
    return undefined;
  }
  if (!isRecord(value)) {
    return {
      ok: false,
      code: `gear.args.${key}`,
      message: `\`${key}\` must be an object for gee.gear.invoke.`,
    };
  }
  return { ok: true, value };
}

function mergeImplicitGearArgs(
  target: Record<string, unknown>,
  outer: Record<string, unknown>,
  nested: Record<string, unknown> | undefined,
): { ok: true } | { ok: false; code: string; message: string } {
  for (const record of [outer, nested]) {
    if (!record) {
      continue;
    }
    for (const [key, value] of Object.entries(record)) {
      if (GEAR_INVOKE_ENVELOPE_KEYS.has(key)) {
        continue;
      }
      const result = mergeArgValue(target, key, value);
      if (!result.ok) {
        return result;
      }
    }
  }
  return { ok: true };
}

function mergeArgRecord(
  target: Record<string, unknown>,
  source: Record<string, unknown>,
): { ok: true } | { ok: false; code: string; message: string } {
  for (const [key, value] of Object.entries(source)) {
    const result = mergeArgValue(target, key, value);
    if (!result.ok) {
      return result;
    }
  }
  return { ok: true };
}

function mergeArgValue(
  target: Record<string, unknown>,
  key: string,
  value: unknown,
): { ok: true } | { ok: false; code: string; message: string } {
  if (target[key] === undefined) {
    target[key] = value;
    return { ok: true };
  }
  if (sameJsonValue(target[key], value)) {
    return { ok: true };
  }
  return envelopeConflict(
    `conflicting \`args.${key}\` values were received for gee.gear.invoke.`,
  );
}

function envelopeConflict(
  message: string,
): { ok: false; code: string; message: string } {
  return {
    ok: false,
    code: "gear.args.envelope",
    message,
  };
}

function sameJsonValue(left: unknown, right: unknown): boolean {
  if (Object.is(left, right)) {
    return true;
  }
  return JSON.stringify(left) === JSON.stringify(right);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}


export function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
