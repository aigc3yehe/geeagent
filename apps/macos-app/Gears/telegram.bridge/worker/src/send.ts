import {
  redactTelegramTarget,
  resolvePushChannel,
  type TelegramBridgeConfig,
  type TelegramPushTarget,
  type TelegramPushTargetKind,
} from "./config.js";

export type PushMessageRequest = {
  channelId: string;
  message: string;
  idempotencyKey: string;
  title?: string;
  parseMode?: "Markdown" | "MarkdownV2" | "HTML" | "plain";
  disableWebPreview?: boolean;
  artifactRefs?: string[];
};

export type TelegramSendInput = {
  token: string;
  target: TelegramPushTarget;
  message: string;
  parseMode?: "Markdown" | "MarkdownV2" | "HTML";
  disableWebPreview?: boolean;
  idempotencyKey: string;
};

export type TelegramSendResult =
  | {
      ok: true;
      telegramMessageId: string;
      sentAt: string;
    }
  | {
      ok: false;
      code: string;
      message: string;
      retryAfterMs?: number;
    };

export type TelegramSendClient = {
  sendMessage(input: TelegramSendInput): Promise<TelegramSendResult>;
};

export type PushSendDependencies = {
  tokenProvider(accountId: string): Promise<string | undefined>;
  telegramClient: TelegramSendClient;
};

export type PushSendStatus = "success" | "partial" | "blocked" | "degraded" | "failed";

export type PushSendResult = {
  status: PushSendStatus;
  fallback_attempted: false;
  channelId: string;
  accountId?: string;
  target?: {
    kind: TelegramPushTargetKind;
    redacted: string;
  };
  delivery?: {
    telegramMessageId: string;
    sentAt: string;
    idempotencyKey: string;
  };
  error: null | {
    code: string;
    message: string;
    retryAfterMs?: number;
  };
};

const TELEGRAM_TEXT_LIMIT = 4096;
const DEGRADABLE_TELEGRAM_CODES = new Set([
  "telegram_rate_limited",
  "network_unavailable",
  "telegram_timeout",
]);

export async function sendPushMessage(
  config: TelegramBridgeConfig,
  request: PushMessageRequest,
  dependencies: PushSendDependencies,
): Promise<PushSendResult> {
  const channelId = request.channelId.trim();
  if (!channelId) {
    return failedResult("failed", "", "channel_id_missing", "`channelId` is required.");
  }
  const message = request.message;
  if (!message.trim()) {
    return failedResult("blocked", channelId, "message_missing", "`message` is required.");
  }
  if (message.length > TELEGRAM_TEXT_LIMIT) {
    return failedResult(
      "blocked",
      channelId,
      "message_too_large",
      `Telegram text messages must be ${TELEGRAM_TEXT_LIMIT} characters or fewer.`,
    );
  }
  const idempotencyKey = request.idempotencyKey.trim();
  if (!idempotencyKey) {
    return failedResult("blocked", channelId, "idempotency_key_missing", "`idempotencyKey` is required.");
  }

  const resolved = resolvePushChannel(config, channelId);
  if (resolved.status !== "success") {
    return failedResult("failed", channelId, resolved.error.code, resolved.error.message);
  }

  const rawChannel = config.pushChannels?.find((candidate) => candidate.id === channelId);
  const account = config.accounts.find((candidate) => candidate.id === resolved.channel.accountId);
  if (!rawChannel || !account) {
    return failedResult("failed", channelId, "channel_resolution_failed", "Push-only channel resolution lost its account binding.");
  }

  let token: string | undefined;
  try {
    token = (await dependencies.tokenProvider(account.id))?.trim();
  } catch {
    return failedResult(
      "failed",
      channelId,
      "token_unavailable",
      `Telegram bot token lookup failed for account \`${account.id}\`.`,
      {
        accountId: account.id,
        target: redactTelegramTarget(rawChannel.target),
      },
    );
  }
  if (!token) {
    return failedResult("failed", channelId, "token_missing", `Telegram bot token is missing for account \`${account.id}\`.`, {
      accountId: account.id,
      target: redactTelegramTarget(rawChannel.target),
    });
  }

  let telegramResult: TelegramSendResult;
  try {
    telegramResult = await dependencies.telegramClient.sendMessage({
      token,
      target: rawChannel.target,
      message,
      parseMode: normalizeParseMode(request.parseMode ?? rawChannel.format?.parseMode),
      disableWebPreview: request.disableWebPreview ?? rawChannel.format?.disableWebPreview,
      idempotencyKey,
    });
  } catch (error) {
    return failedResult(
      "degraded",
      channelId,
      "network_unavailable",
      sanitizeMessage(errorMessage(error), token),
      {
        accountId: account.id,
        target: redactTelegramTarget(rawChannel.target),
      },
    );
  }

  if (!telegramResult.ok) {
    return failedResult(
      DEGRADABLE_TELEGRAM_CODES.has(telegramResult.code) ? "degraded" : "failed",
      channelId,
      telegramResult.code,
      telegramResult.message,
      {
        accountId: account.id,
        target: redactTelegramTarget(rawChannel.target),
        retryAfterMs: telegramResult.retryAfterMs,
      },
    );
  }

  return {
    status: "success",
    fallback_attempted: false,
    channelId,
    accountId: account.id,
    target: redactTelegramTarget(rawChannel.target),
    delivery: {
      telegramMessageId: telegramResult.telegramMessageId,
      sentAt: telegramResult.sentAt,
      idempotencyKey,
    },
    error: null,
  };
}

function normalizeParseMode(parseMode: PushMessageRequest["parseMode"]): TelegramSendInput["parseMode"] {
  return parseMode === "plain" ? undefined : parseMode;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function sanitizeMessage(message: string, token: string): string {
  return message.split(token).join("[redacted-token]");
}

function failedResult(
  status: Exclude<PushSendStatus, "success" | "partial">,
  channelId: string,
  code: string,
  message: string,
  context: {
    accountId?: string;
    target?: {
      kind: TelegramPushTargetKind;
      redacted: string;
    };
    retryAfterMs?: number;
  } = {},
): PushSendResult {
  return {
    status,
    fallback_attempted: false,
    channelId,
    accountId: context.accountId,
    target: context.target,
    error: {
      code,
      message,
      retryAfterMs: context.retryAfterMs,
    },
  };
}
