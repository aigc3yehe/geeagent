#!/usr/bin/env node
import { readFile } from "node:fs/promises";
import process from "node:process";

import { upsertPushChannel } from "./channels.js";
import {
  createEnvironmentTokenProvider,
  defaultBridgeConfigPath,
  defaultPollingStatePath,
  loadBridgeConfigFile,
  loadPollingStateFile,
  saveBridgeConfigFile,
  savePollingStateFile,
} from "./config-store.js";
import {
  redactTelegramTarget,
  type TelegramBridgeConfig,
  type TelegramPushTargetKind,
} from "./config.js";
import { createCodexRemoteClient } from "./codex.js";
import { pollTelegramBridgeOnce } from "./polling.js";
import { createNativeRuntimeChannelClient } from "./runtime-client.js";
import { sendPushMessage } from "./send.js";
import { createTelegramBotApiClient } from "./telegram.js";

type ParsedArgs = {
  command: string;
  options: Record<string, string | string[] | boolean>;
  positionals: string[];
};

export async function runTelegramBridgeCli(argv: string[]): Promise<number> {
  const parsed = parseArgs(argv);
  if (!parsed.command || parsed.command === "help" || parsed.options.help === true) {
    printUsage();
    return parsed.command ? 0 : 2;
  }

  switch (parsed.command) {
    case "status":
      return printJson(await statusCommand(parsed));
    case "list-channels":
      return printJson(await listChannelsCommand(parsed));
    case "upsert-push-channel":
      return printJson(await upsertPushChannelCommand(parsed));
    case "send-push":
      return printJson(await sendPushCommand(parsed));
    case "poll-once":
      return printJson(await pollOnceCommand(parsed));
    case "poll-loop":
      return pollLoopCommand(parsed);
    default:
      process.stderr.write(`Unsupported command: ${parsed.command}\n`);
      printUsage();
      return 2;
  }
}

async function statusCommand(parsed: ParsedArgs): Promise<Record<string, unknown>> {
  const config = await loadBridgeConfigFile(configPath(parsed));
  const state = await loadPollingStateFile(statePath(parsed));
  return {
    status: "success",
    fallback_attempted: false,
    config_path: configPath(parsed),
    state_path: statePath(parsed),
    accounts: config.accounts.map((account) => ({
      id: account.id,
      role: account.role,
      transport: account.transport.mode,
      bot_username: account.botUsername,
    })),
    push_channels: channelSummaries(config),
    polling_offsets: state.offsets,
  };
}

async function listChannelsCommand(parsed: ParsedArgs): Promise<Record<string, unknown>> {
  const config = await loadBridgeConfigFile(configPath(parsed));
  return {
    status: "success",
    fallback_attempted: false,
    channels: channelSummaries(config),
  };
}

async function upsertPushChannelCommand(parsed: ParsedArgs): Promise<Record<string, unknown>> {
  const path = configPath(parsed);
  const config = await loadConfigOrEmpty(path);
  const targetKind = requiredOption(parsed, "target-kind") as TelegramPushTargetKind;
  const targetValue = requiredOption(parsed, "target-value");
  const result = upsertPushChannel(config, {
    channelId: requiredOption(parsed, "channel"),
    accountId: requiredOption(parsed, "account"),
    title: stringOption(parsed, "title"),
    botUsername: stringOption(parsed, "bot-username"),
    target: {
      kind: targetKind,
      value: targetValue,
    },
    enabled: booleanOption(parsed, "enabled") ?? true,
    parseMode: parseModeOption(parsed, "parse-mode"),
    disableWebPreview: booleanOption(parsed, "disable-web-preview"),
  });
  if (result.status === "success") {
    await saveBridgeConfigFile(path, result.config);
  }
  return {
    ...result,
    config: undefined,
    config_path: path,
    token_binding:
      "store the bot token outside config via TELEGRAM_BRIDGE_TOKENS_JSON or TELEGRAM_BRIDGE_TOKEN_<ACCOUNT_ID>",
  };
}

