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
import {
  authorizeTelegramGatewayEnvelope,
  buildGeeDirectRuntimeInput,
  normalizeTelegramGatewayUpdate,
  telegramGatewayUpdateId,
  type RuntimeChannelMessageInput,
  type TelegramGatewayUpdate,
} from "./gateway.js";
import {
  sendTelegramTextProjection,
} from "./outbound.js";

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

type RuntimeSnapshotLike = {
  last_run_state?: Record<string, unknown>;
  active_conversation?: {
    messages?: Array<{
      role?: unknown;
      content?: unknown;
    }>;
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
  update: TelegramGatewayUpdate,
  dependencies: TelegramBridgeServiceDependencies,
): Promise<TelegramBridgeUpdateResult> {
  const account = config.accounts.find((candidate) => candidate.id === accountId);
  const updateId = telegramGatewayUpdateId(update);
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

  const normalized = normalizeTelegramGatewayUpdate(account, update);
  if (normalized.status !== "success") {
    return serviceFailure("dropped", accountId, normalized.updateId, normalized.error.code, normalized.error.message);
  }

  const envelope = normalized.envelope;
  const security = authorizeTelegramGatewayEnvelope(account, envelope);
  if (security.status !== "allowed") {
    return serviceFailure("dropped", accountId, envelope.updateId, security.code, security.message);
  }

  if (account.role === "codex_remote") {
    return handleCodexRemoteText(
      account,
      envelope.message.text,
      {
        chatId: envelope.chat.id,
        updateId: envelope.updateId,
      },
      dependencies,
    );
  }

  const runtimeInput = buildGeeDirectRuntimeInput(envelope, security);

  let snapshot: RuntimeSnapshotLike;
  try {
    snapshot = await dependencies.runtimeClient.submitChannelMessage(runtimeInput);
  } catch (error) {
    return serviceFailure("failed", accountId, envelope.updateId, "runtime_submit_failed", errorMessage(error));
  }
  if (snapshot.last_run_state?.duplicate_channel_message === true) {
    return serviceFailure(
      "dropped",
      accountId,
      envelope.updateId,
      "duplicate_channel_message",
      "Gee runtime already accepted this Telegram update idempotency key.",
    );
  }

  const reply = latestAssistantReply(snapshot);
  if (!reply) {
    return serviceFailure(
      "degraded",
      accountId,
      envelope.updateId,
      "runtime_reply_missing",
      "Gee runtime accepted the Telegram message but did not produce a reply projection.",
    );
  }

  return sendTelegramServiceReply(account, envelope.chat.id, envelope.updateId, reply, dependencies);
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
  return sendTelegramTextProjection({
    account,
    chatId,
    updateId,
    message,
    idempotencyKey: `telegram:reply:${updateId}`,
  }, dependencies);
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

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export type { TelegramSendClient };
