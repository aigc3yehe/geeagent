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
  if (
    toolName === "Read" &&
    typeof normalized.pages === "string" &&
    normalized.pages.trim().length === 0
  ) {
    delete normalized.pages;
  }
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
