import type {
  TelegramBridgeAccount,
  TelegramBridgeConfig,
} from "./config.js";
import type { TelegramPollingState } from "./polling.js";

export type TelegramBridgeGatewayHealthStatus = "success" | "blocked" | "degraded" | "failed";

export type TelegramBridgeGatewayTokenStatus = {
  configured: boolean;
  status: "configured" | "missing" | "error";
  error?: string;
};

export type TelegramBridgeGatewayHealthIssue = {
  code: string;
  severity: Exclude<TelegramBridgeGatewayHealthStatus, "success">;
  message: string;
  account_id?: string;
  channel_id?: string;
};

export type TelegramBridgeGatewayLifecycleInput = {
  mode: "worker_cli" | "native_app";
  pollingLoop?: "running" | "stopped";
  pollIntervalMs?: number;
  startedAt?: string;
};

export type TelegramBridgeGatewayLifecycleHealth = {
  mode: TelegramBridgeGatewayLifecycleInput["mode"];
  polling_loop: "running" | "stopped";
  poll_interval_ms?: number;
  started_at?: string;
  webhook_ready: false;
  webhook_status: "not_implemented";
  fallback_attempted: false;
};

export type TelegramBridgeGatewayAccountHealth = {
  id: string;
  role: TelegramBridgeAccount["role"];
  transport: TelegramBridgeAccount["transport"]["mode"];
  token_configured: boolean;
  token_status: TelegramBridgeGatewayTokenStatus["status"];
  token_error?: string;
  polling_offset?: number;
};

export type TelegramBridgeGatewayHealth = {
  status: TelegramBridgeGatewayHealthStatus;
  fallback_attempted: false;
  lifecycle: TelegramBridgeGatewayLifecycleHealth;
  polling_account_count: number;
  webhook_account_count: number;
  push_only_account_count: number;
  enabled_push_channel_count: number;
  disabled_push_channel_count: number;
  missing_token_account_ids: string[];
  webhook_account_ids: string[];
  accounts: TelegramBridgeGatewayAccountHealth[];
  issues: TelegramBridgeGatewayHealthIssue[];
};

export type TelegramBridgeGatewayTokenStatusProvider = (
  accountId: string,
) => Promise<TelegramBridgeGatewayTokenStatus>;

export function tokenStatusProviderFromTokenProvider(
  tokenProvider: (accountId: string) => Promise<string | undefined>,
): TelegramBridgeGatewayTokenStatusProvider {
  return async (accountId) => {
    try {
      const token = await tokenProvider(accountId);
      return token?.trim()
        ? { configured: true, status: "configured" }
        : { configured: false, status: "missing" };
    } catch (error) {
      return {
        configured: false,
        status: "error",
        error: errorMessage(error),
      };
    }
  };
}

export async function buildTelegramBridgeGatewayHealth(
  config: TelegramBridgeConfig,
  state: TelegramPollingState,
  tokenStatusProvider: TelegramBridgeGatewayTokenStatusProvider = async () => ({
    configured: false,
    status: "missing",
  }),
  lifecycle: TelegramBridgeGatewayLifecycleInput = {
    mode: "worker_cli",
    pollingLoop: "stopped",
  },
): Promise<TelegramBridgeGatewayHealth> {
  const issues: TelegramBridgeGatewayHealthIssue[] = [];
  const missingTokenAccountIds: string[] = [];
  const webhookAccountIds: string[] = [];
  const accounts: TelegramBridgeGatewayAccountHealth[] = [];

  for (const account of config.accounts) {
    const tokenStatus = await tokenStatusProvider(account.id);
    if (!tokenStatus.configured) {
      missingTokenAccountIds.push(account.id);
      issues.push({
        code: tokenStatus.status === "error" ? "token_status_unavailable" : "token_missing",
        severity: "failed",
        account_id: account.id,
        message:
          tokenStatus.error ??
          `Telegram bot token is missing for account \`${account.id}\`.`,
      });
    }
    if (account.transport.mode === "webhook" && account.role !== "push_only") {
      webhookAccountIds.push(account.id);
      issues.push({
        code: "webhook_transport_not_ready",
        severity: "blocked",
        account_id: account.id,
        message:
          `Telegram webhook transport is configured for account \`${account.id}\`, ` +
          "but webhook ingress is not enabled in this release.",
      });
    }
    accounts.push({
      id: account.id,
      role: account.role,
      transport: account.transport.mode,
      token_configured: tokenStatus.configured,
      token_status: tokenStatus.status,
      ...(tokenStatus.error ? { token_error: tokenStatus.error } : {}),
      ...(state.offsets[account.id] !== undefined ? { polling_offset: state.offsets[account.id] } : {}),
    });
  }

  return {
    status: aggregateHealthStatus(issues),
    fallback_attempted: false,
    lifecycle: lifecycleHealth(lifecycle),
    polling_account_count: config.accounts.filter((account) => account.transport.mode === "polling").length,
    webhook_account_count: config.accounts.filter((account) => account.transport.mode === "webhook").length,
    push_only_account_count: config.accounts.filter((account) => account.role === "push_only").length,
    enabled_push_channel_count: (config.pushChannels ?? []).filter((channel) => channel.enabled).length,
    disabled_push_channel_count: (config.pushChannels ?? []).filter((channel) => !channel.enabled).length,
    missing_token_account_ids: missingTokenAccountIds,
    webhook_account_ids: webhookAccountIds,
    accounts,
    issues,
  };
}

function lifecycleHealth(
  lifecycle: TelegramBridgeGatewayLifecycleInput,
): TelegramBridgeGatewayLifecycleHealth {
  return {
    mode: lifecycle.mode,
    polling_loop: lifecycle.pollingLoop ?? "stopped",
    ...(lifecycle.pollIntervalMs !== undefined ? { poll_interval_ms: lifecycle.pollIntervalMs } : {}),
    ...(lifecycle.startedAt ? { started_at: lifecycle.startedAt } : {}),
    webhook_ready: false,
    webhook_status: "not_implemented",
    fallback_attempted: false,
  };
}

function aggregateHealthStatus(issues: TelegramBridgeGatewayHealthIssue[]): TelegramBridgeGatewayHealthStatus {
  return issues.reduce<TelegramBridgeGatewayHealthStatus>((current, issue) => {
    return healthStatusRank(issue.severity) > healthStatusRank(current) ? issue.severity : current;
  }, "success");
}

function healthStatusRank(status: TelegramBridgeGatewayHealthStatus): number {
  switch (status) {
    case "success":
      return 0;
    case "blocked":
      return 1;
    case "degraded":
      return 2;
    case "failed":
      return 3;
  }
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
