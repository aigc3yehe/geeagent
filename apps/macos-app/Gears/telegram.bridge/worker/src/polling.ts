import type { TelegramBridgeConfig } from "./config.js";
import type { TelegramGetUpdatesInput, TelegramGetUpdatesResult } from "./telegram.js";
import {
  handleTelegramBridgeUpdate,
  pollingAccountIds,
  type CodexRemoteClient,
  type RuntimeChannelClient,
  type TelegramBridgeUpdateResult,
  type TelegramUpdate,
} from "./service.js";
import type {
  PushSendDependencies,
  TelegramSendClient,
} from "./send.js";

export type TelegramPollingBotClient = TelegramSendClient & {
  getUpdates(input: TelegramGetUpdatesInput): Promise<TelegramGetUpdatesResult>;
};

export type TelegramPollingState = {
  offsets: Record<string, number | undefined>;
};

export type TelegramPollingDependencies = Omit<PushSendDependencies, "telegramClient"> & {
  telegramClient: TelegramPollingBotClient;
  runtimeClient: RuntimeChannelClient;
  codexClient?: CodexRemoteClient;
  timeoutSeconds?: number;
};

export type TelegramPollingAccountResult = {
  accountId: string;
  status: "success" | "blocked" | "degraded" | "failed";
  updateCount: number;
  handledCount: number;
  nextOffset?: number;
  error: null | {
    code: string;
    message: string;
    retryAfterMs?: number;
  };
};

export type TelegramPollingResult = {
  status: "success" | "blocked" | "degraded" | "failed";
  fallback_attempted: false;
  polls: TelegramPollingAccountResult[];
  nextState: TelegramPollingState;
};

const DEGRADABLE_CODES = new Set([
  "network_unavailable",
  "telegram_rate_limited",
  "telegram_timeout",
]);

export async function pollTelegramBridgeOnce(
  config: TelegramBridgeConfig,
  state: TelegramPollingState,
  dependencies: TelegramPollingDependencies,
): Promise<TelegramPollingResult> {
  const nextOffsets: Record<string, number | undefined> = { ...state.offsets };
  const polls: TelegramPollingAccountResult[] = [];

  for (const accountId of pollingAccountIds(config)) {
    const poll = await pollAccount(config, accountId, nextOffsets[accountId], dependencies);
    polls.push(poll);
    if (poll.nextOffset !== undefined) {
      nextOffsets[accountId] = poll.nextOffset;
    }
  }

  return {
    status: aggregateStatus(polls),
    fallback_attempted: false,
    polls,
    nextState: {
      offsets: compactOffsets(nextOffsets),
    },
  };
}

async function pollAccount(
  config: TelegramBridgeConfig,
  accountId: string,
  offset: number | undefined,
  dependencies: TelegramPollingDependencies,
): Promise<TelegramPollingAccountResult> {
  let token: string | undefined;
  try {
    token = (await dependencies.tokenProvider(accountId))?.trim();
  } catch (error) {
    return accountFailure(accountId, "failed", "token_unavailable", errorMessage(error), 0, 0, offset);
  }
  if (!token) {
    return accountFailure(
      accountId,
      "failed",
      "token_missing",
      `Telegram bot token is missing for account \`${accountId}\`.`,
      0,
      0,
      offset,
    );
  }

  let updatesResult: TelegramGetUpdatesResult;
  try {
    updatesResult = await dependencies.telegramClient.getUpdates({
      token,
      offset,
      timeoutSeconds: dependencies.timeoutSeconds,
    });
  } catch (error) {
    return accountFailure(accountId, "degraded", "network_unavailable", errorMessage(error), 0, 0, offset);
  }
  if (!updatesResult.ok) {
    return accountFailure(
      accountId,
      DEGRADABLE_CODES.has(updatesResult.code) ? "degraded" : "failed",
      updatesResult.code,
      updatesResult.message,
      0,
      0,
      offset,
      updatesResult.retryAfterMs,
    );
  }

  let handledCount = 0;
  let nextOffset = offset;
  let worstStatus: TelegramPollingAccountResult["status"] = "success";
  let latestError: TelegramPollingAccountResult["error"] = null;

  for (const update of updatesResult.updates) {
    const updateId = telegramUpdateId(update);
    let updateResult: TelegramBridgeUpdateResult;
    try {
      updateResult = await handleTelegramBridgeUpdate(config, accountId, update as TelegramUpdate, dependencies);
    } catch (error) {
      updateResult = {
        status: "failed",
        fallback_attempted: false,
        accountId,
        updateId,
        error: {
          code: "update_handler_failed",
          message: errorMessage(error),
        },
      };
    }
    handledCount += 1;
    if (updateId !== undefined) {
      nextOffset = Math.max(nextOffset ?? 0, updateId + 1);
    }
    const mappedStatus = updateStatusToPollStatus(updateResult.status);
    if (statusRank(mappedStatus) > statusRank(worstStatus)) {
      worstStatus = mappedStatus;
      latestError = updateResult.error;
    }
  }

  return {
    accountId,
    status: worstStatus,
    updateCount: updatesResult.updates.length,
    handledCount,
    nextOffset,
    error: latestError,
  };
}

function accountFailure(
  accountId: string,
  status: Exclude<TelegramPollingAccountResult["status"], "success">,
  code: string,
  message: string,
  updateCount: number,
  handledCount: number,
  nextOffset: number | undefined,
  retryAfterMs?: number,
): TelegramPollingAccountResult {
  return {
    accountId,
    status,
    updateCount,
    handledCount,
    nextOffset,
    error: {
      code,
      message,
      retryAfterMs,
    },
  };
}

function updateStatusToPollStatus(
  status: TelegramBridgeUpdateResult["status"],
): TelegramPollingAccountResult["status"] {
  switch (status) {
    case "success":
    case "dropped":
      return "success";
    case "blocked":
      return "blocked";
    case "degraded":
      return "degraded";
    case "failed":
      return "failed";
  }
}

function aggregateStatus(
  polls: TelegramPollingAccountResult[],
): TelegramPollingResult["status"] {
  return polls.reduce<TelegramPollingResult["status"]>((current, poll) => {
    return statusRank(poll.status) > statusRank(current) ? poll.status : current;
  }, "success");
}

function statusRank(status: TelegramPollingAccountResult["status"]): number {
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

function compactOffsets(
  offsets: Record<string, number | undefined>,
): Record<string, number | undefined> {
  return Object.fromEntries(
    Object.entries(offsets).filter(([, value]) => value !== undefined),
  ) as Record<string, number | undefined>;
}

function telegramUpdateId(update: unknown): number | undefined {
  if (!update || typeof update !== "object" || Array.isArray(update)) {
    return undefined;
  }
  const value = (update as { update_id?: unknown }).update_id;
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
