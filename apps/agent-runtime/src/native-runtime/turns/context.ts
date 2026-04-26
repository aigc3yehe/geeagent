import { createHash } from "node:crypto";

import { activeConversation, syncConversationStatuses } from "../store/conversations.js";
import { currentTimestamp } from "../store/defaults.js";
import type { AgentProfile, RuntimeConversation, RuntimeStore } from "../store/types.js";
import type { TurnRoute } from "../sdk-turn-runner.js";
import { summarizePrompt } from "./state.js";
import type { PreparedTurnContext } from "./types.js";

const CONTEXT_AUTO_SUMMARY_TRIGGER_TOKENS = 220_000;
const CONTEXT_RECENT_MESSAGE_KEEP_COUNT = 24;

export function prepareTurnContext(
  store: RuntimeStore,
  route: TurnRoute,
  text: string,
): PreparedTurnContext {
  return {
    activeAgentProfile: resolvedActiveAgentProfile(store),
    workspaceMessages:
      route.mode === "workspace_message" ? workspaceMessagesFromStore(store) : [],
    shouldReuseActiveConversation: shouldReuseActiveConversation(store, text),
  };
}

export function composeClaudeSdkTurnPrompt(
  route: TurnRoute,
  prepared: PreparedTurnContext,
  text: string,
): string {
  const trimmed = text.trim();
  if (route.mode === "quick_prompt" || prepared.workspaceMessages.length === 0) {
    return trimmed;
  }

  const projectedMessages = contextProjectedWorkspaceMessages(prepared.workspaceMessages)[0];
  const history = projectedMessages
    .map((message) => `${message.role === "assistant" ? "Assistant" : "User"}: ${message.content}`)
    .join("\n");

  return `Conversation context before the latest turn:\n${history}\n\nLatest user request:\n${trimmed}\n\nSolve the latest request directly. Use tools when needed. Do not ask the user to type 'continue' for ordinary local work.`;
}

export function routeQuickPromptToBestConversation(
  store: RuntimeStore,
  prompt: string,
): string | null {
  const match = bestQuickPromptConversationMatch(store, prompt);
  if (!match) {
    return null;
  }
  if (match.conversationId !== store.active_conversation_id) {
    store.active_conversation_id = match.conversationId;
    store.workspace_focus = { mode: "default", task_id: null };
    syncConversationStatuses(store);
  }
  return match.conversationId;
}

function bestQuickPromptConversationMatch(
  store: RuntimeStore,
  prompt: string,
): { conversationId: string; score: number } | null {
  const keywords = routingTopicKeywords(prompt);
  if (keywords.size === 0) {
    return null;
  }
  const scored = store.conversations
    .map((conversation) => ({
      conversationId: conversation.conversation_id,
      score: conversationTopicMatchScore(conversation, keywords),
    }))
    .filter((item) => item.score > 0)
    .sort((left, right) => right.score - left.score || left.conversationId.localeCompare(right.conversationId));
  const best = scored[0];
  if (!best) {
    return null;
  }
  if (scored[1]?.score === best.score) {
    return null;
  }
  return best;
}

function shouldReuseActiveConversation(store: RuntimeStore, prompt: string): boolean {
  const keywords = routingTopicKeywords(prompt);
  return keywords.size > 0 && conversationTopicMatchScore(activeConversation(store), keywords) > 0;
}

function routingTopicKeywords(text: string): Set<string> {
  const generic = new Set([
    "answer",
    "check",
    "find",
    "official",
    "search",
    "site",
    "translate",
    "translation",
    "url",
    "website",
    "word",
  ]);
  return new Set([...normalizedKeywords(text)].filter((keyword) => !generic.has(keyword)));
}

function normalizedKeywords(text: string): Set<string> {
  const stopwords = new Set([
    "about",
    "after",
    "before",
    "from",
    "have",
    "into",
    "just",
    "keep",
    "latest",
    "local",
    "should",
    "that",
    "them",
    "then",
    "this",
    "what",
    "with",
    "would",
    "your",
  ]);
  const out = new Set<string>();
  for (const raw of text.toLowerCase().split(/[^a-z0-9]+/)) {
    if (raw.length < 4 || stopwords.has(raw)) {
      continue;
    }
    out.add(raw.endsWith("s") && raw.length > 4 ? raw.slice(0, -1) : raw);
  }
  for (const token of cjkTopicKeywords(text)) {
    out.add(token);
  }
  return out;
}

function cjkTopicKeywords(text: string): string[] {
  const tokens = new Set<string>();
  const runs = text.match(/[\u3400-\u4dbf\u4e00-\u9fff]+/g) ?? [];
  for (const run of runs) {
    if (run.length < 2) {
      continue;
    }
    if (run.length <= 8) {
      tokens.add(run);
    }
    for (let size = 2; size <= 4; size += 1) {
      for (let index = 0; index + size <= run.length; index += 1) {
        tokens.add(run.slice(index, index + size));
      }
    }
  }
  return [...tokens];
}

