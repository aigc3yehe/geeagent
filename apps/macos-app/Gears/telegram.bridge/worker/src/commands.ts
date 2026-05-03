import {
  redactTelegramTarget,
  validateBridgeConfig,
  type TelegramBridgeConfig,
} from "./config.js";
import {
  upsertPushChannel,
  type UpsertPushChannelResult,
} from "./channels.js";
import {
  sendPushMessage,
  type PushSendDependencies,
  type PushSendResult,
  type PushSendStatus,
} from "./send.js";

export type TelegramBridgeWorkerCommand = {
  capability_id?: unknown;
  config?: unknown;
  args?: unknown;
};

export type TelegramBridgeWorkerResult =
  | {
      status: "success";
      fallback_attempted: false;
      capability_id: string;
      result: PushSendResult | PushChannelListResult | UpsertPushChannelResult;
      error: null;
    }
  | {
      status: "blocked" | "degraded" | "failed";
      fallback_attempted: false;
      capability_id: string;
      result?: PushSendResult | UpsertPushChannelResult;
      error: {
        code: string;
        message: string;
        issue_codes?: string[];
        retryAfterMs?: number;
      };
    };

export type PushChannelListResult = {
  status: "success";
  fallback_attempted: false;
  channels: Array<{
    id: string;
    title?: string;
    accountId: string;
    enabled: boolean;
    target: {
      kind: string;
      redacted: string;
    };
  }>;
};

export async function handleTelegramBridgeCommand(
  command: TelegramBridgeWorkerCommand,
  dependencies: PushSendDependencies,
): Promise<TelegramBridgeWorkerResult> {
  const capabilityID = stringValue(command.capability_id) ?? "";
  if (!capabilityID) {
    return commandFailure("", "capability_id_missing", "`capability_id` is required.");
  }
  if (!isSupportedCapability(capabilityID)) {
    return commandFailure(
      capabilityID,
      "capability_unsupported",
      `Telegram Bridge worker does not support capability \`${capabilityID}\` yet.`,
    );
  }

  const validation = validateBridgeConfig(command.config);
  if (!validation.ok) {
    return commandFailure(capabilityID, "config_invalid", "Telegram Bridge config is invalid.", {
      issue_codes: validation.issues.map((issue) => issue.code),
    });
  }

  switch (capabilityID) {
    case "telegram_push.list_channels":
      return {
        status: "success",
        fallback_attempted: false,
        capability_id: capabilityID,
        result: listPushChannels(validation.config, command.args),
        error: null,
      };
    case "telegram_push.upsert_channel":
      return upsertCommandResult(
        capabilityID,
        upsertPushChannel(validation.config, upsertRequestFromArgs(command.args)),
      );
    case "telegram_push.send_message":
      return sendCommandResult(
        capabilityID,
        await sendPushMessage(validation.config, sendRequestFromArgs(command.args), dependencies),
      );
  }
  return commandFailure(
    capabilityID,
    "capability_unsupported",
    `Telegram Bridge worker does not support capability \`${capabilityID}\` yet.`,
  );
}

function isSupportedCapability(capabilityID: string): boolean {
  return [
    "telegram_push.list_channels",
    "telegram_push.upsert_channel",
    "telegram_push.send_message",
  ].includes(capabilityID);
}

function sendCommandResult(capabilityID: string, result: PushSendResult): TelegramBridgeWorkerResult {
  if (result.status === "success") {
    return {
      status: "success",
      fallback_attempted: false,
      capability_id: capabilityID,
      result,
      error: null,
    };
  }
  return {
    status: commandStatusFromPush(result.status),
    fallback_attempted: false,
    capability_id: capabilityID,
    result,
    error: {
      code: result.error?.code ?? "telegram_push_failed",
      message: result.error?.message ?? "Telegram push send did not complete successfully.",
      retryAfterMs: result.error?.retryAfterMs,
    },
  };
}

