import type {
  TelegramBridgeAccount,
  TelegramBridgeConfig,
} from "./config.js";
import {
  redactTelegramTarget,
} from "./config.js";
import type {
  PushSendDependencies,
  TelegramSendClient,
} from "./send.js";

export type RuntimeChannelClient = {
  submitChannelMessage(input: RuntimeChannelMessageInput): Promise<RuntimeSnapshotLike>;
};

export type TelegramBridgeServiceDependencies = PushSendDependencies & {
  runtimeClient: RuntimeChannelClient;
  codexClient?: CodexRemoteClient;
};

export type CodexRemoteClient = {
  listThreads(input: {
    source: "file_scan" | "app_server";
    limit?: number;
  }): Promise<CodexThreadListResult>;
  sendPrompt(input: {
    mode: "cli_resume" | "app_server";
    sessionId: string;
    prompt: string;
  }): Promise<CodexSendResult>;
  cliResumeSend?(input: { sessionId: string; prompt: string }): Promise<CodexSendResult>;
};

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
    attachments: unknown[];
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

type RuntimeSnapshotLike = {
  last_run_state?: Record<string, unknown>;
  active_conversation?: {
    messages?: Array<{
      role?: unknown;
      content?: unknown;
    }>;
  };
};

export type TelegramUpdate = {
  update_id?: unknown;
  message?: {
    message_id?: unknown;
    chat?: {
      id?: unknown;
      type?: unknown;
    };
    from?: {
      id?: unknown;
    };
    text?: unknown;
  };
};

type CodexThreadListResult = {
  status: "success" | "degraded" | "failed";
  fallback_attempted: false;
  source: "file_scan" | "app_server";
  threads: Array<{
    id: string;
    title: string;
    cwd?: string;
    updatedAt?: string | null;
  }>;
  error: null | {
    code: string;
    message: string;
  };
};

type CodexSendResult = {
  status: "success" | "partial" | "empty_result" | "blocked" | "degraded" | "failed";
  fallback_attempted: false;
  source: "cli_resume" | "app_server";
  target: {
    sessionId: string;
  };
  result: null | {
    lastMessage?: string;
  };
  error: null | {
    code: string;
    message: string;
  };
};

