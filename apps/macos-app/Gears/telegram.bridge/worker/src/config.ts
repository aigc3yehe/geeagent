export type TelegramBridgeRole = "codex_remote" | "gee_direct" | "push_only";
export type TelegramTransportMode = "polling" | "webhook" | "outbound_only";
export type TelegramPushTargetKind = "chat_id" | "group_id" | "channel_id" | "channel_username";

export type TelegramPushTarget = {
  kind: TelegramPushTargetKind;
  value: string;
};

export type TelegramBridgeAccount = {
  id: string;
  role: TelegramBridgeRole;
  botUsername?: string;
  transport: {
    mode: TelegramTransportMode;
  };
  security?: {
    allowUserIds?: string[];
    allowChatIds?: string[];
    requirePairing?: boolean;
    groupPolicy?: "deny" | "mention_required" | "allow";
  };
  push?: {
    acceptInbound?: boolean;
  };
  codex?: {
    threadSource?: "app_server" | "file_scan";
    sendMode?: "app_server" | "cli_resume";
  };
};

export type TelegramPushChannel = {
  id: string;
  title?: string;
  accountId: string;
  enabled: boolean;
  target: TelegramPushTarget;
  format?: {
    parseMode?: "Markdown" | "MarkdownV2" | "HTML" | "plain";
    disableWebPreview?: boolean;
  };
  policy?: {
    allowScheduledDelivery?: boolean;
    allowCodexExport?: boolean;
    requirePerSendApproval?: boolean;
  };
};

export type TelegramBridgeConfig = {
  version: 1;
  accounts: TelegramBridgeAccount[];
  pushChannels?: TelegramPushChannel[];
};

export type ValidationIssue = {
  path: string;
  code: string;
  message: string;
};

export type BridgeConfigValidationResult =
  | {
      ok: true;
      issues: [];
      config: TelegramBridgeConfig;
    }
  | {
      ok: false;
      issues: ValidationIssue[];
      config?: TelegramBridgeConfig;
    };

export type ResolvedPushChannel =
  | {
      status: "success";
      channel: {
        id: string;
        title?: string;
        accountId: string;
        target: {
          kind: TelegramPushTargetKind;
          redacted: string;
        };
        policy: Required<NonNullable<TelegramPushChannel["policy"]>>;
      };
      error: null;
    }
  | {
      status: "failed";
      channel?: undefined;
      error: {
        code: string;
        message: string;
      };
    };

const ACCOUNT_ROLES = new Set<TelegramBridgeRole>(["codex_remote", "gee_direct", "push_only"]);
const TRANSPORT_MODES = new Set<TelegramTransportMode>(["polling", "webhook", "outbound_only"]);
const GROUP_POLICIES = new Set<NonNullable<NonNullable<TelegramBridgeAccount["security"]>["groupPolicy"]>>([
  "deny",
  "mention_required",
  "allow",
]);
const CODEX_THREAD_SOURCES = new Set<NonNullable<NonNullable<TelegramBridgeAccount["codex"]>["threadSource"]>>([
  "app_server",
  "file_scan",
]);
const CODEX_SEND_MODES = new Set<NonNullable<NonNullable<TelegramBridgeAccount["codex"]>["sendMode"]>>([
  "app_server",
  "cli_resume",
]);
const PUSH_TARGET_KINDS = new Set<TelegramPushTargetKind>([
  "chat_id",
  "group_id",
  "channel_id",
  "channel_username",
]);

const DEFAULT_PUSH_POLICY: Required<NonNullable<TelegramPushChannel["policy"]>> = {
  allowScheduledDelivery: false,
  allowCodexExport: false,
  requirePerSendApproval: true,
};

