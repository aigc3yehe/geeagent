import { writeFileSync, writeSync } from "node:fs";

import {
  loadChatReadiness,
  loadChatRoutingSettings,
  loadXenodiaGatewayBackend,
  persistChatRoutingSettings,
  type ChatRoutingSettings,
} from "./chat-runtime.js";

type ParsedArgs = {
  command?: string;
  configDir?: string;
  outputPath?: string;
};

function parseArgs(args: string[]): ParsedArgs {
  const parsed: ParsedArgs = {};
  const rest = [...args];
  parsed.command = rest.shift();

  while (rest.length > 0) {
    const next = rest.shift();
    if (next === "--config-dir") {
      parsed.configDir = rest.shift();
      continue;
    }
    if (next === "--output") {
      parsed.outputPath = rest.shift();
      continue;
    }
    throw new Error(`unsupported argument: ${next ?? ""}`);
  }

  return parsed;
}

async function readStdin(): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  return Buffer.concat(chunks).toString("utf8");
}

function writeStdout(text: string): void {
  writeSync(1, text);
}

function writeOutput(text: string, outputPath?: string): void {
  if (outputPath) {
    writeFileSync(outputPath, text, "utf8");
    return;
  }
  writeStdout(text);
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));

  switch (args.command) {
    case "get-chat-routing-settings": {
      const settings = await loadChatRoutingSettings(args.configDir);
      writeOutput(`${JSON.stringify(settings)}\n`, args.outputPath);
      return;
    }
    case "get-chat-readiness": {
      const readiness = await loadChatReadiness(args.configDir);
      writeOutput(`${JSON.stringify(readiness)}\n`, args.outputPath);
      return;
    }
    case "get-xenodia-gateway-backend": {
      const backend = await loadXenodiaGatewayBackend(args.configDir);
      writeOutput(`${JSON.stringify(backend)}\n`, args.outputPath);
      return;
    }
    case "save-chat-routing-settings": {
      if (!args.configDir) {
        throw new Error("save-chat-routing-settings requires --config-dir");
      }
      const raw = await readStdin();
      const settings = JSON.parse(raw) as ChatRoutingSettings;
      await persistChatRoutingSettings(args.configDir, settings);
      writeOutput("{}\n", args.outputPath);
      return;
    }
    default:
      throw new Error(
        "usage: chat-runtime-cli <get-chat-routing-settings|get-chat-readiness|get-xenodia-gateway-backend|save-chat-routing-settings> [--config-dir <path>]",
      );
  }
}

void main().then(
  () => {
    process.exit(0);
  },
  (error: unknown) => {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exit(1);
  },
);