export type TelegramBridgeUpdateResult = {
  status: "success" | "dropped" | "blocked" | "degraded" | "failed";
  fallback_attempted: false;
  accountId: string;
  updateId?: number;
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

export function pollingAccountIds(config: TelegramBridgeConfig): string[] {
  return config.accounts
    .filter((account) => account.transport.mode === "polling" && account.role !== "push_only")
    .map((account) => account.id);
}

export async function handleTelegramBridgeUpdate(
  config: TelegramBridgeConfig,
  accountId: string,
  update: TelegramUpdate,
  dependencies: TelegramBridgeServiceDependencies,
): Promise<TelegramBridgeUpdateResult> {
  const account = config.accounts.find((candidate) => candidate.id === accountId);
  const updateId = numberValue(update.update_id);
  if (!account) {
    return serviceFailure("failed", accountId, updateId, "account_not_found", `Telegram account \`${accountId}\` was not found.`);
  }
  if (account.role === "push_only") {
    return serviceFailure(
      "dropped",
      accountId,
      updateId,
      "push_only_inbound_disabled",
      `Push-only account \`${accountId}\` does not accept Telegram inbound updates.`,
    );
  }
  const message = update.message;
  const text = stringValue(message?.text);
  if (!message || !text) {
    return serviceFailure("dropped", accountId, updateId, "message_not_text", "Telegram update did not contain a text message.");
  }
  const chatId = idValue(message.chat?.id);
  const messageId = idValue(message.message_id);
  const fromUserId = idValue(message.from?.id);
  if (!chatId || !messageId || !fromUserId || updateId === undefined) {
    return serviceFailure("dropped", accountId, updateId, "message_identity_missing", "Telegram update is missing stable identity fields.");
  }

  const security = securityDecision(account, chatId, fromUserId, stringValue(message.chat?.type), text);
  if (security.status !== "allowed") {
    return serviceFailure("dropped", accountId, updateId, security.code, security.message);
  }

  if (account.role === "codex_remote") {
    return handleCodexRemoteText(
      account,
      text,
      {
        chatId,
        updateId,
      },
      dependencies,
    );
  }

  const runtimeInput: RuntimeChannelMessageInput = {
    source: "telegram.bridge",
    role: "gee_direct",
    channelIdentity: `telegram:${account.id}:bot:unknown:dm:${chatId}`,
    message: {
      idempotencyKey: `telegram:update:${updateId}`,
      telegramUpdateId: updateId,
      chatId,
      messageId,
      fromUserId,
      text,
      attachments: [],
    },
    security: {
      decision: "allowed",
      policyId: security.policyId,
    },
    projection: {
      surface: "telegram",
      replyTarget: {
        chatId,
        messageId,
      },
    },
  };

  let snapshot: RuntimeSnapshotLike;
  try {
    snapshot = await dependencies.runtimeClient.submitChannelMessage(runtimeInput);
  } catch (error) {
    return serviceFailure("failed", accountId, updateId, "runtime_submit_failed", errorMessage(error));
  }
  if (snapshot.last_run_state?.duplicate_channel_message === true) {
    return serviceFailure(
      "dropped",
      accountId,
      updateId,
      "duplicate_channel_message",
      "Gee runtime already accepted this Telegram update idempotency key.",
    );
  }

  const reply = latestAssistantReply(snapshot);
  if (!reply) {
    return serviceFailure(
      "degraded",
      accountId,
      updateId,
      "runtime_reply_missing",
      "Gee runtime accepted the Telegram message but did not produce a reply projection.",
    );
  }

  const token = await dependencies.tokenProvider(account.id);
  if (!token?.trim()) {
    return serviceFailure("failed", accountId, updateId, "token_missing", `Telegram bot token is missing for account \`${account.id}\`.`);
  }

  const sendResult = await dependencies.telegramClient.sendMessage({
    token: token.trim(),
    target: { kind: "chat_id", value: chatId },
    message: reply,
    disableWebPreview: true,
    idempotencyKey: `telegram:reply:${updateId}`,
  });
  if (!sendResult.ok) {
    return serviceFailure(
      sendResult.code === "telegram_rate_limited" || sendResult.code === "network_unavailable" ? "degraded" : "failed",
      accountId,
      updateId,
      sendResult.code,
      sendResult.message,
      sendResult.retryAfterMs,
    );
  }

  return {
    status: "success",
    fallback_attempted: false,
    accountId,
    updateId,
    delivery: {
      telegramMessageId: sendResult.telegramMessageId,
      sentAt: sendResult.sentAt,
    },
    error: null,
  };
}

async function handleCodexRemoteText(
  account: TelegramBridgeAccount,
  text: string,
  context: {
    chatId: string;
    updateId: number;
  },
  dependencies: TelegramBridgeServiceDependencies,
): Promise<TelegramBridgeUpdateResult> {
  if (!dependencies.codexClient) {
    return serviceFailure("failed", account.id, context.updateId, "codex_client_missing", "Codex remote client is not configured.");
  }
  const [command, ...parts] = text.trim().split(/\s+/);
  if (command === "/list" || command === "/recent") {
    const source = account.codex?.threadSource ?? "file_scan";
    const list = await dependencies.codexClient.listThreads({ source });
    const send = await sendTelegramServiceReply(
      account,
      context.chatId,
      context.updateId,
      codexListText(list),
      dependencies,
    );
    if (send.status !== "success") {
      return send;
    }
    return list.error
      ? serviceFailure(list.status === "degraded" ? "degraded" : "failed", account.id, context.updateId, list.error.code, list.error.message)
      : {
          status: "success",
          fallback_attempted: false,
          accountId: account.id,
          updateId: context.updateId,
          delivery: send.delivery,
          error: null,
        };
  }
  if (command === "/send") {
    const sessionId = parts.shift()?.trim() ?? "";
    const prompt = parts.join(" ").trim();
    if (!sessionId || !prompt) {
      return serviceFailure("blocked", account.id, context.updateId, "codex_send_args_missing", "`/send` requires a session id and prompt.");
    }
    const mode = account.codex?.sendMode ?? "cli_resume";
    const result = await dependencies.codexClient.sendPrompt({ mode, sessionId, prompt });
    const send = await sendTelegramServiceReply(
      account,
      context.chatId,
      context.updateId,
      codexSendText(result),
      dependencies,
    );
    if (send.status !== "success") {
      return send;
    }
    if (result.error) {
      return serviceFailure(codexStatusToServiceStatus(result.status), account.id, context.updateId, result.error.code, result.error.message);
    }
    return {
      status: "success",
      fallback_attempted: false,
      accountId: account.id,
      updateId: context.updateId,
      delivery: send.delivery,
      error: null,
    };
  }
  return serviceFailure("blocked", account.id, context.updateId, "codex_command_unsupported", "Use /list or /send <session_id> <prompt>.");
}

async function sendTelegramServiceReply(
  account: TelegramBridgeAccount,
  chatId: string,
  updateId: number,
  message: string,
  dependencies: Pick<TelegramBridgeServiceDependencies, "tokenProvider" | "telegramClient">,
): Promise<TelegramBridgeUpdateResult> {
  const token = await dependencies.tokenProvider(account.id);
  if (!token?.trim()) {
    return serviceFailure("failed", account.id, updateId, "token_missing", `Telegram bot token is missing for account \`${account.id}\`.`);
  }
  const result = await dependencies.telegramClient.sendMessage({
    token: token.trim(),
    target: { kind: "chat_id", value: chatId },
    message,
    disableWebPreview: true,
    idempotencyKey: `telegram:reply:${updateId}`,
  });
  if (!result.ok) {
    return serviceFailure(
      result.code === "telegram_rate_limited" || result.code === "network_unavailable" ? "degraded" : "failed",
      account.id,
      updateId,
      result.code,
      result.message,
      result.retryAfterMs,
    );
  }
  return {
    status: "success",
    fallback_attempted: false,
    accountId: account.id,
    updateId,
    delivery: {
      telegramMessageId: result.telegramMessageId,
      sentAt: result.sentAt,
    },
    error: null,
  };
}

function codexListText(result: CodexThreadListResult): string {
  if (result.error) {
    return `Codex thread list failed: ${result.error.message}`;
  }
  if (result.threads.length === 0) {
    return "No Codex threads found.";
  }
  return [
    `Codex threads (${result.source}):`,
    ...result.threads.slice(0, 10).map((thread, index) =>
      `${index + 1}. ${thread.title} (${thread.id})${thread.cwd ? `\n   ${thread.cwd}` : ""}`,
    ),
  ].join("\n");
}

function codexSendText(result: CodexSendResult): string {
  if (result.error) {
    return `Codex send failed: ${result.error.message}`;
  }
  const reply = result.result?.lastMessage?.trim();
  return reply ? `Codex replied:\n${reply}` : "Codex accepted the prompt.";
}

function codexStatusToServiceStatus(status: CodexSendResult["status"]): Exclude<TelegramBridgeUpdateResult["status"], "success" | "dropped"> {
  switch (status) {
    case "blocked":
      return "blocked";
    case "degraded":
    case "partial":
    case "empty_result":
      return "degraded";
    case "failed":
      return "failed";
    case "success":
      return "failed";
  }
}

function securityDecision(
  account: TelegramBridgeAccount,
  chatId: string,
  fromUserId: string,
  chatType: string | undefined,
  text: string,
):
  | { status: "allowed"; policyId: string }
  | { status: "denied"; code: string; message: string } {
  if (account.security?.requirePairing === true) {
    return {
      status: "denied",
      code: "pairing_required_unavailable",
      message: "Telegram pairing is required for this account, but pairing is not implemented in this Gear release.",
    };
  }
  if (chatType && chatType !== "private") {
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
      if (!hasBotMention(text, account.botUsername)) {
        return {
          status: "denied",
          code: "group_policy_mention_required",
          message: "Telegram group messages must mention this bot before GeeAgent accepts them.",
        };
      }
    }
  }
  const allowedUsers = normalizedIdSet(account.security?.allowUserIds);
  if (allowedUsers.size > 0 && !allowedUsers.has(fromUserId)) {
    return {
      status: "denied",
      code: "user_not_allowed",
      message: "Telegram user is not authorized for this account.",
    };
  }
  const allowedChats = normalizedIdSet(account.security?.allowChatIds);
  if (allowedChats.size > 0 && !allowedChats.has(chatId)) {
    return {
      status: "denied",
      code: "chat_not_allowed",
      message: "Telegram chat is not authorized for this account.",
    };
  }
  return { status: "allowed", policyId: "allowlist" };
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

function latestAssistantReply(snapshot: RuntimeSnapshotLike): string | null {
  const messages = snapshot.active_conversation?.messages ?? [];
  for (let index = messages.length - 1; index >= 0; index -= 1) {
    const message = messages[index];
    if (message?.role === "assistant" && typeof message.content === "string" && message.content.trim()) {
      return message.content.trim();
    }
  }
  return null;
}

function serviceFailure(
  status: Exclude<TelegramBridgeUpdateResult["status"], "success">,
  accountId: string,
  updateId: number | undefined,
  code: string,
  message: string,
  retryAfterMs?: number,
): TelegramBridgeUpdateResult {
  return {
    status,
    fallback_attempted: false,
    accountId,
    updateId,
    error: {
      code,
      message,
      retryAfterMs,
    },
  };
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

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export type { TelegramSendClient };
