import type {
  TelegramBridgeAccount,
  TelegramBridgeRole,
} from "./config.js";

export type TelegramGatewayUpdate = {
  update_id?: unknown;
  message?: {
    message_id?: unknown;
    message_thread_id?: unknown;
    chat?: {
      id?: unknown;
      type?: unknown;
    };
    from?: {
      id?: unknown;
    };
    text?: unknown;
    caption?: unknown;
    photo?: unknown;
    document?: unknown;
    video?: unknown;
    animation?: unknown;
    audio?: unknown;
    voice?: unknown;
    video_note?: unknown;
    sticker?: unknown;
    paid_media?: unknown;
    contact?: unknown;
    location?: unknown;
    venue?: unknown;
    poll?: unknown;
    dice?: unknown;
    game?: unknown;
  };
};

export type TelegramGatewayEnvelope = {
  source: "telegram.bridge";
  accountId: string;
  role: TelegramBridgeRole;
  updateId: number;
  idempotencyKey: string;
  chat: {
    id: string;
    type?: string;
    threadId?: string;
  };
  sender: {
    userId: string;
  };
  message: {
    id: string;
    text: string;
    attachments: TelegramGatewayAttachmentRef[];
  };
  routing: {
    channelIdentity: string;
  };
  projection: {
    surface: "telegram";
    replyTarget: {
      chatId: string;
      messageId: string;
    };
  };
};

export type TelegramGatewayAttachmentRef = {
  artifact_id: string;
  kind: "telegram_file";
  type: "image" | "video" | "audio" | "document";
  title: string;
  uri: string;
  summary: string;
  mime_type?: string;
  telegram_file_id: string;
  telegram_file_unique_id?: string;
  telegram_media_kind: string;
  width?: number;
  height?: number;
};

export type TelegramGatewaySecurityDecision =
  | { status: "allowed"; policyId: string }
  | { status: "denied"; code: string; message: string };

export type RuntimeChannelMessageInput = {
  source: "telegram.bridge";
  role: "gee_direct";
  channelIdentity: string;
  message: {
    idempotencyKey: string;
    telegramUpdateId: number;
    chatId: string;
    messageId: string;
    fromUserId: string;
    text: string;
    attachments: TelegramGatewayAttachmentRef[];
  };
  security: {
    decision: "allowed";
    policyId: string;
  };
  projection: {
    surface: "telegram";
    replyTarget: {
      chatId: string;
      messageId: string;
    };
  };
};

export type TelegramGatewayNormalizeResult =
  | {
      status: "success";
      envelope: TelegramGatewayEnvelope;
      error: null;
    }
  | {
      status: "failed";
      updateId?: number;
      envelope?: undefined;
      error: {
        code: string;
        message: string;
      };
    };

export function telegramGatewayUpdateId(update: TelegramGatewayUpdate): number | undefined {
  return numberValue(update.update_id);
}

export function normalizeTelegramGatewayUpdate(
  account: TelegramBridgeAccount,
  update: TelegramGatewayUpdate,
): TelegramGatewayNormalizeResult {
  const updateId = telegramGatewayUpdateId(update);
  const message = update.message;
  if (!message) {
    return normalizeFailure(updateId, "message_not_text", "Telegram update did not contain a text message.");
  }
  const unsupportedAttachmentKey = unsupportedTelegramAttachmentKey(message);
  if (unsupportedAttachmentKey) {
    return normalizeFailure(
      updateId,
      "message_attachment_unsupported",
      `Telegram update contains unsupported attachment field \`${unsupportedAttachmentKey}\`.`,
    );
  }

  const chatId = idValue(message.chat?.id);
  const messageId = idValue(message.message_id);
  const fromUserId = idValue(message.from?.id);
  if (!chatId || !messageId || !fromUserId || updateId === undefined) {
    return normalizeFailure(updateId, "message_identity_missing", "Telegram update is missing stable identity fields.");
  }

  const attachments = telegramMediaAttachmentRefs(account, updateId, message, chatId, messageId);
  const text = stringValue(message.text) ?? stringValue(message.caption) ?? (attachments.length > 0 ? "Telegram media attachment received." : null);
  if (!text) {
    return normalizeFailure(updateId, "message_not_text", "Telegram update did not contain a text message.");
  }

  const chatType = stringValue(message.chat?.type);
  const threadId = idValue(message.message_thread_id);
  const channelKind = chatType === "private" ? "dm" : "chat";
  const channelIdentity = [
    `telegram:${account.id}:bot:unknown:${channelKind}:${chatId}`,
    threadId ? `topic:${threadId}` : undefined,
  ].filter(Boolean).join(":");

  return {
    status: "success",
    envelope: {
      source: "telegram.bridge",
      accountId: account.id,
      role: account.role,
      updateId,
      idempotencyKey: `telegram:update:${updateId}`,
      chat: {
        id: chatId,
        type: chatType,
        threadId: threadId ?? undefined,
      },
      sender: {
        userId: fromUserId,
      },
      message: {
        id: messageId,
        text,
        attachments,
      },
      routing: {
        channelIdentity,
      },
      projection: {
        surface: "telegram",
        replyTarget: {
          chatId,
          messageId,
        },
      },
    },
    error: null,
  };
}

