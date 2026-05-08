import {
  CHAT_ONLY_SDK_AUTO_APPROVE_TOOLS,
  CHAT_ONLY_SDK_AVAILABLE_TOOLS,
} from "../../sdk-tool-policy.js";
import type { RuntimeInputAttachment } from "../store/types.js";

export type ChatTurnMode =
  | "plain_chat"
  | "vision"
  | "local_context"
  | "agentic_task";

export type ChatTurnPolicy = {
  mode: ChatTurnMode;
  toolProfile: "none" | "normal";
  requiresFinalReplyAfterTool: true;
};

export type SdkTurnToolOptions = {
  availableTools?: string[];
  autoApproveTools?: string[];
  enableGeeHostTools?: boolean;
};

export function classifyChatTurnPolicy(
  text: string,
  attachments: RuntimeInputAttachment[],
): ChatTurnPolicy {
  if (isPlainConversationalTurn(text, attachments)) {
    return noToolPolicy("plain_chat");
  }
  if (isVisionOnlyTurn(text, attachments)) {
    return noToolPolicy("vision");
  }
  if (hasLocalContextSignal(text, attachments)) {
    return normalToolPolicy("local_context");
  }
  return normalToolPolicy("agentic_task");
}

export function sdkToolOptionsForTurn(
  text: string,
  attachments: RuntimeInputAttachment[],
): SdkTurnToolOptions {
  const policy = classifyChatTurnPolicy(text, attachments);
  if (policy.toolProfile === "normal") {
    return {};
  }
  return {
    availableTools: CHAT_ONLY_SDK_AVAILABLE_TOOLS,
    autoApproveTools: CHAT_ONLY_SDK_AUTO_APPROVE_TOOLS,
    enableGeeHostTools: false,
  };
}

export function isPlainConversationalTurn(
  text: string,
  attachments: RuntimeInputAttachment[],
): boolean {
  if (attachments.length > 0) {
    return false;
  }
  const trimmed = text.trim();
  if (!trimmed || trimmed.length > 160) {
    return false;
  }
  if (containsLocalOrRemoteReference(trimmed) || containsTaskOrToolVerb(trimmed)) {
    return false;
  }
  const normalized = trimmed.toLowerCase().replace(/[.!?]+$/g, "").trim();
  return (
    /^(hi|hello|hey|yo|hiya|howdy|gm|gn|ok|okay|cool|nice|thanks|thank you)$/.test(normalized) ||
    /^(good morning|good afternoon|good evening|who are you|what are you|what can you do|help)$/.test(normalized)
  );
}

function isVisionOnlyTurn(
  text: string,
  attachments: RuntimeInputAttachment[],
): boolean {
  if (attachments.length === 0 || !attachments.every((attachment) => attachment.kind === "image")) {
    return false;
  }
  return !asksForToolBasedImageVerification(text);
}

function hasLocalContextSignal(
  text: string,
  attachments: RuntimeInputAttachment[],
): boolean {
  return (
    attachments.some((attachment) => attachment.kind === "file" || attachment.kind === "directory") ||
    containsLocalOrRemoteReference(text)
  );
}

function asksForToolBasedImageVerification(text: string): boolean {
  const trimmed = text.trim();
  return (
    /\b(use|run|call)\b.*\b(ocr|tool|bash|read|metadata|mdls|filesystem)\b/i.test(trimmed) ||
    /\b(ocr|metadata|mdls)\b.*\b(tool|verify|check|compare)\b/i.test(trimmed)
  );
}

function noToolPolicy(mode: ChatTurnMode): ChatTurnPolicy {
  return {
    mode,
    toolProfile: "none",
    requiresFinalReplyAfterTool: true,
  };
}

function normalToolPolicy(mode: ChatTurnMode): ChatTurnPolicy {
  return {
    mode,
    toolProfile: "normal",
    requiresFinalReplyAfterTool: true,
  };
}

function containsLocalOrRemoteReference(text: string): boolean {
  return (
    /https?:\/\//i.test(text) ||
    /```|`[^`]+`/.test(text) ||
    /(?:^|\s)(?:\.{0,2}\/|~\/|\/Users\/|\/Volumes\/|[A-Za-z]:\\)/.test(text)
  );
}

function containsTaskOrToolVerb(text: string): boolean {
  return /\b(write|save|create|edit|modify|delete|remove|move|rename|copy|read|open|list|find|search|grep|run|execute|build|test|install|commit|push|pull|download|upload|send|compare|inspect|debug|fix|review|summarize)\b/i.test(text);
}
