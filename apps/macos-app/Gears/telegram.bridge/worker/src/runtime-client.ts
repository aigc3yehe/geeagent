import { spawn } from "node:child_process";
import { join } from "node:path";

import type {
  RuntimeChannelClient,
  RuntimeChannelMessageInput,
} from "./service.js";

export type RuntimeCommandResult = {
  code: number;
  signal: string | null;
  stdout: string;
  stderr: string;
};

export type RuntimeCommandRunner = (
  command: string,
  args: string[],
  options: {
    timeoutMs: number;
  },
) => Promise<RuntimeCommandResult>;

export type NativeRuntimeChannelClientOptions = {
  command?: string;
  args?: string[];
  configDir?: string;
  timeoutMs?: number;
  runner?: RuntimeCommandRunner;
};

export function createNativeRuntimeChannelClient(
  options: NativeRuntimeChannelClientOptions = {},
): RuntimeChannelClient {
  const command = options.command ?? "node";
  const args = options.args ?? [defaultRuntimeEntrypoint()];
  const timeoutMs = options.timeoutMs ?? 150_000;
  const runner = options.runner ?? runRuntimeCommand;

  return {
    async submitChannelMessage(input: RuntimeChannelMessageInput): Promise<Record<string, unknown>> {
      const runtimeArgs = [
        ...args,
        "submit-channel-message",
        JSON.stringify(input),
      ];
      if (options.configDir?.trim()) {
        runtimeArgs.push("--config-dir", options.configDir.trim());
      }
      const result = await runner(command, runtimeArgs, { timeoutMs });
      if (result.code !== 0) {
        throw new Error(result.stderr.trim() || result.stdout.trim() || `native runtime exited with code ${result.code}`);
      }
      return parseSnapshot(result.stdout);
    },
  };
}

function defaultRuntimeEntrypoint(): string {
  return join(process.cwd(), "dist", "native-runtime", "index.mjs");
}

function parseSnapshot(stdout: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(stdout) as unknown;
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      return parsed as Record<string, unknown>;
    }
    throw new Error("native runtime did not return a JSON object");
  } catch (error) {
    throw new Error(`native runtime returned invalid JSON: ${errorMessage(error)}`);
  }
}

function runRuntimeCommand(
  command: string,
  args: string[],
  options: { timeoutMs: number },
): Promise<RuntimeCommandResult> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      env: process.env,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    let settled = false;
    const timer = setTimeout(() => {
      if (settled) {
        return;
      }
      settled = true;
      child.kill("SIGTERM");
      reject(new Error(`native runtime timed out after ${options.timeoutMs}ms`));
    }, options.timeoutMs);
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.on("error", (error) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      reject(error);
    });
    child.on("close", (code, signal) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      resolve({
        code: code ?? 1,
        signal,
        stdout,
        stderr,
      });
    });
  });
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
