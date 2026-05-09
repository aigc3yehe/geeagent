import readline from "node:readline";
import type { Readable, Writable } from "node:stream";

import { handleNativeRuntimeCommand } from "./commands.js";
import {
  errorResponse,
  okResponse,
  type RuntimeRequest,
} from "./protocol.js";
import { shutdownSdkRuntime } from "./sdk-turn-runner.js";
import { reconcileStaleApprovals } from "./store/stale-approvals.js";
import { terminateActiveProcesses } from "./tools/process.js";

export type NativeRuntimeServerOptions = {
  configDir?: string;
  parentPid?: number;
  input?: Readable;
  output?: Writable;
};

export async function runNativeRuntimeServer(
  options: NativeRuntimeServerOptions = {},
): Promise<void> {
  const input = options.input ?? process.stdin;
  const output = options.output ?? process.stdout;
  let chain = Promise.resolve();

  await reconcileStaleApprovals(options.configDir);
  const lines = readline.createInterface({ input, crlfDelay: Infinity });
  let parentExitStarted = false;
  const stopParentMonitor = monitorParentProcess(options.parentPid, () => {
    if (parentExitStarted) {
      return;
    }
    parentExitStarted = true;
    lines.close();
    terminateActiveProcesses();
    void shutdownSdkRuntime().catch(() => {});
    setTimeout(() => {
      process.exit(0);
    }, 500);
  });

  try {
    for await (const line of lines) {
      if (!line.trim()) {
        continue;
      }
      chain = chain.then(() => handleLine(line, output, options.configDir));
    }
  } finally {
    stopParentMonitor();
  }

  await chain;
}

function monitorParentProcess(
  parentPid: number | undefined,
  onParentUnavailable: () => void,
): () => void {
  if (!Number.isInteger(parentPid) || parentPid === undefined || parentPid <= 0) {
    return () => {};
  }
  const timer = setInterval(() => {
    if (!isProcessAlive(parentPid)) {
      onParentUnavailable();
    }
  }, 2_000);
  timer.unref();
  return () => clearInterval(timer);
}

function isProcessAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return Boolean(error && typeof error === "object" && "code" in error && error.code === "EPERM");
  }
}

async function handleLine(
  line: string,
  output: Writable,
  configDir?: string,
): Promise<void> {
  let request: RuntimeRequest;
  try {
    request = JSON.parse(line) as RuntimeRequest;
  } catch (error) {
    output.write(`${JSON.stringify(errorResponse("unknown", error))}\n`);
    return;
  }

  try {
    const result = await handleNativeRuntimeCommand(
      request.command,
      request.args ?? [],
      { configDir },
    );
    output.write(`${JSON.stringify(okResponse(request.id, result))}\n`);
  } catch (error) {
    output.write(`${JSON.stringify(errorResponse(request.id, error))}\n`);
  }
}
