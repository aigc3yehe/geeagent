export type PreToolUseBoundaryOutput = {
  continue: true;
  hookSpecificOutput: {
    hookEventName: "PreToolUse";
    updatedInput: Record<string, unknown>;
  };
};

type RecordLike = Record<string, unknown>;

export function normalizeToolInput(input: unknown): RecordLike {
  if (input && typeof input === "object" && !Array.isArray(input)) {
    return input as RecordLike;
  }
  return {};
}

export function normalizeToolBoundaryInput(
  toolName: string,
  input: unknown,
): RecordLike {
  const normalized = { ...normalizeToolInput(input) };
  if (toolName === "mcp__gee__gear_invoke" || toolName === "gee.gear.invoke") {
    return normalizeGeeGearInvokeInput(normalized);
  }
  if (
    toolName === "Read" &&
    typeof normalized.pages === "string" &&
    normalized.pages.trim().length === 0
  ) {
    delete normalized.pages;
  }
  return normalized;
}

export function normalizeGeeGearInvokeInput(input: RecordLike): RecordLike {
  const nestedArguments = recordValue(input.arguments);
  const normalized: RecordLike = {};

  const gearID = stringValue(input.gear_id) ?? stringValue(nestedArguments?.gear_id);
  const capabilityID =
    stringValue(input.capability_id) ?? stringValue(nestedArguments?.capability_id);
  if (gearID) {
    normalized.gear_id = gearID;
  }
  if (capabilityID) {
    normalized.capability_id = capabilityID;
  }

  const invokeArgs = firstRecord(
    input.args,
    nestedArguments?.args,
    nestedArguments?.input,
    nestedArguments?.payload,
    input.input,
    input.payload,
  );
  normalized.args = invokeArgs ? { ...invokeArgs } : {};

  return normalized;
}

export function preToolUseBoundaryOutput(
  input: unknown,
): PreToolUseBoundaryOutput | undefined {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    return undefined;
  }

  const record = input as RecordLike;
  if (record.hook_event_name !== "PreToolUse") {
    return undefined;
  }

  const toolName = typeof record.tool_name === "string" ? record.tool_name : "";
  const originalInput = normalizeToolInput(record.tool_input);
  const normalizedInput = normalizeToolBoundaryInput(toolName, originalInput);
  if (shallowRecordEqual(originalInput, normalizedInput)) {
    return undefined;
  }

  return {
    continue: true,
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      updatedInput: normalizedInput,
    },
  };
}

function shallowRecordEqual(left: RecordLike, right: RecordLike): boolean {
  const leftEntries = Object.entries(left);
  const rightEntries = Object.entries(right);
  if (leftEntries.length !== rightEntries.length) {
    return false;
  }
  return leftEntries.every(([key, value]) => Object.is(value, right[key]));
}

function recordValue(value: unknown): RecordLike | undefined {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as RecordLike)
    : undefined;
}

function firstRecord(...values: Array<unknown>): RecordLike | undefined {
  for (const value of values) {
    const record = recordValue(value);
    if (record) {
      return record;
    }
  }
  return undefined;
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0 ? value : undefined;
}