async function sendPushCommand(parsed: ParsedArgs): Promise<Record<string, unknown>> {
  const config = await loadBridgeConfigFile(configPath(parsed));
  const telegramClient = createTelegramBotApiClient({
    apiBaseUrl: stringOption(parsed, "telegram-api-base-url"),
  });
  const message = await messageInput(parsed);
  const result = await sendPushMessage(
    config,
    {
      channelId: requiredOption(parsed, "channel"),
      message,
      idempotencyKey: requiredOption(parsed, "idempotency-key"),
      parseMode: parseModeOption(parsed, "parse-mode"),
      disableWebPreview: booleanOption(parsed, "disable-web-preview"),
    },
    {
      tokenProvider: createEnvironmentTokenProvider(),
      telegramClient,
    },
  );
  return result;
}

async function pollOnceCommand(parsed: ParsedArgs): Promise<Record<string, unknown>> {
  const config = await loadBridgeConfigFile(configPath(parsed));
  const state = await loadPollingStateFile(statePath(parsed));
  const result = await pollTelegramBridgeOnce(config, state, {
    tokenProvider: createEnvironmentTokenProvider(),
    telegramClient: createTelegramBotApiClient({
      apiBaseUrl: stringOption(parsed, "telegram-api-base-url"),
    }),
    runtimeClient: createNativeRuntimeChannelClient({
      command: stringOption(parsed, "runtime-command"),
      args: runtimeArgs(parsed),
      configDir: stringOption(parsed, "runtime-config-dir"),
    }),
    codexClient: createCodexRemoteClient({
      codexHome: stringOption(parsed, "codex-home"),
      codexBin: stringOption(parsed, "codex-bin"),
    }),
    timeoutSeconds: numberOption(parsed, "telegram-timeout-seconds"),
  });
  await savePollingStateFile(statePath(parsed), result.nextState);
  return result;
}

async function pollLoopCommand(parsed: ParsedArgs): Promise<number> {
  const intervalMs = numberOption(parsed, "interval-ms") ?? 3_000;
  let stopped = false;
  const stop = () => {
    stopped = true;
  };
  process.once("SIGINT", stop);
  process.once("SIGTERM", stop);
  while (!stopped) {
    try {
      process.stdout.write(`${JSON.stringify(await pollOnceCommand(parsed))}\n`);
    } catch (error) {
      process.stdout.write(
        `${JSON.stringify({
          status: "failed",
          fallback_attempted: false,
          error: {
            code: "poll_loop_failed",
            message: errorMessage(error),
          },
        })}\n`,
      );
    }
    if (!stopped) {
      await new Promise((resolve) => setTimeout(resolve, intervalMs));
    }
  }
  return 0;
}

function parseArgs(argv: string[]): ParsedArgs {
  const [command = "", ...rest] = argv;
  const options: Record<string, string | string[] | boolean> = {};
  const positionals: string[] = [];
  for (let index = 0; index < rest.length; index += 1) {
    const value = rest[index];
    if (!value.startsWith("--")) {
      positionals.push(value);
      continue;
    }
    const key = value.slice(2);
    const next = rest[index + 1];
    const optionValue = !next || next.startsWith("--") ? true : next;
    if (optionValue !== true) {
      index += 1;
    }
    if (options[key] === undefined) {
      options[key] = optionValue;
    } else if (Array.isArray(options[key])) {
      (options[key] as string[]).push(String(optionValue));
    } else {
      options[key] = [String(options[key]), String(optionValue)];
    }
  }
  return { command, options, positionals };
}

function configPath(parsed: ParsedArgs): string {
  return stringOption(parsed, "config") ?? defaultBridgeConfigPath();
}

function statePath(parsed: ParsedArgs): string {
  return stringOption(parsed, "state") ?? defaultPollingStatePath();
}

