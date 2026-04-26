import { randomUUID } from "node:crypto";

import {
  unstable_v2_createSession,
  type SDKMessage,
  type SDKSession,
} from "@anthropic-ai/claude-agent-sdk";

import type { RuntimeEvent, RuntimeContext } from "./protocol.js";

type SessionConfig = {
  sessionId: string;
  cwd: string;
  model: string;
  maxTurns: number;
  systemPrompt?: string;
  runtimeContext?: RuntimeContext;
  availableTools?: string[];
  autoApproveTools: string[];
  disallowedTools: string[];
  gatewayBaseUrl: string;
  gatewayApiKey: string;
};

type ApprovalDecision = {
  decision: "allow" | "deny";
  message?: string;
  updatedInput?: Record<string, unknown>;
};

type PendingApproval = {
  resolve: (decision: ApprovalDecision) => void;
  reject: (error: Error) => void;
};

function claudeCodeExecutablePath(): string | undefined {
  const path = process.env.GEEAGENT_CLAUDE_CODE_EXECUTABLE?.trim();
  return path && path.length > 0 ? path : undefined;
}

function buildSystemPrompt(
  sessionPrompt: string | undefined,
  context: RuntimeContext | undefined,
): string {
  const lines = [
    "You are running inside GeeAgent through the agent runtime.",
    "Treat the session as a real multi-step task runtime.",
    "Observe, decide, act, and continue until the task is complete or blocked by approval.",
    "Do not ask the user to type 'continue' for ordinary operator work.",
    "Use built-in shell and file tools when needed.",
    "When the user asks you to inspect local machine state, use GeeAgent's Bash tool for read-only checks instead of telling the user to run a terminal command.",
    "Local machine state includes ports, processes, files, directories, command availability, local services, repository state, build output, and test output.",
    "If the latest user request asks for local machine state, you MUST call an appropriate tool before answering. A response that says you cannot directly inspect is incorrect unless the host denies or withholds the tool.",
    "Do not use SDK WebSearch or WebFetch in GeeAgent. When current public web information is needed, use Bash with an inspectable command such as curl, python urllib, or another local CLI, so the host can show and approve the exact operation.",
    "Do not use TodoWrite or maintain a separate SDK todo list; GeeAgent owns task and approval state at the host layer.",
    "Gee's default specialty and preset task domain are not code development. Unless the user explicitly asks you to develop, fix, refactor, or edit code, do not modify local project source code or configuration as the way to satisfy a request.",
    "If a task needs scripting, data processing, inspection helpers, or a temporary automation program, you may write and run that code as an implementation detail, but do not turn ordinary app control, file management, research, or configuration requests into edits to the user's local codebase.",
  ];

  if (context) {
    lines.push("", "[Runtime Context]");
    if (context.localTime) {
      lines.push(`- Local time: ${context.localTime}`);
    }
    if (context.timezone) {
      lines.push(`- Timezone: ${context.timezone}`);
    }
    if (context.surface) {
      lines.push(`- Surface: ${context.surface}`);
    }
    if (context.cwd) {
      lines.push(`- Workspace cwd: ${context.cwd}`);
    }
    if (context.approvalPosture) {
      lines.push(`- Approval posture: ${context.approvalPosture}`);
    }
    if (context.capabilities && context.capabilities.length > 0) {
      lines.push(`- Host capabilities: ${context.capabilities.join(", ")}`);
    }
  }

  if (sessionPrompt && sessionPrompt.trim().length > 0) {
    lines.push("", "[GeeAgent Session Prompt]", sessionPrompt.trim());
  }

  return lines.join("\n");
}

function normalizeToolInput(input: unknown): Record<string, unknown> {
  if (input && typeof input === "object" && !Array.isArray(input)) {
    return input as Record<string, unknown>;
  }
  return {};
}

function sanitizeToolInput(
  toolName: string,
  input: unknown,
): Record<string, unknown> {
  const normalized = { ...normalizeToolInput(input) };
  if (toolName === "Read" && normalized.pages === "") {
    delete normalized.pages;
  }
  return normalized;
}

function summarizeToolResultContent(content: unknown): string | undefined {
  if (typeof content === "string") {
    const trimmed = content.trim();
    return trimmed.length > 0 ? trimmed : undefined;
  }

  if (Array.isArray(content)) {
    const text = content
      .map((item) => {
        if (
          item &&
          typeof item === "object" &&
          "type" in item &&
          (item as { type?: unknown }).type === "text" &&
          "text" in item
        ) {
          const value = (item as { text?: unknown }).text;
          return typeof value === "string" ? value : "";
        }
        return "";
      })
      .filter((value) => value.trim().length > 0)
      .join("\n");

    if (text.trim().length > 0) {
      return text.trim();
    }
  }

  if (content && typeof content === "object") {
    return JSON.stringify(content);
  }

  return undefined;
}

export class ClaudeRuntimeSession {
  public readonly sessionId: string;

  private readonly emit: (event: RuntimeEvent) => void;
  private readonly config: SessionConfig;
  private readonly pendingApprovals = new Map<string, PendingApproval>();
  private readonly queuedMessages: string[] = [];
  private readonly sdkSession: SDKSession;
  private listening = false;
  private closed = false;

