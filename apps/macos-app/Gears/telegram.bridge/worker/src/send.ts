import {
  redactTelegramTarget,
  resolvePushChannel,
  type TelegramBridgeConfig,
  type TelegramPushTarget,
  type TelegramPushTargetKind,
} from "./config.js";
import { constants } from "node:fs";
import { access, stat } from "node:fs/promises";
import { basename, isAbsolute, resolve } from "node:path";
import { homedir } from "node:os";

export type PushMessageRequest = {
  channelId: string;
  message: string;
  idempotencyKey: string;
  title?: string;
  parseMode?: "Markdown" | "MarkdownV2" | "HTML" | "plain";
  disableWebPreview?: boolean;
  artifactRefs?: string[];
};

export type PushFileRequest = {
  channelId: string;
  filePath: string;
  idempotencyKey: string;
  caption?: string;
  title?: string;
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

export type TelegramLocalFileInput = {
  token: string;
  target: TelegramPushTarget;
  filePath: string;
  caption?: string;
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

export type TelegramFileSendClient = {
  sendLocalFile(input: TelegramLocalFileInput): Promise<TelegramSendResult>;
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
  file?: {
    path: string;
    name: string;
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

export async function sendPushFile(
  config: TelegramBridgeConfig,
  request: PushFileRequest,
  dependencies: PushSendDependencies,
): Promise<PushSendResult> {
  const channelId = request.channelId.trim();
  if (!channelId) {
    return failedResult("failed", "", "channel_id_missing", "`channelId` is required.");
  }
  const rawFilePath = request.filePath.trim();
  if (!rawFilePath) {
    return failedResult("failed", channelId, "file_path_missing", "`filePath` is required.");
  }
  const localFile = await readableLocalFile(rawFilePath);
  if (!localFile.ok) {
    return failedResult("failed", channelId, localFile.code, localFile.message, {
      file: localFile.file,
    });
  }
  const idempotencyKey = request.idempotencyKey.trim();
  if (!idempotencyKey) {
    return failedResult("blocked", channelId, "idempotency_key_missing", "`idempotencyKey` is required.", {
      file: localFile.file,
    });
  }

  const resolved = resolvePushChannel(config, channelId);
  if (resolved.status !== "success") {
    return failedResult("failed", channelId, resolved.error.code, resolved.error.message, {
      file: localFile.file,
    });
  }

  const rawChannel = config.pushChannels?.find((candidate) => candidate.id === channelId);
  const account = config.accounts.find((candidate) => candidate.id === resolved.channel.accountId);
  if (!rawChannel || !account) {
    return failedResult("failed", channelId, "channel_resolution_failed", "Push-only channel resolution lost its account binding.", {
      file: localFile.file,
    });
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
        file: localFile.file,
      },
    );
  }
  if (!token) {
    return failedResult("failed", channelId, "token_missing", `Telegram bot token is missing for account \`${account.id}\`.`, {
      accountId: account.id,
      target: redactTelegramTarget(rawChannel.target),
      file: localFile.file,
    });
  }

  if (!canSendLocalFile(dependencies.telegramClient)) {
    return failedResult(
      "failed",
      channelId,
      "telegram_file_send_unavailable",
      "The configured Telegram client does not support local file uploads.",
      {
        accountId: account.id,
        target: redactTelegramTarget(rawChannel.target),
        file: localFile.file,
      },
    );
  }

  let telegramResult: TelegramSendResult;
  try {
    telegramResult = await dependencies.telegramClient.sendLocalFile({
      token,
      target: rawChannel.target,
      filePath: localFile.file.path,
      caption: request.caption,
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
        file: localFile.file,
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
        file: localFile.file,
      },
    );
  }

  return {
    status: "success",
    fallback_attempted: false,
    channelId,
    accountId: account.id,
    target: redactTelegramTarget(rawChannel.target),
    file: localFile.file,
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
    file?: {
      path: string;
      name: string;
    };
  } = {},
): PushSendResult {
  return {
    status,
    fallback_attempted: false,
    channelId,
    accountId: context.accountId,
    target: context.target,
    file: context.file,
    error: {
      code,
      message,
      retryAfterMs: context.retryAfterMs,
    },
  };
}

function canSendLocalFile(client: TelegramSendClient): client is TelegramSendClient & TelegramFileSendClient {
  return typeof (client as Partial<TelegramFileSendClient>).sendLocalFile === "function";
}

async function readableLocalFile(rawPath: string): Promise<
  | {
      ok: true;
      file: {
        path: string;
        name: string;
      };
    }
  | {
      ok: false;
      code: string;
      message: string;
      file: {
        path: string;
        name: string;
      };
    }
> {
  const path = localFilePath(rawPath);
  const file = {
    path,
    name: basename(path),
  };
  try {
    const info = await stat(path);
    if (!info.isFile()) {
      return {
        ok: false,
        code: "file_not_found",
        message: `Local file \`${path}\` was not found.`,
        file,
      };
    }
    await access(path, constants.R_OK);
    return { ok: true, file };
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    return {
      ok: false,
      code: code === "ENOENT" ? "file_not_found" : "file_not_readable",
      message:
        code === "ENOENT"
          ? `Local file \`${path}\` was not found.`
          : `Local file \`${path}\` is not readable by GeeAgent.`,
      file,
    };
  }
}

function localFilePath(rawPath: string): string {
  const trimmed = rawPath.trim();
  if (trimmed.startsWith("~/")) {
    return resolve(homedir(), trimmed.slice(2));
  }
  return isAbsolute(trimmed) ? resolve(trimmed) : resolve(process.cwd(), trimmed);
}