export function validateBridgeConfig(input: unknown): BridgeConfigValidationResult {
  const issues: ValidationIssue[] = [];
  if (!isRecord(input)) {
    return {
      ok: false,
      issues: [
        {
          path: "$",
          code: "config.not_object",
          message: "Telegram Bridge config must be an object.",
        },
      ],
    };
  }

  const accounts = readArray(input.accounts);
  const pushChannels = input.pushChannels === undefined ? [] : readArray(input.pushChannels);
  const config: TelegramBridgeConfig = {
    version: 1,
    accounts: [],
    pushChannels: [],
  };

  if (input.version !== 1) {
    issues.push({
      path: "$.version",
      code: "config.version_unsupported",
      message: "Telegram Bridge config version must be 1.",
    });
  }

  if (!Array.isArray(input.accounts)) {
    issues.push({
      path: "$.accounts",
      code: "accounts.not_array",
      message: "`accounts` must be an array.",
    });
  }

  accounts.forEach((accountInput, index) => {
    const account = normalizeAccount(accountInput, `$.accounts[${index}]`, issues);
    if (account) {
      config.accounts.push(account);
    }
  });

  if (input.pushChannels !== undefined && !Array.isArray(input.pushChannels)) {
    issues.push({
      path: "$.pushChannels",
      code: "push_channels.not_array",
      message: "`pushChannels` must be an array when provided.",
    });
  }

  pushChannels.forEach((channelInput, index) => {
    const channel = normalizePushChannel(channelInput, `$.pushChannels[${index}]`, issues);
    if (channel) {
      config.pushChannels?.push(channel);
    }
  });

  validatePushChannelAccounts(config, issues);

  return issues.length === 0 ? { ok: true, issues: [], config } : { ok: false, issues, config };
}

export function resolvePushChannel(
  config: TelegramBridgeConfig,
  channelId: string,
): ResolvedPushChannel {
  const channel = (config.pushChannels ?? []).find((candidate) => candidate.id === channelId);
  if (!channel) {
    return failedPushChannel("channel_not_found", `Push-only channel \`${channelId}\` was not found.`);
  }
  if (!channel.enabled) {
    return failedPushChannel("channel_disabled", `Push-only channel \`${channelId}\` is disabled.`);
  }
  const account = config.accounts.find((candidate) => candidate.id === channel.accountId);
  if (!account) {
    return failedPushChannel(
      "account_not_found",
      `Push-only channel \`${channelId}\` references missing account \`${channel.accountId}\`.`,
    );
  }
  if (account.role !== "push_only") {
    return failedPushChannel(
      "account_not_push_only",
      `Push-only channel \`${channelId}\` references non-push account \`${account.id}\`.`,
    );
  }
  if (account.transport.mode !== "outbound_only") {
    return failedPushChannel(
      "push_only.transport_not_outbound_only",
      `Push-only channel \`${channelId}\` references account \`${account.id}\` that is not outbound-only.`,
    );
  }
  if (account.push?.acceptInbound !== false) {
    return failedPushChannel(
      "push_only.accept_inbound_not_allowed",
      `Push-only channel \`${channelId}\` references account \`${account.id}\` that can accept inbound updates.`,
    );
  }

  return {
    status: "success",
    channel: {
      id: channel.id,
      title: channel.title,
      accountId: channel.accountId,
      target: redactTelegramTarget(channel.target),
      policy: {
        ...DEFAULT_PUSH_POLICY,
        ...(channel.policy ?? {}),
      },
    },
    error: null,
  };
}

export function redactTelegramTarget(target: TelegramPushTarget): {
  kind: TelegramPushTargetKind;
  redacted: string;
} {
  return {
    kind: target.kind,
    redacted: redactIdentifier(target.value),
  };
}

