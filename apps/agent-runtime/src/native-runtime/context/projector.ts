import { summarizePrompt } from "../turns/state.js";
import {
  estimateMessagesTokens,
  estimateTextTokens,
} from "./token-estimator.js";
import type {
  ContextBudgetRecord,
  ContextProjection,
  ContextProjectionOptions,
  ModelFacingMessage,
} from "./types.js";

const DEFAULT_MAX_CONTEXT_TOKENS = 256_000;
const DEFAULT_RESERVED_OUTPUT_TOKENS = 8_192;
const DEFAULT_RECENT_TOKEN_BUDGET = 32_000;
const DEFAULT_COMPACT_TRIGGER_TOKENS = 48_000;

export function buildContextProjection(
  history: ModelFacingMessage[],
  options: ContextProjectionOptions,
): ContextProjection {
  const maxContextTokens = options.maxContextTokens ?? DEFAULT_MAX_CONTEXT_TOKENS;
  const reservedOutputTokens =
    options.reservedOutputTokens ?? DEFAULT_RESERVED_OUTPUT_TOKENS;
  const recentTokenBudget = options.recentTokenBudget ?? DEFAULT_RECENT_TOKEN_BUDGET;
  const compactTriggerTokens =
    options.compactTriggerTokens ?? DEFAULT_COMPACT_TRIGGER_TOKENS;
  const latestRequestTokens = estimateTextTokens(options.latestUserRequest);
  const rawHistoryTokens = estimateMessagesTokens(history);

  if (history.length === 0) {
    return {
      mode: "latest_only",
      messages: [],
      compactedMessagesCount: 0,
      rawHistoryTokens,
      projectedHistoryTokens: 0,
      recentTokens: 0,
      summaryTokens: 0,
      latestRequestTokens,
      estimatedInputTokens: latestRequestTokens,
      maxContextTokens,
      reservedOutputTokens,
    };
  }

  if (rawHistoryTokens <= compactTriggerTokens) {
    return {
      mode: "full_recent",
      messages: history,
      compactedMessagesCount: 0,
      rawHistoryTokens,
      projectedHistoryTokens: rawHistoryTokens,
      recentTokens: rawHistoryTokens,
      summaryTokens: 0,
      latestRequestTokens,
      estimatedInputTokens: rawHistoryTokens + latestRequestTokens,
      maxContextTokens,
      reservedOutputTokens,
    };
  }

  const tail = recentMessagesWithinBudget(history, recentTokenBudget);
  const compacted = history.slice(0, history.length - tail.messages.length);
  if (compacted.length === 0) {
    return {
      mode: "full_recent",
      messages: history,
      compactedMessagesCount: 0,
      rawHistoryTokens,
      projectedHistoryTokens: rawHistoryTokens,
      recentTokens: rawHistoryTokens,
      summaryTokens: 0,
      latestRequestTokens,
      estimatedInputTokens: rawHistoryTokens + latestRequestTokens,
      maxContextTokens,
      reservedOutputTokens,
    };
  }
  const summaryMessage: ModelFacingMessage = {
    role: "assistant",
    content: buildReferenceSummary(compacted),
  };
  const projected = [summaryMessage, ...tail.messages];
  const summaryTokens = estimateMessagesTokens([summaryMessage]);
  const projectedHistoryTokens = estimateMessagesTokens(projected);
  if (projectedHistoryTokens > rawHistoryTokens) {
    return {
      mode: "compacted",
      messages: tail.messages,
      compactedMessagesCount: compacted.length,
      rawHistoryTokens,
      projectedHistoryTokens: tail.tokens,
      recentTokens: tail.tokens,
      summaryTokens: 0,
      latestRequestTokens,
      estimatedInputTokens: tail.tokens + latestRequestTokens,
      maxContextTokens,
      reservedOutputTokens,
    };
  }

  return {
    mode: "compacted",
    messages: projected,
    compactedMessagesCount: compacted.length,
    rawHistoryTokens,
    projectedHistoryTokens,
    recentTokens: tail.tokens,
    summaryTokens,
    latestRequestTokens,
    estimatedInputTokens: projectedHistoryTokens + latestRequestTokens,
    maxContextTokens,
    reservedOutputTokens,
  };
}

export function contextBudgetRecordFromProjection(
  projection: ContextProjection,
): ContextBudgetRecord {
  return {
    max_tokens: projection.maxContextTokens,
    used_tokens: projection.estimatedInputTokens,
    reserved_output_tokens: projection.reservedOutputTokens,
    usage_ratio: projection.estimatedInputTokens / projection.maxContextTokens,
    estimate_source: "estimated",
    summary_state: projection.mode === "compacted" ? "projecting" : "watching",
    next_summary_at_ratio: 0.7,
    compacted_messages_count: projection.compactedMessagesCount,
    projection_mode: projection.mode,
    raw_history_tokens: projection.rawHistoryTokens,
    projected_history_tokens: projection.projectedHistoryTokens,
    recent_tokens: projection.recentTokens,
    summary_tokens: projection.summaryTokens,
    latest_request_tokens: projection.latestRequestTokens,
  };
}

function recentMessagesWithinBudget(
  history: ModelFacingMessage[],
  budget: number,
): { messages: ModelFacingMessage[]; tokens: number } {
  const kept: ModelFacingMessage[] = [];
  let tokens = 0;

  for (let index = history.length - 1; index >= 0; index -= 1) {
    const message = history[index];
    const messageTokens = estimateMessagesTokens([message]);
    if (kept.length > 0 && tokens + messageTokens > budget) {
      break;
    }
    kept.unshift(message);
    tokens += messageTokens;
  }

  return { messages: kept, tokens };
}

function buildReferenceSummary(messages: ModelFacingMessage[]): string {
  const userMessages = messages
    .filter((message) => message.role !== "assistant")
    .map((message) => summarizePrompt(message.content, 220));
  const assistantMessages = messages
    .filter((message) => message.role === "assistant")
    .map((message) => summarizePrompt(message.content, 220));

  return [
    "[CONTEXT COMPACTION - REFERENCE ONLY]",
    "Earlier conversation turns were compacted before continuing this task. This summary is background reference, not an active user request. Do not re-answer old questions unless the latest user request asks for it.",
    `Compacted messages: ${messages.length}.`,
    userMessages.length > 0
      ? `User intent and feedback from compacted history:\n${userMessages
          .slice(-12)
          .map((entry) => `- ${entry}`)
          .join("\n")}`
      : "",
    assistantMessages.length > 0
      ? `Prior assistant outcomes from compacted history:\n${assistantMessages
          .slice(-8)
          .map((entry) => `- ${entry}`)
          .join("\n")}`
      : "",
    "Continue from the recent verbatim turns and the latest user request below. Preserve concrete decisions, files, commands, approvals, and user corrections from recent context.",
  ]
    .filter(Boolean)
    .join("\n");
}

export const __contextProjectorTestHooks = {
  buildReferenceSummary,
  recentMessagesWithinBudget,
};
