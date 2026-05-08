import type { TelegramBridgeAccount } from "./config.js";
import type {
  TelegramSendClient,
} from "./send.js";

export type TelegramOutboundTextDependencies = {
  tokenProvider(accountId: string): Promise<string | undefined>;
  telegramClient: TelegramSendClient;
};

export type TelegramOutboundTextProjection = {
  account: TelegramBridgeAccount;
  chatId: string;
  updateId: number;
  message: string;
  idempotencyKey: string;
  disableWebPreview?: boolean;
};

export type TelegramOutboundTextResult = {
  status: "success" | "degraded" | "failed";
  fallback_attempted: false;
  accountId: string;
  updateId: number;
  delivery?: {
    telegramMessageId: string;
    sentAt: string;
  };
  error: null | {
    code: string;
    message: string;
    retryAfterMs?: number;
  };
};

export async function sendTelegramTextProjection(
  projection: TelegramOutboundTextProjection,
  dependencies: TelegramOutboundTextDependencies,
): Promise<TelegramOutboundTextResult> {
  const token = await dependencies.tokenProvider(projection.account.id);
  if (!token?.trim()) {
    return textProjectionFailure(
      "failed",
      projection,
      "token_missing",
      `Telegram bot token is missing for account \`${projection.account.id}\`.`,
    );
  }

  const result = await dependencies.telegramClient.sendMessage({
    token: token.trim(),
    target: { kind: "chat_id", value: projection.chatId },
    message: projection.message,
    disableWebPreview: projection.disableWebPreview ?? true,
    idempotencyKey: projection.idempotencyKey,
  });
  if (!result.ok) {
    return textProjectionFailure(
      result.code === "telegram_rate_limited" || result.code === "network_unavailable" ? "degraded" : "failed",
      projection,
      result.code,
      result.message,
      result.retryAfterMs,
    );
  }

  return {
    status: "success",
    fallback_attempted: false,
    accountId: projection.account.id,
    updateId: projection.updateId,
    delivery: {
      telegramMessageId: result.telegramMessageId,
      sentAt: result.sentAt,
    },
    error: null,
  };
}

function textProjectionFailure(
  status: Exclude<TelegramOutboundTextResult["status"], "success">,
  projection: TelegramOutboundTextProjection,
  code: string,
  message: string,
  retryAfterMs?: number,
): TelegramOutboundTextResult {
  return {
    status,
    fallback_attempted: false,
    accountId: projection.account.id,
    updateId: projection.updateId,
    error: {
      code,
      message,
      retryAfterMs,
    },
  };
}