async function loadConfigOrEmpty(path: string): Promise<TelegramBridgeConfig> {
  try {
    return await loadBridgeConfigFile(path);
  } catch (error) {
    if (error && typeof error === "object" && "code" in error && error.code === "ENOENT") {
      return { version: 1, accounts: [], pushChannels: [] };
    }
    throw error;
  }
}

function channelSummaries(config: TelegramBridgeConfig): Array<Record<string, unknown>> {
  return (config.pushChannels ?? []).map((channel) => ({
    id: channel.id,
    title: channel.title,
    account_id: channel.accountId,
    enabled: channel.enabled,
    target: redactTelegramTarget(channel.target),
  }));
}

function runtimeArgs(parsed: ParsedArgs): string[] | undefined {
  const runtimeEntry = stringOption(parsed, "runtime-entry");
  const rawArgs = parsed.options["runtime-arg"];
  const args = Array.isArray(rawArgs)
    ? rawArgs
    : typeof rawArgs === "string"
      ? [rawArgs]
      : [];
  if (runtimeEntry) {
    return [runtimeEntry, ...args];
  }
  if (process.env.GEEAGENT_NATIVE_RUNTIME_ENTRY?.trim()) {
    return [process.env.GEEAGENT_NATIVE_RUNTIME_ENTRY.trim(), ...args];
  }
  return args.length > 0 ? args : undefined;
}

async function messageInput(parsed: ParsedArgs): Promise<string> {
  const message = stringOption(parsed, "message");
  if (message !== undefined) {
    return message;
  }
  const messageFile = stringOption(parsed, "message-file");
  if (messageFile) {
    return readFile(messageFile, "utf8");
  }
  return requiredOption(parsed, "message");
}

function stringOption(parsed: ParsedArgs, key: string): string | undefined {
  const value = parsed.options[key];
  if (typeof value === "string" && value.trim()) {
    return value;
  }
  return undefined;
}

function requiredOption(parsed: ParsedArgs, key: string): string {
  const value = stringOption(parsed, key);
  if (!value) {
    throw new Error(`--${key} is required`);
  }
  return value;
}

function booleanOption(parsed: ParsedArgs, key: string): boolean | undefined {
  const value = parsed.options[key];
  if (value === true) {
    return true;
  }
  if (value === "true") {
    return true;
  }
  if (value === "false") {
    return false;
  }
  return undefined;
}

function numberOption(parsed: ParsedArgs, key: string): number | undefined {
  const value = stringOption(parsed, key);
  if (!value) {
    return undefined;
  }
  const number = Number(value);
  return Number.isFinite(number) ? number : undefined;
}

function parseModeOption(
  parsed: ParsedArgs,
  key: string,
): "Markdown" | "MarkdownV2" | "HTML" | "plain" | undefined {
  const value = stringOption(parsed, key);
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

function printJson(value: unknown): number {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
  return 0;
}

function printUsage(): void {
  process.stderr.write(
    [
      "usage: telegram-bridge-worker <command> [options]",
      "",
      "commands:",
      "  status --config <config.json>",
      "  list-channels --config <config.json>",
      "  upsert-push-channel --channel <id> --account <account_id> --target-kind <chat_id|group_id|channel_id|channel_username> --target-value <target>",
      "  send-push --channel <id> --message <text> --idempotency-key <key>",
      "  poll-once --config <config.json> --state <polling-state.json> --runtime-entry <native-runtime/index.mjs>",
      "  poll-loop --config <config.json> --state <polling-state.json> --runtime-entry <native-runtime/index.mjs>",
      "",
      "tokens: use TELEGRAM_BRIDGE_TOKENS_JSON or TELEGRAM_BRIDGE_TOKEN_<ACCOUNT_ID>",
    ].join("\n") + "\n",
  );
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

if (process.argv[1]?.endsWith("cli.ts") || process.argv[1]?.endsWith("cli.js")) {
  runTelegramBridgeCli(process.argv.slice(2))
    .then((code) => {
      process.exitCode = code;
    })
    .catch((error: unknown) => {
      process.stderr.write(`${errorMessage(error)}\n`);
      process.exitCode = 1;
    });
}