export function authorizeTelegramGatewayEnvelope(
  account: TelegramBridgeAccount,
  envelope: TelegramGatewayEnvelope,
): TelegramGatewaySecurityDecision {
  if (account.security?.requirePairing === true) {
    return {
      status: "denied",
      code: "pairing_required_unavailable",
      message: "Telegram pairing is required for this account, but pairing is not implemented in this Gear release.",
    };
  }
  if (envelope.chat.type && envelope.chat.type !== "private") {
    const groupPolicy = account.security?.groupPolicy ?? "deny";
    if (groupPolicy === "deny") {
      return {
        status: "denied",
        code: "group_policy_denied",
        message: "Telegram group messages are denied for this account.",
      };
    }
    if (groupPolicy === "mention_required") {
      if (!account.botUsername?.trim()) {
        return {
          status: "denied",
          code: "group_policy_bot_username_missing",
          message: "Telegram mention-required group policy needs botUsername to be configured.",
        };
      }
      if (!hasBotMention(envelope.message.text, account.botUsername)) {
        return {
          status: "denied",
          code: "group_policy_mention_required",
          message: "Telegram group messages must mention this bot before GeeAgent accepts them.",
        };
      }
    }
  }
  const allowedUsers = normalizedIdSet(account.security?.allowUserIds);
  if (allowedUsers.size > 0 && !allowedUsers.has(envelope.sender.userId)) {
    return {
      status: "denied",
      code: "user_not_allowed",
      message: "Telegram user is not authorized for this account.",
    };
  }
  const allowedChats = normalizedIdSet(account.security?.allowChatIds);
  if (allowedChats.size > 0 && !allowedChats.has(envelope.chat.id)) {
    return {
      status: "denied",
      code: "chat_not_allowed",
      message: "Telegram chat is not authorized for this account.",
    };
  }
  return { status: "allowed", policyId: "allowlist" };
}

export function buildGeeDirectRuntimeInput(
  envelope: TelegramGatewayEnvelope,
  security: Extract<TelegramGatewaySecurityDecision, { status: "allowed" }>,
): RuntimeChannelMessageInput {
  return {
    source: "telegram.bridge",
    role: "gee_direct",
    channelIdentity: envelope.routing.channelIdentity,
    message: {
      idempotencyKey: envelope.idempotencyKey,
      telegramUpdateId: envelope.updateId,
      chatId: envelope.chat.id,
      messageId: envelope.message.id,
      fromUserId: envelope.sender.userId,
      text: envelope.message.text,
      attachments: envelope.message.attachments,
    },
    security: {
      decision: "allowed",
      policyId: security.policyId,
    },
    projection: envelope.projection,
  };
}

function normalizeFailure(
  updateId: number | undefined,
  code: string,
  message: string,
): Extract<TelegramGatewayNormalizeResult, { status: "failed" }> {
  return {
    status: "failed",
    updateId,
    error: {
      code,
      message,
    },
  };
}

