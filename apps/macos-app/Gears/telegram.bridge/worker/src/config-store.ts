import { mkdir, readFile, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

import {
  validateBridgeConfig,
  type TelegramBridgeConfig,
} from "./config.js";
import type { TelegramPollingState } from "./polling.js";

export function defaultBridgeDataDir(): string {
  return join(
    homedir(),
    "Library",
    "Application Support",
    "GeeAgent",
    "gear-data",
    "telegram.bridge",
  );
}

export function defaultBridgeConfigPath(): string {
  return join(defaultBridgeDataDir(), "config.json");
}

export function defaultPollingStatePath(): string {
  return join(defaultBridgeDataDir(), "polling-state.json");
}

export async function loadBridgeConfigFile(path: string): Promise<TelegramBridgeConfig> {
  const parsed = JSON.parse(await readFile(path, "utf8")) as unknown;
  const validation = validateBridgeConfig(parsed);
  if (!validation.ok) {
    throw new Error(
      `Telegram Bridge config is invalid: ${validation.issues.map((issue) => issue.code).join(", ")}`,
    );
  }
  return validation.config;
}

export async function saveBridgeConfigFile(
  path: string,
  config: TelegramBridgeConfig,
): Promise<void> {
  const validation = validateBridgeConfig(config);
  if (!validation.ok) {
    throw new Error(
      `Refusing to save invalid Telegram Bridge config: ${validation.issues.map((issue) => issue.code).join(", ")}`,
    );
  }
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify(validation.config, null, 2)}\n`, "utf8");
}

export async function loadPollingStateFile(path: string): Promise<TelegramPollingState> {
  try {
    const parsed = JSON.parse(await readFile(path, "utf8")) as unknown;
    return normalizePollingState(parsed);
  } catch (error) {
    if (isNotFound(error)) {
      return { offsets: {} };
    }
    throw error;
  }
}

export async function savePollingStateFile(
  path: string,
  state: TelegramPollingState,
): Promise<void> {
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify(normalizePollingState(state), null, 2)}\n`, "utf8");
}

export function createEnvironmentTokenProvider(
  env: NodeJS.ProcessEnv = process.env,
): (accountId: string) => Promise<string | undefined> {
  const tokens = parseTokenMap(env.TELEGRAM_BRIDGE_TOKENS_JSON);
  return async (accountId: string) => {
    const mapped = tokens[accountId];
    if (typeof mapped === "string" && mapped.trim()) {
      return mapped.trim();
    }
    const key = `TELEGRAM_BRIDGE_TOKEN_${envKey(accountId)}`;
    const value = env[key];
    return value?.trim() || undefined;
  };
}

function normalizePollingState(value: unknown): TelegramPollingState {
  const record = isRecord(value) ? value : {};
  const offsets = isRecord(record.offsets) ? record.offsets : {};
  return {
    offsets: Object.fromEntries(
      Object.entries(offsets).flatMap(([key, item]) => {
        if (typeof item === "number" && Number.isFinite(item)) {
          return [[key, item]];
        }
        return [];
      }),
    ),
  };
}

function parseTokenMap(raw: string | undefined): Record<string, string> {
  if (!raw?.trim()) {
    return {};
  }
  const parsed = JSON.parse(raw) as unknown;
  if (!isRecord(parsed)) {
    return {};
  }
  return Object.fromEntries(
    Object.entries(parsed).filter((entry): entry is [string, string] => {
      return typeof entry[1] === "string" && entry[1].trim().length > 0;
    }),
  );
}

function envKey(accountId: string): string {
  return accountId.replace(/[^a-zA-Z0-9]/g, "_").toUpperCase();
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function isNotFound(error: unknown): boolean {
  return Boolean(error && typeof error === "object" && "code" in error && error.code === "ENOENT");
}