function upsertCommandResult(capabilityID: string, result: UpsertPushChannelResult): TelegramBridgeWorkerResult {
  if (result.status === "success") {
    return {
      status: "success",
      fallback_attempted: false,
      capability_id: capabilityID,
      result,
      error: null,
    };
  }
  return {
    status: "failed",
    fallback_attempted: false,
    capability_id: capabilityID,
    result,
    error: {
      code: result.error.code,
      message: result.error.message,
    },
  };
}

function commandStatusFromPush(status: PushSendStatus): "blocked" | "degraded" | "failed" {
  switch (status) {
    case "blocked":
    case "degraded":
    case "failed":
      return status;
    case "partial":
      return "degraded";
    case "success":
      return "failed";
  }
}

function listPushChannels(config: TelegramBridgeConfig, args: unknown): PushChannelListResult {
  const enabledOnly = isRecord(args) && args.enabled_only === true;
  return {
    status: "success",
    fallback_attempted: false,
    channels: (config.pushChannels ?? [])
      .filter((channel) => !enabledOnly || channel.enabled)
      .map((channel) => ({
        id: channel.id,
        title: channel.title,
        accountId: channel.accountId,
        enabled: channel.enabled,
        target: redactTelegramTarget(channel.target),
      })),
  };
}

function sendRequestFromArgs(args: unknown): {
  channelId: string;
  message: string;
  idempotencyKey: string;
  title?: string;
  parseMode?: "Markdown" | "MarkdownV2" | "HTML" | "plain";
  disableWebPreview?: boolean;
  artifactRefs?: string[];
} {
  const record = isRecord(args) ? args : {};
  return {
    channelId: stringValue(record.channel_id) ?? stringValue(record.channelId) ?? "",
    message: rawStringValue(record.message) ?? "",
    idempotencyKey: stringValue(record.idempotency_key) ?? stringValue(record.idempotencyKey) ?? "",
    title: stringValue(record.title),
    parseMode: parseModeValue(record.parse_mode ?? record.parseMode),
    disableWebPreview: booleanValue(record.disable_web_preview ?? record.disableWebPreview),
    artifactRefs: stringArrayValue(record.artifact_refs ?? record.artifactRefs),
  };
}

function upsertRequestFromArgs(args: unknown): {
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
} {
  const record = isRecord(args) ? args : {};
  return {
    channelId: stringValue(record.channel_id) ?? stringValue(record.channelId) ?? "",
    accountId: stringValue(record.account_id) ?? stringValue(record.accountId) ?? "",
    title: stringValue(record.title),
    botUsername: stringValue(record.bot_username) ?? stringValue(record.botUsername),
    enabled: booleanValue(record.enabled),
    target: {
      kind: pushTargetKindValue(record.target_kind ?? record.targetKind),
      value: stringValue(record.target_value) ?? stringValue(record.targetValue) ?? "",
    },
    parseMode: parseModeValue(record.parse_mode ?? record.parseMode),
    disableWebPreview: booleanValue(record.disable_web_preview ?? record.disableWebPreview),
  };
}

function commandFailure(
  capabilityID: string,
  code: string,
  message: string,
  extra: { issue_codes?: string[] } = {},
): TelegramBridgeWorkerResult {
  return {
    status: "failed",
    fallback_attempted: false,
    capability_id: capabilityID,
    error: {
      code,
      message,
      ...extra,
    },
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function rawStringValue(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

function booleanValue(value: unknown): boolean | undefined {
  return typeof value === "boolean" ? value : undefined;
}

function stringArrayValue(value: unknown): string[] | undefined {
  if (!Array.isArray(value)) {
    return undefined;
  }
  const strings = value.filter((item): item is string => typeof item === "string" && item.trim().length > 0);
  return strings.length > 0 ? strings : undefined;
}

function parseModeValue(value: unknown): "Markdown" | "MarkdownV2" | "HTML" | "plain" | undefined {
  switch (value) {
    case "Markdown":
    case "MarkdownV2":
    case "HTML":
    case "plain":
      return value;
    default:
      return undefined;
  }
}

function pushTargetKindValue(value: unknown): string {
  return typeof value === "string" ? value : "";
}