function conversationTopicMatchScore(
  conversation: RuntimeConversation,
  promptKeywords: Set<string>,
): number {
  const context = `${conversation.title} ${conversation.messages
    .slice(-12)
    .map((message) => message.content)
    .join(" ")}`.toLowerCase();
  const conversationKeywords = normalizedKeywords(context);
  let score = 0;
  for (const keyword of promptKeywords) {
    if (!conversationKeywords.has(keyword)) {
      continue;
    }
    const occurrenceCount = Math.min(4, context.split(keyword).length - 1 || 1);
    const titleBonus = conversation.title.toLowerCase().includes(keyword) ? 3 : 0;
    score += occurrenceCount + titleBonus;
  }
  return score;
}

export function isTransientQuickPrompt(prompt: string): boolean {
  const trimmed = prompt.trim();
  if (!trimmed) {
    return false;
  }
  const lowered = trimmed.toLowerCase();
  const looksLikeMath =
    /[0-9]/.test(trimmed) &&
    /[+\-*/×÷=^%()]/.test(trimmed) &&
    [...trimmed].length <= 120;
  if (looksLikeMath) {
    return true;
  }
  return (
    ["translate ", "what is ", "what's ", "calculate ", "spell ", "define "].some(
      (pattern) => lowered.includes(pattern),
    ) && [...trimmed].length <= 120
  );
}

export function quickConversationTitle(prompt: string): string {
  return summarizePrompt(prompt, 64);
}

export function transientRuntimeSessionId(text: string): string {
  const hash = createHash("sha256")
    .update(text)
    .update(currentTimestamp())
    .digest("hex")
    .slice(0, 16);
  return `session_quick_transient_${hash}`;
}

function workspaceMessagesFromStore(
  store: RuntimeStore,
): Array<{ role: string; content: string }> {
  return activeConversation(store).messages.map((message) => ({
    role: message.role,
    content: message.content,
  }));
}

function contextProjectedWorkspaceMessages(
  messages: Array<{ role: string; content: string }>,
): [Array<{ role: string; content: string }>, number, number] {
  const rawTokens = estimateWorkspaceMessagesTokens(messages);
  if (
    rawTokens < CONTEXT_AUTO_SUMMARY_TRIGGER_TOKENS ||
    messages.length <= CONTEXT_RECENT_MESSAGE_KEEP_COUNT
  ) {
    return [messages, 0, rawTokens];
  }
  const splitAt = messages.length - CONTEXT_RECENT_MESSAGE_KEEP_COUNT;
  const older = messages.slice(0, splitAt);
  const recent = messages.slice(splitAt);
  const summary = {
    role: "assistant",
    content: buildContextCompactionSummary(older),
  };
  const projected = [summary, ...recent];
  return [projected, older.length, estimateWorkspaceMessagesTokens(projected)];
}

function buildContextCompactionSummary(
  messages: Array<{ role: string; content: string }>,
): string {
  const userMessages = messages
    .filter((message) => message.role !== "assistant")
    .map((message) => summarizePrompt(message.content, 180));
  const assistantMessages = messages
    .filter((message) => message.role === "assistant")
    .map((message) => summarizePrompt(message.content, 180));
  return [
    "[AUTO CONTEXT SUMMARY] Older conversation turns were compacted before the 256k context window filled. The full transcript remains available in GeeAgent history; this summary is the model-facing continuity layer.",
    `Compacted messages: ${messages.length}.`,
    userMessages.length > 0
      ? `User intent and feedback from compacted history:\n${userMessages
          .slice(0, 12)
          .map((entry) => `- ${entry}`)
          .join("\n")}`
      : "",
    assistantMessages.length > 0
      ? `Prior assistant work from compacted history:\n${assistantMessages
          .slice(-8)
          .map((entry) => `- ${entry}`)
          .join("\n")}`
      : "",
    "Continue from the recent verbatim messages below. Preserve active tasks, approvals, files, commands, and user corrections from the recent context.",
  ]
    .filter(Boolean)
    .join("\n");
}

function estimateWorkspaceMessagesTokens(
  messages: Array<{ role: string; content: string }>,
): number {
  return messages.reduce(
    (sum, message) =>
      sum + approximateContextTokens(message.role) + approximateContextTokens(message.content) + 8,
    0,
  );
}

function approximateContextTokens(text: string): number {
  let cjkChars = 0;
  let otherChars = 0;
  for (const ch of text) {
    if (/[\u3400-\u4dbf\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]/.test(ch)) {
      cjkChars += 1;
    } else {
      otherChars += 1;
    }
  }
  const charEstimate = cjkChars + Math.ceil(otherChars / 4);
  const byteEstimate = Math.ceil(Buffer.byteLength(text) / 4);
  return Math.max(1, charEstimate, byteEstimate);
}

function resolvedActiveAgentProfile(store: RuntimeStore): AgentProfile {
  return (
    store.agent_profiles.find((profile) => profile.id === store.active_agent_profile_id) ??
    store.agent_profiles[0]
  );
}
