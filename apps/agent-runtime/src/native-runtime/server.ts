import readline from "node:readline";
import type { Readable, Writable } from "node:stream";

import { handleNativeRuntimeCommand } from "./commands.js";
import {
  errorResponse,
  okResponse,
  type RuntimeRequest,
} from "./protocol.js";
import { reconcileStaleApprovals } from "./store/stale-approvals.js";

export type NativeRuntimeServerOptions = {
  configDir?: string;
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

  for await (const line of lines) {
    if (!line.trim()) {
      continue;
    }
    chain = chain.then(() => handleLine(line, output, options.configDir));
  }

  await chain;
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
