import { randomUUID } from "node:crypto";

import {
  createSdkMcpServer,
  tool,
  unstable_v2_createSession,
  type SDKMessage,
  type SDKSession,
} from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod/v4";

import type {
  RuntimeHostActionCompletion,
  RuntimeHostActionIntent,
  RuntimeContext,
  RuntimeEvent,
} from "./protocol.js";

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
  enableGeeHostTools?: boolean;
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

type PendingHostAction = {
  resolve: (completion: RuntimeHostActionCompletion) => void;
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
    "Do not use SDK WebSearch or WebFetch in GeeAgent. When current public web information is needed, use Bash with an inspectable command such as curl, python3 urllib, or another local CLI, so the host can show and approve the exact operation.",
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
    if (context.capabilities?.includes("gee_host_bridge")) {
      lines.push(
        "- Gee Gear controls are available through the host bridge. If `mcp__gee__gear_list_capabilities`, `mcp__gee__gear_invoke`, or `mcp__gee__app_open_surface` are visible as callable tools, use them progressively and inspect each structured result before deciding the next step.",
      );
      lines.push(
        "- If those MCP tools are not visible in this SDK session, do not inspect source code or claim the bridge is unavailable. Instead emit exactly one `<gee-host-actions>` directive and no user-facing prose. GeeAgent will execute it in the native host, then resume this same task with structured results.",
      );
      lines.push(
        '- Host-action directive shape: `<gee-host-actions>{"actions":[{"tool_id":"gee.gear.listCapabilities","arguments":{"detail":"summary"}}]}</gee-host-actions>`. Allowed `tool_id` values are `gee.app.openSurface`, `gee.gear.listCapabilities`, and `gee.gear.invoke`.',
      );
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

function compactRecord(record: Record<string, unknown>): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(record).filter(([, value]) => value !== undefined),
  );
}

function hostActionId(toolID: string): string {
  return `sdk_host_action_${toolID.replace(/[^a-z0-9]+/gi, "_")}_${randomUUID().slice(0, 8)}`;
}

function parseHostActionResultJSON(raw: string): unknown {
  try {
    return JSON.parse(raw);
  } catch {
    return raw;
  }
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
  private readonly pendingHostActions = new Map<string, PendingHostAction>();
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
      ...(config.enableGeeHostTools === false
        ? {}
        : { mcpServers: { gee: this.createGeeHostMcpServer() } }),
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

  resolveHostAction(
    hostActionId: string,
    completion: RuntimeHostActionCompletion,
  ): void {
    const pending = this.pendingHostActions.get(hostActionId);
    if (!pending) {
      throw new Error(
        `session ${this.sessionId} has no pending host action ${hostActionId}`,
      );
    }
    this.pendingHostActions.delete(hostActionId);
    pending.resolve(completion);
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

    for (const [hostActionId, pending] of this.pendingHostActions) {
      pending.reject(
        new Error(`session ${this.sessionId} closed while waiting for host action ${hostActionId}`),
      );
    }
    this.pendingHostActions.clear();
  }

  private createGeeHostMcpServer() {
    return createSdkMcpServer({
      name: "gee",
      version: "1.0.0",
      tools: [
        tool(
          "app_open_surface",
          "Open a Gee app or Gear surface by id. Use this before invoking a Gear when the user expects the native app window/surface to be visible.",
          {
            gear_id: z.string().optional(),
            surface_id: z.string().optional(),
            module_id: z.string().optional(),
          },
          async (args) => this.callGeeHostAction("gee.app.openSurface", compactRecord(args)),
        ),
        tool(
          "gear_list_capabilities",
          "Progressively disclose enabled Gee Gear capabilities. Use detail='summary' first, then detail='capabilities' for one gear_id, then detail='schema' for one capability_id.",
          {
            detail: z.enum(["summary", "capabilities", "schema"]).optional(),
            gear_id: z.string().optional(),
            capability_id: z.string().optional(),
          },
          async (args) => this.callGeeHostAction("gee.gear.listCapabilities", compactRecord(args)),
        ),
        tool(
          "gear_invoke",
          "Invoke one enabled Gee Gear capability through the native macOS host bridge. Inspect the structured result before choosing the next step.",
          {
            gear_id: z.string(),
            capability_id: z.string(),
            args: z.record(z.string(), z.unknown()).optional(),
          },
          async (args) =>
            this.callGeeHostAction("gee.gear.invoke", {
              gear_id: args.gear_id,
              capability_id: args.capability_id,
              args: args.args ?? {},
            }),
        ),
      ],
    });
  }

  private async callGeeHostAction(
    toolID: string,
    args: Record<string, unknown>,
  ) {
    const completion = await this.requestGeeHostAction({
      host_action_id: hostActionId(toolID),
      tool_id: toolID,
      arguments: args,
    });
    const payload = {
      host_action_id: completion.host_action_id,
      tool_id: completion.tool_id,
      status: completion.status,
      ...(completion.summary ? { summary: completion.summary } : {}),
      ...(completion.error ? { error: completion.error } : {}),
      ...(completion.result_json
        ? { result: parseHostActionResultJSON(completion.result_json) }
        : {}),
    };
    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify(payload, null, 2),
        },
      ],
      isError: completion.status === "failed",
    };
  }

  private requestGeeHostAction(
    hostAction: RuntimeHostActionIntent,
  ): Promise<RuntimeHostActionCompletion> {
    if (this.closed) {
      return Promise.reject(
        new Error(`session ${this.sessionId} is already closed`),
      );
    }

    this.emit({
      type: "session.host_action_requested",
      sessionId: this.sessionId,
      hostAction,
    });

    return new Promise((resolve, reject) => {
      this.pendingHostActions.set(hostAction.host_action_id, { resolve, reject });
    });
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