  constructor(config: SessionConfig, emit: (event: RuntimeEvent) => void) {
    this.sessionId = config.sessionId;
    this.config = config;
    this.emit = emit;
    this.sdkSession = unstable_v2_createSession({
      cwd: config.cwd,
      model: config.model,
      pathToClaudeCodeExecutable: claudeCodeExecutablePath(),
      ...(config.availableTools ? { tools: config.availableTools } : {}),
      allowedTools: config.autoApproveTools,
      disallowedTools: config.disallowedTools,
      env: {
        ...process.env,
        ANTHROPIC_BASE_URL: config.gatewayBaseUrl,
        ANTHROPIC_API_KEY: config.gatewayApiKey,
        CLAUDE_AGENT_SDK_CLIENT_APP: "geeagent/agent-runtime",
      },
      canUseTool: async (toolName: string, input: unknown) => {
        const normalizedInput = sanitizeToolInput(toolName, input);

        if (config.autoApproveTools.includes(toolName)) {
          return {
            behavior: "allow",
            updatedInput: normalizedInput,
          };
        }

        const requestId = randomUUID();
        this.emit({
          type: "session.approval_requested",
          sessionId: this.sessionId,
          requestId,
          toolName,
          input: normalizedInput,
        });

        const decision = await new Promise<ApprovalDecision>((resolve, reject) => {
          this.pendingApprovals.set(requestId, { resolve, reject });
        });

        if (decision.decision === "allow") {
          return {
            behavior: "allow",
            updatedInput: decision.updatedInput ?? normalizedInput,
          };
        }

        return {
          behavior: "deny",
          message: decision.message ?? "GeeAgent host denied this tool request.",
        };
      },
    });
  }

  send(content: string): void {
    if (this.closed) {
      throw new Error(`session ${this.sessionId} is already closed`);
    }

    const runtimePrompt = buildSystemPrompt(
      this.config.systemPrompt,
      this.config.runtimeContext,
    );
    this.queuedMessages.push(
      runtimePrompt.trim().length > 0
        ? `${runtimePrompt}\n\n[GeeAgent Turn]\n${content}`
        : content,
    );
    if (!this.listening) {
      void this.startListening();
    }
  }

  resolveApproval(
    requestId: string,
    decision: ApprovalDecision,
  ): void {
    const pending = this.pendingApprovals.get(requestId);
    if (!pending) {
      throw new Error(
        `session ${this.sessionId} has no pending approval ${requestId}`,
      );
    }
    this.pendingApprovals.delete(requestId);
    pending.resolve(decision);
  }

  close(): void {
    if (this.closed) {
      return;
    }

    this.closed = true;
    this.sdkSession.close();

    for (const [requestId, pending] of this.pendingApprovals) {
      pending.reject(
        new Error(`session ${this.sessionId} closed while waiting for approval ${requestId}`),
      );
    }
    this.pendingApprovals.clear();
  }

  private async startListening(): Promise<void> {
    if (this.listening || this.closed) {
      return;
    }
    this.listening = true;

    try {
      while (!this.closed && this.queuedMessages.length > 0) {
        const nextMessage = this.queuedMessages.shift();
        if (!nextMessage) {
          continue;
        }

        await this.sdkSession.send(nextMessage);
        for await (const message of this.sdkSession.stream()) {
          if (this.handleSdkMessage(message)) {
            break;
          }
        }
      }
    } catch (error) {
      this.emit({
        type: "session.error",
        sessionId: this.sessionId,
        error: error instanceof Error ? error.message : String(error),
      });
    } finally {
      this.listening = false;
      if (!this.closed && this.queuedMessages.length > 0) {
        void this.startListening();
      }
    }
  }

  private handleSdkMessage(message: SDKMessage): boolean {
    if (message?.type === "system") {
      this.emit({
        type: "session.system",
        sessionId: this.sessionId,
        subtype: message.subtype,
        sessionSdkId: message.session_id,
        raw: message,
      });
      return false;
    }

    if (message?.type === "assistant") {
      const blocks = Array.isArray(message.message.content) ? message.message.content : [];

      for (const block of blocks) {
        if (block?.type === "text") {
          this.emit({
            type: "session.assistant_text",
            sessionId: this.sessionId,
            text: block.text,
            raw: block,
          });
        } else if (block?.type === "tool_use") {
          this.emit({
            type: "session.tool_use",
            sessionId: this.sessionId,
            toolUseId: block.id,
            toolName: block.name,
            input: sanitizeToolInput(block.name, block.input),
            raw: block,
          });
        }
      }
      return false;
    }

    if (message?.type === "user") {
      const blocks = Array.isArray(message.message.content) ? message.message.content : [];

      for (const block of blocks) {
        if (block?.type === "tool_result") {
          const summary = summarizeToolResultContent(block.content);
          const isError = Boolean(block.is_error);
          this.emit({
            type: "session.tool_result",
            sessionId: this.sessionId,
            toolUseId: block.tool_use_id,
            status: isError ? "failed" : "succeeded",
            summary,
            error: isError ? summary ?? "Tool execution failed." : undefined,
            raw: block,
          });
        }
      }

      this.emit({
        type: "session.user",
        sessionId: this.sessionId,
        raw: message,
      });
      return false;
    }

    if (message?.type === "result") {
      const resultText =
        message.subtype === "success" && typeof message.result === "string"
          ? message.result
          : undefined;
      this.emit({
        type: "session.result",
        sessionId: this.sessionId,
        subtype: message.subtype,
        durationMs: message.duration_ms,
        totalCostUsd: message.total_cost_usd,
        result: resultText,
        raw: message,
      });
      return true;
    }

    return false;
  }
}

export const __sessionTestHooks = {
  buildSystemPrompt,
  normalizeToolInput,
  sanitizeToolInput,
  summarizeToolResultContent,
};
