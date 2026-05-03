import { createHash } from "node:crypto";

import {
  buildContextProjection,
  contextBudgetRecordFromProjection,
} from "../context/projector.js";
import { renderProjectedTurnPrompt } from "../context/prompt-renderer.js";
import {
  activeConversation,
  isQuickConversation,
  syncConversationStatuses,
} from "../store/conversations.js";
import { currentTimestamp } from "../store/defaults.js";
import type { AgentProfile, RuntimeConversation, RuntimeStore } from "../store/types.js";
import type { TurnRoute } from "../sdk-turn-runner.js";
import type { RuntimePlanningMode } from "./planning.js";
import { isRecord, summarizePrompt } from "./state.js";
import type { PreparedTurnContext } from "./types.js";

const MAX_STAGE_CAPSULES_IN_PROMPT = 3;

export function prepareTurnContext(
  store: RuntimeStore,
  route: TurnRoute,
  text: string,
  planningMode: RuntimePlanningMode = "structured",
): PreparedTurnContext {
  const workspaceMessages =
    route.mode === "workspace_message" ? workspaceMessagesFromStore(store) : [];
  const stageCapsuleMessages =
    route.mode === "workspace_message" && shouldInjectStageCapsules(planningMode)
      ? stageCapsuleMessagesFromStore(store)
      : [];
  const baseProjection = buildContextProjection(workspaceMessages, {
    latestUserRequest: text,
  });
  const modelFacingMessages =
    baseProjection.mode === "compacted"
      ? [...workspaceMessages, ...stageCapsuleMessages]
      : workspaceMessages;
  const contextProjection = buildContextProjection(modelFacingMessages, {
    latestUserRequest: text,
  });
  store.context_budget = contextBudgetRecordFromProjection(contextProjection);

  return {
    activeAgentProfile: resolvedActiveAgentProfile(store),
    workspaceMessages,
    stageCapsuleMessages,
    contextProjection,
    shouldReuseActiveConversation:
      route.mode === "quick_prompt" ? false : shouldReuseActiveConversation(store, text),
  };
}

function shouldInjectStageCapsules(planningMode: RuntimePlanningMode): boolean {
  return planningMode === "structured" || planningMode === "recovery";
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

  return renderProjectedTurnPrompt(prepared.contextProjection, trimmed);
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
    .filter((conversation) => !isQuickConversation(conversation))
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
  const conversation = activeConversation(store);
  return (
    keywords.size > 0 &&
    !isQuickConversation(conversation) &&
    conversationTopicMatchScore(conversation, keywords) > 0
  );
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

function stageCapsuleMessagesFromStore(
  store: RuntimeStore,
): Array<{ role: "assistant"; content: string }> {
  const activeSessionId = `session_${store.active_conversation_id}`;
  return store.transcript_events
    .filter((event) => isRecord(event) && event.session_id === activeSessionId)
    .map((event) => (isRecord(event) ? event.payload : null))
    .filter((payload): payload is Record<string, unknown> => isRecord(payload))
    .map((payload) => payload.stage_capsule)
    .filter((value): value is string => typeof value === "string" && value.trim().length > 0)
    .slice(-MAX_STAGE_CAPSULES_IN_PROMPT)
    .map((content) => ({
      role: "assistant",
      content,
    }));
}

function resolvedActiveAgentProfile(store: RuntimeStore): AgentProfile {
  return (
    store.agent_profiles.find((profile) => profile.id === store.active_agent_profile_id) ??
    store.agent_profiles[0]
  );
}
