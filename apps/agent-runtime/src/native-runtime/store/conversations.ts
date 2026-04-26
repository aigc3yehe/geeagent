import { randomUUID } from "node:crypto";

import { currentTimestamp } from "./defaults.js";
import type {
  RuntimeConversation,
  RuntimeConversationSummary,
  RuntimeStore,
} from "./types.js";

const PREVIEW_LIMIT = 72;

function summarizePreview(text: string): string {
  return text.length > PREVIEW_LIMIT ? `${text.slice(0, PREVIEW_LIMIT)}…` : text;
}

export function summarizeConversation(
  store: RuntimeStore,
  conversation: RuntimeConversation,
): RuntimeConversationSummary {
  const lastMessage = conversation.messages.at(-1);
  return {
    conversation_id: conversation.conversation_id,
    title: conversation.title,
    status: conversation.status,
    last_message_preview: summarizePreview(lastMessage?.content ?? "Fresh conversation."),
    last_timestamp: lastMessage?.timestamp ?? currentTimestamp(),
    is_active: conversation.conversation_id === store.active_conversation_id,
  };
}

export function syncConversationStatuses(store: RuntimeStore): void {
  for (const conversation of store.conversations) {
    conversation.status =
      conversation.conversation_id === store.active_conversation_id ? "active" : "idle";
  }
}

export function activeConversation(store: RuntimeStore): RuntimeConversation {
  const found = store.conversations.find(
    (conversation) => conversation.conversation_id === store.active_conversation_id,
  );
  if (found) {
    return found;
  }
  store.active_conversation_id = store.conversations[0]?.conversation_id ?? "conv_01";
  return store.conversations[0] ?? createConversation(store, "New Conversation");
}

export function createConversation(store: RuntimeStore, title?: string): RuntimeConversation {
  const index = nextConversationIndex(store);
  const conversationId = newConversationId(index, store);
  const conversation: RuntimeConversation = {
    conversation_id: conversationId,
    title: title?.trim() || `Conversation ${index}`,
    status: "active",
    messages: [
      {
        message_id: `msg_assistant_${String(index).padStart(2, "0")}`,
        role: "assistant",
        content: "New conversation ready. Tell GeeAgent what to do next.",
        timestamp: currentTimestamp(),
      },
    ],
  };
  store.conversations.push(conversation);
  store.active_conversation_id = conversation.conversation_id;
  store.workspace_focus = { mode: "default", task_id: null };
  syncConversationStatuses(store);
  return conversation;
}

export function activateConversation(store: RuntimeStore, conversationId: string): void {
  const exists = store.conversations.some(
    (conversation) => conversation.conversation_id === conversationId,
  );
  if (!exists) {
    throw new Error("conversation not found");
  }
  store.active_conversation_id = conversationId;
  store.workspace_focus = { mode: "default", task_id: null };
  syncConversationStatuses(store);
}

export function deleteConversation(store: RuntimeStore, conversationId: string): void {
  const before = store.conversations.length;
  const deletedSessionIds = sessionIdsForConversation(store, conversationId);
  store.conversations = store.conversations.filter(
    (conversation) => conversation.conversation_id !== conversationId,
  );
  if (store.conversations.length === before) {
    throw new Error("conversation not found");
  }
  pruneConversationRuntimeHistory(store, conversationId, deletedSessionIds);
  if (store.conversations.length === 0) {
    createConversation(store, "Fresh Conversation");
    return;
  }
  if (store.active_conversation_id === conversationId) {
    store.active_conversation_id = store.conversations[0].conversation_id;
  }
  syncConversationStatuses(store);
}

function nextConversationIndex(store: RuntimeStore): number {
  let next = store.conversations.length + 1;
  const ids = new Set(store.conversations.map((conversation) => conversation.conversation_id));
  while (ids.has(`conv_${String(next).padStart(2, "0")}`)) {
    next += 1;
  }
  return next;
}

function newConversationId(index: number, store: RuntimeStore): string {
  const existingIds = new Set(store.conversations.map((conversation) => conversation.conversation_id));
  while (true) {
    const candidate = `conv_${String(index).padStart(2, "0")}_${randomUUID().slice(0, 8)}`;
    if (!existingIds.has(candidate)) {
      return candidate;
    }
  }
}

function sessionIdsForConversation(store: RuntimeStore, conversationId: string): Set<string> {
  const sessionIds = new Set([`session_${conversationId}`]);
  for (const session of store.execution_sessions) {
    if (!isRecord(session)) {
      continue;
    }
    if (
      session.conversation_id === conversationId &&
      typeof session.session_id === "string"
    ) {
      sessionIds.add(session.session_id);
    }
  }
  return sessionIds;
}

function pruneConversationRuntimeHistory(
  store: RuntimeStore,
  conversationId: string,
  sessionIds: Set<string>,
): void {
  store.execution_sessions = store.execution_sessions.filter((session) => {
    if (!isRecord(session)) {
      return true;
    }
    if (session.conversation_id === conversationId) {
      return false;
    }
    return typeof session.session_id !== "string" || !sessionIds.has(session.session_id);
  });
  store.transcript_events = store.transcript_events.filter((event) => {
    if (!isRecord(event)) {
      return true;
    }
    return typeof event.session_id !== "string" || !sessionIds.has(event.session_id);
  });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
