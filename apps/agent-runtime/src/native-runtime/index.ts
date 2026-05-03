import { handleNativeRuntimeCommand } from "./commands.js";
import { runCodexMcpServer } from "./codex-mcp-server.js";
import { runNativeRuntimeServer } from "./server.js";
import { shutdownSdkRuntime } from "./sdk-turn-runner.js";

type ParsedArgs = {
  command?: string;
  args: string[];
  configDir?: string;
};

function parseArgs(rawArgs: string[]): ParsedArgs {
  const args: string[] = [];
  let configDir: string | undefined;

  for (let index = 0; index < rawArgs.length; index += 1) {
    const value = rawArgs[index];
    if (value === "--config-dir") {
      configDir = rawArgs[index + 1];
      index += 1;
      continue;
    }
    args.push(value);
  }

  return {
    command: args[0],
    args: args.slice(1),
    configDir,
  };
}

function printUsage(): void {
  process.stderr.write(
    "usage: native-runtime <command> [args] [--config-dir <path>]\n" +
      "commands: snapshot, list-agent-profiles, create-conversation, " +
      "set-active-conversation, delete-conversation, set-active-agent-profile, " +
      "install-agent-pack, reload-agent-profile, delete-agent-profile, " +
      "delete-terminal-access-rule, export-runtime-run, project-runtime-run, " +
      "project-runtime-run-replay, classify-runtime-run-wait, " +
      "submit-workspace-message, submit-routed-workspace-message, " +
      "submit-quick-prompt, perform-task-action, get-chat-routing-settings, " +
      "save-chat-routing-settings, set-highest-authorization, add-system-skill-source, " +
      "remove-system-skill-source, add-persona-skill-source, remove-persona-skill-source, " +
      "codex-export-status, codex-export-list-capabilities, " +
      "codex-export-describe-capability, codex-export-generate-plugin, " +
      "codex-export-install-plugin, " +
      "codex-external-invocation-complete, " +
      "invoke-tool, codex-mcp, serve\n",
  );
}

async function main(): Promise<void> {
  const parsed = parseArgs(process.argv.slice(2));
  if (!parsed.command) {
    printUsage();
    process.exit(2);
  }

  if (parsed.command === "serve") {
    if (parsed.args.length > 0) {
      throw new Error("serve does not accept positional arguments");
    }
    await runNativeRuntimeServer({ configDir: parsed.configDir });
    return;
  }

  if (parsed.command === "codex-mcp") {
    if (parsed.args.length > 0) {
      throw new Error("codex-mcp does not accept positional arguments");
    }
    await runCodexMcpServer({ configDir: parsed.configDir });
    return;
  }

  try {
    const output = await handleNativeRuntimeCommand(parsed.command, parsed.args, {
      configDir: parsed.configDir,
    });
    process.stdout.write(output);
  } finally {
    await shutdownSdkRuntime();
  }
}

void main().catch((error: unknown) => {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exit(1);
});