function normalizeAccount(
  input: unknown,
  path: string,
  issues: ValidationIssue[],
): TelegramBridgeAccount | null {
  if (!isRecord(input)) {
    issues.push({
      path,
      code: "account.not_object",
      message: "Telegram Bridge account must be an object.",
    });
    return null;
  }

  const id = stringValue(input.id);
  const role = stringValue(input.role);
  const transportMode = isRecord(input.transport) ? stringValue(input.transport.mode) : undefined;
  if (!id) {
    issues.push({ path: `${path}.id`, code: "account.id_missing", message: "Account id is required." });
  }
  if (!role || !ACCOUNT_ROLES.has(role as TelegramBridgeRole)) {
    issues.push({
      path: `${path}.role`,
      code: "account.role_invalid",
      message: "Account role must be codex_remote, gee_direct, or push_only.",
    });
  }
  if (!transportMode || !TRANSPORT_MODES.has(transportMode as TelegramTransportMode)) {
    issues.push({
      path: `${path}.transport.mode`,
      code: "account.transport_mode_invalid",
      message: "Transport mode must be polling, webhook, or outbound_only.",
    });
  }

  if (role === "push_only") {
    if (transportMode !== "outbound_only") {
      issues.push({
        path: `${path}.transport.mode`,
        code: "push_only.transport_not_outbound_only",
        message: "Push-only accounts must use outbound_only transport.",
      });
    }
    const push = isRecord(input.push) ? input.push : {};
    if (push.acceptInbound !== false) {
      issues.push({
        path: `${path}.push.acceptInbound`,
        code: "push_only.accept_inbound_not_allowed",
        message: "Push-only accounts must set acceptInbound to false.",
      });
    }
  }

  if (!id || !role || !transportMode || !ACCOUNT_ROLES.has(role as TelegramBridgeRole)) {
    return null;
  }
  if (!TRANSPORT_MODES.has(transportMode as TelegramTransportMode)) {
    return null;
  }

  const account: TelegramBridgeAccount = {
    id,
    role: role as TelegramBridgeRole,
    botUsername: stringValue(input.botUsername),
    transport: {
      mode: transportMode as TelegramTransportMode,
    },
  };
  if (isRecord(input.security)) {
    account.security = normalizeSecurity(input.security, `${path}.security`, issues);
  }
  if (isRecord(input.push)) {
    account.push = {
      acceptInbound: typeof input.push.acceptInbound === "boolean" ? input.push.acceptInbound : undefined,
    };
  }
  if (isRecord(input.codex)) {
    account.codex = normalizeCodex(input.codex, `${path}.codex`, issues);
  }
  return account;
}

function normalizeSecurity(
  input: Record<string, unknown>,
  path: string,
  issues: ValidationIssue[],
): TelegramBridgeAccount["security"] {
  const security: NonNullable<TelegramBridgeAccount["security"]> = {};
  const allowUserIds = idArrayValue(input.allowUserIds, `${path}.allowUserIds`, issues);
  if (allowUserIds !== undefined) {
    security.allowUserIds = allowUserIds;
  }
  const allowChatIds = idArrayValue(input.allowChatIds, `${path}.allowChatIds`, issues);
  if (allowChatIds !== undefined) {
    security.allowChatIds = allowChatIds;
  }
  if (input.requirePairing !== undefined) {
    if (typeof input.requirePairing === "boolean") {
      security.requirePairing = input.requirePairing;
    } else {
      issues.push({
        path: `${path}.requirePairing`,
        code: "security.require_pairing_invalid",
        message: "security.requirePairing must be a boolean when provided.",
      });
    }
  }
  if (input.groupPolicy !== undefined) {
    const groupPolicy = stringValue(input.groupPolicy);
    if (groupPolicy && GROUP_POLICIES.has(groupPolicy as NonNullable<typeof security.groupPolicy>)) {
      security.groupPolicy = groupPolicy as NonNullable<typeof security.groupPolicy>;
    } else {
      issues.push({
        path: `${path}.groupPolicy`,
        code: "security.group_policy_invalid",
        message: "security.groupPolicy must be deny, mention_required, or allow.",
      });
    }
  }
  return security;
}

function normalizeCodex(
  input: Record<string, unknown>,
  path: string,
  issues: ValidationIssue[],
): TelegramBridgeAccount["codex"] {
  const codex: NonNullable<TelegramBridgeAccount["codex"]> = {};
  if (input.threadSource !== undefined) {
    const threadSource = stringValue(input.threadSource);
    if (threadSource && CODEX_THREAD_SOURCES.has(threadSource as NonNullable<typeof codex.threadSource>)) {
      codex.threadSource = threadSource as NonNullable<typeof codex.threadSource>;
    } else {
      issues.push({
        path: `${path}.threadSource`,
        code: "codex.thread_source_invalid",
        message: "codex.threadSource must be app_server or file_scan.",
      });
    }
  }
  if (input.sendMode !== undefined) {
    const sendMode = stringValue(input.sendMode);
    if (sendMode && CODEX_SEND_MODES.has(sendMode as NonNullable<typeof codex.sendMode>)) {
      codex.sendMode = sendMode as NonNullable<typeof codex.sendMode>;
    } else {
      issues.push({
        path: `${path}.sendMode`,
        code: "codex.send_mode_invalid",
        message: "codex.sendMode must be app_server or cli_resume.",
      });
    }
  }
  return codex;
}