function hasBotMention(text: string, botUsername: string): boolean {
  const username = botUsername.trim().replace(/^@+/, "").toLowerCase();
  if (!username) {
    return false;
  }
  const pattern = new RegExp(`(^|[^A-Za-z0-9_])@${escapeRegExp(username)}($|[^A-Za-z0-9_])`);
  return pattern.test(text.toLowerCase());
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function telegramMediaAttachmentRefs(
  account: TelegramBridgeAccount,
  updateId: number,
  message: NonNullable<TelegramGatewayUpdate["message"]>,
  chatId: string,
  messageId: string,
): TelegramGatewayAttachmentRef[] {
  const refs: TelegramGatewayAttachmentRef[] = [];
  const photos = Array.isArray(message.photo) ? message.photo.filter(isRecord) : [];
  const photo = [...photos].reverse().find((item) => idValue(item.file_id));
  if (photo) {
    refs.push(telegramMediaAttachmentRef(account, updateId, chatId, messageId, "photo", photo, "image", "Telegram photo", "image/*"));
  }
  const singleMedia: Array<[string, unknown, TelegramGatewayAttachmentRef["type"], string, string | undefined]> = [
    ["document", message.document, "document", "Telegram document", undefined],
    ["video", message.video, "video", "Telegram video", "video/*"],
    ["animation", message.animation, "video", "Telegram animation", "image/gif"],
    ["audio", message.audio, "audio", "Telegram audio", "audio/*"],
    ["voice", message.voice, "audio", "Telegram voice message", "audio/*"],
    ["video_note", message.video_note, "video", "Telegram video note", "video/*"],
    ["sticker", message.sticker, "image", "Telegram sticker", "image/*"],
  ];
  for (const [mediaKind, value, type, title, mimeType] of singleMedia) {
    if (isRecord(value) && idValue(value.file_id)) {
      refs.push(telegramMediaAttachmentRef(account, updateId, chatId, messageId, mediaKind, value, type, title, mimeType));
    }
  }
  return refs;
}

function telegramMediaAttachmentRef(
  account: TelegramBridgeAccount,
  updateId: number,
  chatId: string,
  messageId: string,
  mediaKind: string,
  file: Record<string, unknown>,
  type: TelegramGatewayAttachmentRef["type"],
  title: string,
  mimeType: string | undefined,
): TelegramGatewayAttachmentRef {
  const fileId = idValue(file.file_id) ?? "unknown";
  const fileUniqueId = idValue(file.file_unique_id) ?? undefined;
  const artifactIdentity = fileUniqueId ?? fileId;
  return {
    artifact_id: `telegram:${account.id}:${updateId}:${mediaKind}:${artifactIdentity}`,
    kind: "telegram_file",
    type,
    title,
    uri: `telegram://file/${fileId}`,
    summary: `${title} attachment from chat ${chatId} message ${messageId}.`,
    ...(mimeType ? { mime_type: mimeType } : {}),
    telegram_file_id: fileId,
    ...(fileUniqueId ? { telegram_file_unique_id: fileUniqueId } : {}),
    telegram_media_kind: mediaKind,
    ...(numberValue(file.width) !== undefined ? { width: numberValue(file.width) } : {}),
    ...(numberValue(file.height) !== undefined ? { height: numberValue(file.height) } : {}),
  };
}

function unsupportedTelegramAttachmentKey(message: NonNullable<TelegramGatewayUpdate["message"]>): string | null {
  const unsupportedKeys = [
    "paid_media",
    "contact",
    "location",
    "venue",
    "poll",
    "dice",
    "game",
  ];
  for (const key of unsupportedKeys) {
    if (message[key as keyof typeof message] !== undefined && message[key as keyof typeof message] !== null) {
      return key;
    }
  }
  return null;
}

function normalizedIdSet(values: unknown): Set<string> {
  if (!Array.isArray(values)) {
    return new Set();
  }
  return new Set(
    values
      .map((value) => String(value).trim())
      .filter(Boolean),
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function idValue(value: unknown): string | null {
  if (typeof value === "string" && value.trim()) {
    return value.trim();
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return String(value);
  }
  return null;
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function numberValue(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}
