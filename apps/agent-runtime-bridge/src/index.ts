import readline from "node:readline";

import {
  startAnthropicGateway,
  type AnthropicGatewayHandle,
} from "./gateway.js";
import { ClaudeBridgeSession } from "./session.js";
import type { BridgeCommand, BridgeEvent } from "./protocol.js";

const DEFAULT_MODEL = "sonnet";
const DEFAULT_MAX_TURNS = 100;
const DEFAULT_AUTO_APPROVE_TOOLS = [
  "ToolSearch",
  "ExitPlanMode",
  "Read",
  "Glob",
  "Grep",
  "LS",
  "BashOutput",
  "KillBash",
];

const sessions = new Map<string, ClaudeBridgeSession>();

let initializedDefaultModel = DEFAULT_MODEL;
let gateway: AnthropicGatewayHandle | null = null;
let commandChain = Promise.resolve();

function emit(event: BridgeEvent): void {
  process.stdout.write(`${JSON.stringify(event)}\n`);
}

function sessionFor(sessionId: string): ClaudeBridgeSession {
  const session = sessions.get(sessionId);
  if (!session) {
    throw new Error(`unknown session ${sessionId}`);
  }
  return session;
}

async function ensureGateway(): Promise<AnthropicGatewayHandle> {
  if (gateway) {
    return gateway;
  }

  const xenodiaApiKey = process.env.GEEAGENT_XENODIA_API_KEY?.trim();
  if (!xenodiaApiKey) {
    throw new Error("GEEAGENT_XENODIA_API_KEY is missing for the SDK bridge");
  }

  gateway = await startAnthropicGateway({
    xenodiaApiKey,
    backendUrl: process.env.GEEAGENT_XENODIA_CHAT_COMPLETIONS_URL,
    modelOverride: process.env.GEEAGENT_XENODIA_MODEL,
  });
  return gateway;
}

async function handleCommand(command: BridgeCommand): Promise<void> {
  switch (command.type) {
    case "bridge.init": {
      initializedDefaultModel = command.defaultModel ?? DEFAULT_MODEL;
      await ensureGateway();
      emit({
        type: "bridge.initialized",
        defaultModel: initializedDefaultModel,
      });
      return;
    }
    case "session.create": {
      if (sessions.has(command.sessionId)) {
        throw new Error(`session ${command.sessionId} already exists`);
      }

      const cwd = command.cwd ?? process.cwd();
      const model = command.model ?? initializedDefaultModel;
      const maxTurns = command.maxTurns ?? DEFAULT_MAX_TURNS;
      const autoApproveTools =
        command.autoApproveTools ?? DEFAULT_AUTO_APPROVE_TOOLS;
      const activeGateway = await ensureGateway();

      const session = new ClaudeBridgeSession(
        {
          sessionId: command.sessionId,
          cwd,
          model,
          maxTurns,
          systemPrompt: command.systemPrompt,
          runtimeContext: command.runtimeContext,
          autoApproveTools,
          gatewayBaseUrl: activeGateway.baseUrl,
          gatewayApiKey: activeGateway.apiKey,
        },
        emit,
      );

      sessions.set(command.sessionId, session);
      emit({
        type: "session.created",
        sessionId: command.sessionId,
        model,
        cwd,
      });
      return;
    }
    case "session.send": {
      sessionFor(command.sessionId).send(command.content);
      return;
    }
    case "session.approval": {
      sessionFor(command.sessionId).resolveApproval(command.requestId, {
        decision: command.decision,
        message: command.message,
        updatedInput: command.updatedInput,
      });
      return;
    }
    case "session.close": {
      const session = sessionFor(command.sessionId);
      session.close();
      sessions.delete(command.sessionId);
      emit({
        type: "session.closed",
        sessionId: command.sessionId,
      });
      return;
    }
    case "bridge.shutdown": {
      for (const [sessionId, session] of sessions) {
        session.close();
        emit({
          type: "session.closed",
          sessionId,
        });
      }
      sessions.clear();
      if (gateway) {
        await gateway.close();
        gateway = null;
      }
      process.exit(0);
    }
  }
}

async function main(): Promise<void> {
  emit({
    type: "bridge.ready",
    protocolVersion: "0.1.0",
    pid: process.pid,
  });

  const rl = readline.createInterface({
    input: process.stdin,
    crlfDelay: Infinity,
  });

  rl.on("line", (line) => {
    if (!line.trim()) {
      return;
    }

    try {
      const command = JSON.parse(line) as BridgeCommand;
      commandChain = commandChain
        .then(() => handleCommand(command))
        .catch((error: unknown) => {
          emit({
            type: "session.error",
            error: error instanceof Error ? error.message : String(error),
          });
        });
    } catch (error) {
      emit({
        type: "session.error",
        error: error instanceof Error ? error.message : String(error),
      });
    }
  });

  rl.on("close", () => {
    for (const [, session] of sessions) {
      session.close();
    }
    sessions.clear();
    if (gateway) {
      void gateway.close();
      gateway = null;
    }
  });
}

void main();