function normalizePushChannel(
  input: unknown,
  path: string,
  issues: ValidationIssue[],
): TelegramPushChannel | null {
  if (!isRecord(input)) {
    issues.push({
      path,
      code: "push_channel.not_object",
      message: "Push-only channel must be an object.",
    });
    return null;
  }
  const id = stringValue(input.id);
  const accountId = stringValue(input.accountId);
  const enabled = typeof input.enabled === "boolean" ? input.enabled : false;
  const target = normalizePushTarget(input.target, `${path}.target`, issues);

  if (!id) {
    issues.push({ path: `${path}.id`, code: "push_channel.id_missing", message: "Channel id is required." });
  }
  if (!accountId) {
    issues.push({
      path: `${path}.accountId`,
      code: "push_channel.account_id_missing",
      message: "Push-only channel accountId is required.",
    });
  }

  if (!id || !accountId || !target) {
    return null;
  }

  return {
    id,
    title: stringValue(input.title),
    accountId,
    enabled,
    target,
    format: isRecord(input.format) ? (input.format as TelegramPushChannel["format"]) : undefined,
    policy: isRecord(input.policy) ? (input.policy as TelegramPushChannel["policy"]) : undefined,
  };
}

function normalizePushTarget(
  input: unknown,
  path: string,
  issues: ValidationIssue[],
): TelegramPushTarget | null {
  if (!isRecord(input)) {
    issues.push({
      path,
      code: "push_target.not_object",
      message: "Push target must be an object.",
    });
    return null;
  }
  const kind = stringValue(input.kind);
  const value = stringValue(input.value);
  if (!kind || !PUSH_TARGET_KINDS.has(kind as TelegramPushTargetKind)) {
    issues.push({
      path: `${path}.kind`,
      code: "push_target.kind_invalid",
      message: "Push target kind must be chat_id, group_id, channel_id, or channel_username.",
    });
  }
  if (!value) {
    issues.push({
      path: `${path}.value`,
      code: "push_target.value_missing",
      message: "Push target value is required.",
    });
  }
  if (!kind || !value || !PUSH_TARGET_KINDS.has(kind as TelegramPushTargetKind)) {
    return null;
  }
  return {
    kind: kind as TelegramPushTargetKind,
    value,
  };
}

function validatePushChannelAccounts(
  config: TelegramBridgeConfig,
  issues: ValidationIssue[],
): void {
  const accountsByID = new Map(config.accounts.map((account) => [account.id, account]));
  for (const [index, channel] of (config.pushChannels ?? []).entries()) {
    const account = accountsByID.get(channel.accountId);
    if (!account) {
      issues.push({
        path: `$.pushChannels[${index}].accountId`,
        code: "push_channel.account_not_found",
        message: `Push-only channel references missing account \`${channel.accountId}\`.`,
      });
      continue;
    }
    if (account.role !== "push_only") {
      issues.push({
        path: `$.pushChannels[${index}].accountId`,
        code: "push_channel.account_not_push_only",
        message: `Push-only channel references non-push account \`${channel.accountId}\`.`,
      });
    }
  }
}

function failedPushChannel(code: string, message: string): ResolvedPushChannel {
  return {
    status: "failed",
    error: {
      code,
      message,
    },
  };
}

function readArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function idArrayValue(
  value: unknown,
  path: string,
  issues: ValidationIssue[],
): string[] | undefined {
  if (value === undefined) {
    return undefined;
  }
  if (!Array.isArray(value)) {
    issues.push({
      path,
      code: "security.id_array_invalid",
      message: "Telegram allowlist ids must be an array.",
    });
    return undefined;
  }
  const ids: string[] = [];
  for (const [index, item] of value.entries()) {
    if (typeof item === "string" && item.trim()) {
      ids.push(item.trim());
    } else if (typeof item === "number" && Number.isFinite(item)) {
      ids.push(String(item));
    } else {
      issues.push({
        path: `${path}[${index}]`,
        code: "security.id_invalid",
        message: "Telegram allowlist ids must be non-empty strings or finite numbers.",
      });
    }
  }
  return ids;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function redactIdentifier(value: string): string {
  if (value.length <= 4) {
    return "****";
  }
  const prefixLength = value.startsWith("@") ? 4 : 3;
  const prefix = value.slice(0, prefixLength);
  const suffix = value.slice(-3);
  return `${prefix}***${suffix}`;
}
