import type { ContextProjection } from "./types.js";

export function renderProjectedTurnPrompt(
  projection: ContextProjection,
  latestUserRequest: string,
): string {
  const trimmed = latestUserRequest.trim();
  if (projection.messages.length === 0) {
    return trimmed;
  }

  const history = projection.messages
    .map((message) => `${message.role === "assistant" ? "Assistant" : "User"}: ${message.content}`)
    .join("\n");

  const projectionNote =
    projection.mode === "compacted"
      ? [
          "Context projection mode: compacted.",
          `Older compacted messages: ${projection.compactedMessagesCount}.`,
          `Estimated model-facing history tokens: ${projection.projectedHistoryTokens} of ${projection.rawHistoryTokens} raw history tokens.`,
        ].join("\n")
      : [
          "Context projection mode: recent.",
          `Estimated model-facing history tokens: ${projection.projectedHistoryTokens}.`,
        ].join("\n");

  return [
    "Conversation context before the latest turn:",
    projectionNote,
    "",
    history,
    "",
    "Latest user request:",
    trimmed,
    "",
    "Solve the latest request directly. Use tools when needed. Do not ask the user to type 'continue' for ordinary local work.",
  ].join("\n");
}
