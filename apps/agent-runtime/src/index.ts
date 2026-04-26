import readline from "node:readline";

import {
  startAnthropicGateway,
  type AnthropicGatewayHandle,
} from "./gateway.js";
import {
  DEFAULT_SDK_AUTO_APPROVE_TOOLS,
  DEFAULT_SDK_DISALLOWED_TOOLS,
} from "./sdk-tool-policy.js";
import { ClaudeRuntimeSession } from "./session.js";
import type { RuntimeCommand, RuntimeEvent } from "./protocol.js";

const DEFAULT_MODEL = "sonnet";
const DEFAULT_MAX_TURNS = 100;

const sessions = new Map<string, ClaudeRuntimeSession>();

let initializedDefaultModel = DEFAULT_MODEL;
let gateway: AnthropicGatewayHandle | null = null;
let commandChain = Promise.resolve();

function configuredGatewayTimeoutSeconds(): number | undefined {
  const raw = process.env.GEEAGENT_XENODIA_REQUEST_TIMEOUT_SECONDS?.trim();
  if (!raw) {
    return undefined;
  }
  const parsed = Number(raw);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : undefined;
}

function emit(event: RuntimeEvent): void {
  process.stdout.write(`${JSON.stringify(event)}\n`);
}

function sessionFor(sessionId: string): ClaudeRuntimeSession {
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
    throw new Error("GEEAGENT_XENODIA_API_KEY is missing for the SDK runtime");
  }

  gateway = await startAnthropicGateway({
    xenodiaApiKey,
    backendUrl: process.env.GEEAGENT_XENODIA_CHAT_COMPLETIONS_URL,
    modelOverride: process.env.GEEAGENT_XENODIA_MODEL,
    requestTimeoutSeconds: configuredGatewayTimeoutSeconds(),
  });
  return gateway;
}

async function handleCommand(command: RuntimeCommand): Promise<void> {
  switch (command.type) {
    case "runtime.init": {
      initializedDefaultModel = command.defaultModel ?? DEFAULT_MODEL;
      await ensureGateway();
      emit({
        type: "runtime.initialized",
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
        command.autoApproveTools ?? DEFAULT_SDK_AUTO_APPROVE_TOOLS;
      const disallowedTools =
        command.disallowedTools ?? DEFAULT_SDK_DISALLOWED_TOOLS;
      const activeGateway = await ensureGateway();

      const session = new ClaudeRuntimeSession(
        {
          sessionId: command.sessionId,
          cwd,
          model,
          maxTurns,
          systemPrompt: command.systemPrompt,
          runtimeContext: command.runtimeContext,
          availableTools: command.availableTools,
          autoApproveTools,
          disallowedTools,
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
    case "runtime.shutdown": {
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
    type: "runtime.ready",
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
      const command = JSON.parse(line) as RuntimeCommand;
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
