import type {
  TelegramBridgeConfig,
  TelegramPushTarget,
  TelegramPushTargetKind,
} from "./config.js";

export type UpsertPushChannelInput = {
  channelId: string;
  accountId: string;
  target: {
    kind: string;
    value: string;
  };
  title?: string;
  botUsername?: string;
  enabled?: boolean;
  parseMode?: "Markdown" | "MarkdownV2" | "HTML" | "plain";
  disableWebPreview?: boolean;
};

export type UpsertPushChannelResult =
  | {
      status: "success";
      fallback_attempted: false;
      channelId: string;
      accountId: string;
      config: TelegramBridgeConfig;
      error: null;
    }
  | {
      status: "failed";
      fallback_attempted: false;
      channelId: string;
      accountId?: string;
      config: TelegramBridgeConfig;
      error: {
        code: string;
        message: string;
      };
    };

export function upsertPushChannel(
  config: TelegramBridgeConfig,
  input: UpsertPushChannelInput,
): UpsertPushChannelResult {
  const channelId = input.channelId.trim();
  const accountId = input.accountId.trim();
  if (!channelId) {
    return failure(config, channelId, accountId, "channel_id_missing", "`channelId` is required.");
  }
  if (!accountId) {
    return failure(config, channelId, accountId, "account_id_missing", "`accountId` is required.");
  }
  if (!input.target.value.trim()) {
    return failure(config, channelId, accountId, "target_value_missing", "`target.value` is required.");
  }
  if (!isPushTargetKind(input.target.kind)) {
    return failure(
      config,
      channelId,
      accountId,
      "target_kind_invalid",
      "`target.kind` must be chat_id, group_id, channel_id, or channel_username.",
    );
  }

  const existingAccount = config.accounts.find((account) => account.id === accountId);
  if (existingAccount && existingAccount.role !== "push_only") {
    return failure(
      config,
      channelId,
      accountId,
      "account_not_push_only",
      `Account \`${accountId}\` is \`${existingAccount.role}\`; push channels require a push_only account.`,
    );
  }
  if (existingAccount && existingAccount.transport.mode !== "outbound_only") {
    return failure(
      config,
      channelId,
      accountId,
      "push_only.transport_not_outbound_only",
      `Push-only account \`${accountId}\` must use outbound_only transport.`,
    );
  }

  const next: TelegramBridgeConfig = {
    version: 1,
    accounts: config.accounts.map((account) => ({ ...account })),
    pushChannels: (config.pushChannels ?? []).map((channel) => ({ ...channel })),
  };

  if (!existingAccount) {
    next.accounts.push({
      id: accountId,
      role: "push_only",
      botUsername: optionalString(input.botUsername),
      transport: {
        mode: "outbound_only",
      },
      push: {
        acceptInbound: false,
      },
    });
  } else {
    const index = next.accounts.findIndex((account) => account.id === accountId);
    next.accounts[index] = {
      ...next.accounts[index],
      botUsername: optionalString(input.botUsername) ?? next.accounts[index].botUsername,
      push: {
        acceptInbound: false,
      },
    };
  }

  const channel = {
    id: channelId,
    title: optionalString(input.title),
    accountId,
    enabled: input.enabled ?? true,
      target: {
        kind: input.target.kind,
        value: input.target.value.trim(),
      },
    format:
      input.parseMode || typeof input.disableWebPreview === "boolean"
        ? {
            parseMode: input.parseMode,
            disableWebPreview: input.disableWebPreview,
          }
        : undefined,
  };
  const channelIndex = (next.pushChannels ?? []).findIndex((item) => item.id === channelId);
  if (channelIndex >= 0) {
    next.pushChannels![channelIndex] = {
      ...next.pushChannels![channelIndex],
      ...channel,
    };
  } else {
    next.pushChannels = [...(next.pushChannels ?? []), channel];
  }

  return {
    status: "success",
    fallback_attempted: false,
    channelId,
    accountId,
    config: next,
    error: null,
  };
}

const PUSH_TARGET_KINDS = new Set<string>([
  "chat_id",
  "group_id",
  "channel_id",
  "channel_username",
]);

function isPushTargetKind(value: string): value is TelegramPushTargetKind {
  return PUSH_TARGET_KINDS.has(value);
}

function failure(
  config: TelegramBridgeConfig,
  channelId: string,
  accountId: string,
  code: string,
  message: string,
): UpsertPushChannelResult {
  return {
    status: "failed",
    fallback_attempted: false,
    channelId,
    accountId: accountId || undefined,
    config,
    error: {
      code,
      message,
    },
  };
}

function optionalString(value: string | undefined): string | undefined {
  return value?.trim() || undefined;
}
