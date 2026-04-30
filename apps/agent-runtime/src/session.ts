import { randomUUID } from "node:crypto";
import { mkdirSync } from "node:fs";
import { join } from "node:path";

import {
  createSdkMcpServer,
  query,
  tool,
  unstable_v2_createSession,
  type SDKMessage,
  type SDKUserMessage,
} from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod/v4";

import type {
  RuntimeHostActionCompletion,
  RuntimeHostActionIntent,
  RuntimeContext,
  RuntimeEvent,
} from "./protocol.js";
import {
  gearCapabilityContracts,
  validateGearCapabilityArgs,
  type GearCapabilityValidationResult,
} from "./native-runtime/capabilities/gear-validation.js";
import { prepareHostActionCompletionsForModel } from "./native-runtime/context/host-action-results.js";
import {
  mergeDeterministicArgsForCapability,
  type RuntimeRunPlan,
} from "./native-runtime/turns/planning.js";
import {
  normalizeGeeGearInvokeInput,
  normalizeToolBoundaryInput,
  normalizeToolInput,
  preToolUseBoundaryOutput,
} from "./tool-boundary-gateway.js";
import {
  DEFAULT_SDK_AVAILABLE_TOOLS,
  isGeeHostSdkTool,
} from "./sdk-tool-policy.js";

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
  artifactRoot: string;
  gatewayBaseUrl: string;
  gatewayApiKey: string;
  toolBoundaryMode?: "default" | "gear_first";
  runPlan?: RuntimeRunPlan | null;
  sdkSessionFactory?: RuntimeSdkSessionFactory;
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

type RuntimeBootstrapState = "not_sent" | "queued" | "sent";

type QueuedRuntimeMessage = {
  content: string;
  includeRuntimeBootstrap: boolean;
};

type RuntimeSdkSession = {
  send(content: string): void;
  stream(): AsyncIterable<SDKMessage>;
  close(): void;
};

type RuntimeSdkSessionFactory = (
  options: Parameters<typeof unstable_v2_createSession>[0],
) => RuntimeSdkSession;

class AsyncMessageQueue<T> implements AsyncIterable<T> {
  private readonly values: T[] = [];
  private readonly waiters: Array<(result: IteratorResult<T>) => void> = [];
  private closed = false;

  enqueue(value: T): void {
    if (this.closed) {
      return;
    }
    const waiter = this.waiters.shift();
    if (waiter) {
      waiter({ done: false, value });
      return;
    }
    this.values.push(value);
  }

  done(): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    for (const waiter of this.waiters.splice(0)) {
      waiter({ done: true, value: undefined as T });
    }
  }

  [Symbol.asyncIterator](): AsyncIterator<T> {
    return {
      next: () => {
        const value = this.values.shift();
        if (value !== undefined) {
          return Promise.resolve({ done: false, value });
        }
        if (this.closed) {
          return Promise.resolve({ done: true, value: undefined as T });
        }
        return new Promise<IteratorResult<T>>((resolve) => {
          this.waiters.push(resolve);
        });
      },
    };
  }
}

function sdkUserMessage(content: string): SDKUserMessage {
  return {
    type: "user",
    session_id: "",
    message: {
      role: "user",
      content: [{ type: "text", text: content }],
    },
    parent_tool_use_id: null,
  };
}

function createQueryBackedSession(
  options: Parameters<typeof unstable_v2_createSession>[0],
): RuntimeSdkSession {
  const input = new AsyncMessageQueue<SDKUserMessage>();
  const session = query({
    prompt: input,
    options,
  });
  const iterator = session[Symbol.asyncIterator]();
  let closed = false;

  return {
    send(content: string): void {
      if (closed) {
        throw new Error("SDK query session is already closed");
      }
      input.enqueue(sdkUserMessage(content));
    },
    async *stream(): AsyncIterable<SDKMessage> {
      while (!closed) {
        const next = await iterator.next();
        if (next.done) {
          return;
        }
        yield next.value;
        if (next.value.type === "result") {
          return;
        }
      }
    },
    close(): void {
      if (closed) {
        return;
      }
      closed = true;
      input.done();
      session.close();
    },
  };
}

function claudeCodeExecutablePath(): string | undefined {
  const path = process.env.GEEAGENT_CLAUDE_CODE_EXECUTABLE?.trim();
  return path && path.length > 0 ? path : undefined;
}

function claudeConfigDir(artifactRoot: string): string {
  return join(artifactRoot, "ClaudeConfig");
}

function sanitizedSdkEnvironment(
  config: Pick<SessionConfig, "artifactRoot" | "gatewayApiKey" | "gatewayBaseUrl">,
) {
  const env = { ...process.env };
  for (const key of Object.keys(env)) {
    const upper = key.toUpperCase();
    if (upper.startsWith("CLAUDE") || upper.startsWith("ANTHROPIC")) {
      delete env[key];
    }
  }

  const configDir = claudeConfigDir(config.artifactRoot);
  mkdirSync(configDir, { recursive: true });
  return {
    ...env,
    ANTHROPIC_BASE_URL: config.gatewayBaseUrl,
    ANTHROPIC_API_KEY: config.gatewayApiKey,
    CLAUDE_AGENT_SDK_CLIENT_APP: "geeagent/agent-runtime",
    CLAUDE_CONFIG_DIR: configDir,
  };
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
    "Do not use SDK Agent, Task, or subagent delegation tools in GeeAgent's main runtime. GeeAgent owns delegation, worktree isolation, and task state at the host layer.",
    "Gee's default specialty and preset task domain are not code development. Unless the user explicitly asks you to develop, fix, refactor, or edit code, do not modify local project source code or configuration as the way to satisfy a request.",
    "If a task needs scripting, data processing, inspection helpers, or a temporary automation program, you may write and run that code as an implementation detail, but do not turn ordinary app control, file management, research, or configuration requests into edits to the user's local codebase.",
    "Do not use fallback task execution paths. If the intended tool, Gear, provider, permission, or session continuation is unavailable, report the real failed or degraded state instead of switching to another route or presenting partial work as complete.",
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
        "- Gee Gear controls are available through the host bridge. If `mcp__gee__gear_list_capabilities`, `mcp__gee__gear_invoke`, or `mcp__gee__app_open_surface` are visible as callable tools, use them deliberately and inspect each structured result before deciding the next step.",
      );
      lines.push(
        "- For requests that match an installed Gear or built-in app, use the Gee Gear bridge as the execution path. Do not inspect GeeAgent source files, call SDK Skill aliases, or use Bash to discover product internals unless the user explicitly asks to debug GeeAgent itself.",
      );
      lines.push(
        "- WeChat article and album URLs (`mp.weixin.qq.com/s/...` and `mp.weixin.qq.com/mp/appmsgalbum?...`) belong to the installed WeSpy Reader Gear (`wespy.reader`). Use the Gear bridge first for fetching or listing those pages; use Bash/file tools only after the Gear returns structured results and the user asked for local composition, copying, or saving.",
      );
      lines.push(
        "- If those MCP tools are not visible in this SDK session, report the missing Gee host bridge as a runtime failure. Do not emit text control directives, do not inspect source code as a substitute, and do not claim the task is complete.",
      );
      lines.push(
        "- Use progressive Gear disclosure: first call `mcp__gee__gear_list_capabilities` with `detail: \"summary\"` plus any runtime-provided `focus_gear_ids`, `focus_capability_ids`, `run_plan_id`, and `stage_id`; then inspect specific capabilities only when the focused summary is insufficient. When the summary already contains the needed capability id and required args, invoke the capability directly instead of re-reading every schema.",
      );
      lines.push(
        "- Never call `gee.gear.invoke` with guessed or empty required arguments. If required arguments are not known from the latest user request, recent assistant result, or a specific Gear schema, read the schema or report the missing argument as a real blockage.",
      );
      lines.push(renderGearCapabilityContractHints());
      lines.push(
        '- For direct `mcp__gee__gear_invoke` tool calls, pass `gear_id`, `capability_id`, and `args` directly, for example `{"gear_id":"wespy.reader","capability_id":"wespy.fetch_article","args":{"url":"https://mp.weixin.qq.com/s/..."}}`. Only raw host-action directives use a `tool_id` plus `arguments` envelope.',
      );
      lines.push(
        "- Treat a user Gear request as complete only when the user's full objective is complete, not when one atomic Gear call succeeds. If a Gear result reveals that another Gear step is required, continue the same task with another Gee host-action directive.",
      );
      lines.push(
        "- For X/Twitter bookmark requests, do not stop after `twitter.capture/twitter.fetch_tweet`. If the user asks to preserve media or the tweet strongly implies media acquisition, continue through `smartyt.media/smartyt.download_now`, then `media.library/media.import_files`, then `bookmark.vault/bookmark.save` with `local_media_paths`. Remote media URLs are only media candidates; they are not saved local media files unless a download/import capability returns local paths.",
      );
      lines.push(
        "- For WeChat article requests that ask to save Markdown to a local destination, first fetch with `wespy.reader`, then use the returned file/artifact paths to complete the requested local save or clearly report the missing step.",
      );
    }
  }

  if (sessionPrompt && sessionPrompt.trim().length > 0) {
    lines.push("", "[GeeAgent Session Prompt]", sessionPrompt.trim());
  }

  return lines.join("\n");
}

function renderGearCapabilityContractHints(): string {
  const lines = gearCapabilityContracts().map((contract) => {
    const required = contract.required_args
      .map((requirement) => {
        const details: string[] = [requirement.kind];
        if (requirement.aliases.length > 1) {
          details.push(`aliases: ${requirement.aliases.join(", ")}`);
        }
        return `args.${requirement.field} (${details.join("; ")})`;
      })
      .join(", ");
    return `  - ${contract.gear_id}/${contract.capability_id}: ${required}`;
  });
  return [
    "- Known Gee Gear required args:",
    ...lines,
  ].join("\n");
}

function sdkSessionBootstrapPrompt(
  config: Pick<SessionConfig, "systemPrompt" | "runtimeContext">,
): string {
  return buildSystemPrompt(config.systemPrompt, config.runtimeContext);
}

function runtimeUserMessage(content: string, runtimePrompt?: string): string {
  const trimmedPrompt = runtimePrompt?.trim() ?? "";
  if (trimmedPrompt.length > 0) {
    return `${trimmedPrompt}\n\n[GeeAgent Turn]\n${content}`;
  }
  return content;
}

function sanitizeToolInput(
  toolName: string,
  input: unknown,
  runPlan?: RuntimeRunPlan | null,
): Record<string, unknown> {
  const normalized = normalizeToolBoundaryInput(toolName, input);
  return mergeDeterministicGearInvokeInput(toolName, normalized, runPlan);
}

function compactRecord(record: Record<string, unknown>): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(record).filter(([, value]) => value !== undefined),
  );
}

function shallowRecordEqual(left: Record<string, unknown>, right: Record<string, unknown>): boolean {
  const leftEntries = Object.entries(left);
  const rightEntries = Object.entries(right);
  if (leftEntries.length !== rightEntries.length) {
    return false;
  }
  return leftEntries.every(([key, value]) => Object.is(value, right[key]));
}

function hostActionId(toolID: string): string {
  return `sdk_host_action_${toolID.replace(/[^a-z0-9]+/gi, "_")}_${randomUUID().slice(0, 8)}`;
}

function gearCapabilityValidationToolResult(
  toolID: string,
  gearID: string,
  capabilityID: string,
  args: Record<string, unknown>,
  validation: Extract<GearCapabilityValidationResult, { ok: false }>,
) {
  const payload = {
    tool_id: toolID,
    status: "failed",
    code: validation.code,
    error: validation.message,
    gear_id: gearID,
    capability_id: capabilityID,
    args,
    retry_hint:
      "Inspect the Gear schema and retry with the missing argument inside args.",
  };
  return {
    content: [
      {
        type: "text" as const,
        text: JSON.stringify(payload, null, 2),
      },
    ],
    isError: true,
  };
}

function gearInvokeArgumentErrorToolResult(input: {
  gearID: string;
  capabilityID: string;
  args: Record<string, unknown>;
  code: string;
  message: string;
}) {
  const payload = {
    tool_id: "gee.gear.invoke",
    status: "failed",
    code: input.code,
    error: input.message,
    gear_id: input.gearID,
    capability_id: input.capabilityID,
    args: input.args,
    retry_hint:
      "Use the current runtime plan's deterministic capability_args or provide a non-conflicting value inside args.",
  };
  return {
    content: [
      {
        type: "text" as const,
        text: JSON.stringify(payload, null, 2),
      },
    ],
    isError: true,
  };
}

function mergeDeterministicGearInvokeInput(
  toolName: string,
  input: Record<string, unknown>,
  runPlan?: RuntimeRunPlan | null,
): Record<string, unknown> {
  if (
    toolName !== "mcp__gee__gear_invoke" &&
    toolName !== "gear_invoke" &&
    toolName !== "gee.gear.invoke"
  ) {
    return input;
  }
  const gearID = typeof input.gear_id === "string" ? input.gear_id : "";
  const capabilityID = typeof input.capability_id === "string" ? input.capability_id : "";
  const args =
    input.args && typeof input.args === "object" && !Array.isArray(input.args)
      ? (input.args as Record<string, unknown>)
      : {};
  const merged = mergeDeterministicArgsForCapability(
    runPlan,
    gearID,
    capabilityID,
    args,
  );
  if (!merged.ok) {
    return input;
  }
  return {
    ...input,
    args: merged.args,
  };
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
  private runPlan: RuntimeRunPlan | null;
  private readonly pendingApprovals = new Map<string, PendingApproval>();
  private readonly pendingHostActions = new Map<string, PendingHostAction>();
  private readonly queuedMessages: QueuedRuntimeMessage[] = [];
  private readonly sdkSession: RuntimeSdkSession;
  private runtimeBootstrapState: RuntimeBootstrapState = "not_sent";
  private requestedGeeHostAction = false;
  private listening = false;
  private closed = false;

  constructor(config: SessionConfig, emit: (event: RuntimeEvent) => void) {
    this.sessionId = config.sessionId;
    this.config = config;
    this.runPlan = config.runPlan ?? null;
    this.emit = emit;
    const availableTools = config.availableTools ?? DEFAULT_SDK_AVAILABLE_TOOLS;
    const sdkOptions = {
      cwd: config.cwd,
      model: config.model,
      pathToClaudeCodeExecutable: claudeCodeExecutablePath(),
      tools: availableTools,
      ...(config.enableGeeHostTools === false
        ? {}
        : { mcpServers: { gee: this.createGeeHostMcpServer() } }),
      allowedTools: config.autoApproveTools,
      disallowedTools: config.disallowedTools,
      env: sanitizedSdkEnvironment(config),
      canUseTool: async (toolName: string, input: unknown) => {
        const normalizedInput = sanitizeToolInput(toolName, input, this.runPlan);
        const boundaryDenial = this.toolBoundaryDenial(toolName);
        if (boundaryDenial) {
          return {
            behavior: "deny",
            message: boundaryDenial,
          };
        }

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
	      hooks: {
        PreToolUse: [
          {
            hooks: [
              async (input) => this.preToolUseBoundaryOutput(input) ?? { continue: true },
            ],
          },
        ],
      },
    } as Parameters<typeof unstable_v2_createSession>[0] & { tools: string[] };
    this.sdkSession = (config.sdkSessionFactory ?? createQueryBackedSession)(sdkOptions);
  }

  send(content: string): void {
    if (this.closed) {
      throw new Error(`session ${this.sessionId} is already closed`);
    }

    const includeRuntimeBootstrap = this.runtimeBootstrapState === "not_sent";
    if (includeRuntimeBootstrap) {
      this.runtimeBootstrapState = "queued";
    }
    this.queuedMessages.push({ content, includeRuntimeBootstrap });
    if (!this.listening) {
      void this.startListening();
    }
  }

  updateRunPlan(runPlan: RuntimeRunPlan | null): void {
    this.runPlan = runPlan;
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

  private toolBoundaryDenial(toolName: string): string | null {
    if (this.config.toolBoundaryMode !== "gear_first") {
      return null;
    }
    if (this.requestedGeeHostAction) {
      return null;
    }
    if (isGeeHostToolName(toolName)) {
      return null;
    }
    return (
      "This turn is a Gee Gear task. GeeAgent requires the active SDK run to " +
      "use the Gee MCP Gear bridge before any shell, file, skill, or source " +
      "inspection tools. The request was blocked so bridge/tool problems are " +
      "exposed instead of hidden by fallback probing."
    );
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
          "List enabled Gee Gear capabilities. Use detail='summary' first, scoped by runtime-provided focus_gear_ids/focus_capability_ids when available. Invoke directly when the focused summary contains the needed capability and required args. Request detail='schema' only when optional arguments or exact types are unclear.",
          {
            detail: z.enum(["summary", "capabilities", "schema"]).optional(),
            gear_id: z.string().optional(),
            capability_id: z.string().optional(),
            focus_gear_ids: z.array(z.string()).optional(),
            focus_capability_ids: z.array(z.string()).optional(),
            run_plan_id: z.string().optional(),
            stage_id: z.string().optional(),
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
            arguments: z
              .object({
                gear_id: z.string().optional(),
                capability_id: z.string().optional(),
                args: z.record(z.string(), z.unknown()).optional(),
              })
              .passthrough()
              .optional(),
          },
          async (args) => {
            const normalized = mergeDeterministicGearInvokeInput(
              "gear_invoke",
              normalizeGeeGearInvokeInput(compactRecord(args)),
              this.runPlan,
            );
            const gearID = typeof normalized.gear_id === "string" ? normalized.gear_id : "";
            const capabilityID =
              typeof normalized.capability_id === "string" ? normalized.capability_id : "";
            const gearArgs =
              normalized.args &&
              typeof normalized.args === "object" &&
              !Array.isArray(normalized.args)
                ? (normalized.args as Record<string, unknown>)
                : {};
            const merged = mergeDeterministicArgsForCapability(
              this.runPlan,
              gearID,
              capabilityID,
              gearArgs,
            );
            if (!merged.ok) {
              return gearInvokeArgumentErrorToolResult({
                gearID,
                capabilityID,
                args: gearArgs,
                code: merged.code,
                message: merged.message,
              });
            }
            const validation = validateGearCapabilityArgs(
              gearID,
              capabilityID,
              merged.args,
            );
            if (!validation.ok) {
              return gearCapabilityValidationToolResult(
                "gee.gear.invoke",
                gearID,
                capabilityID,
                merged.args,
                validation,
              );
            }
            return this.callGeeHostAction("gee.gear.invoke", {
              gear_id: gearID,
              capability_id: capabilityID,
              args: merged.args,
            });
          },
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
    const prepared = await prepareHostActionCompletionsForModel(
      [completion],
      this.config.artifactRoot,
    );
    const payload = prepared.completions[0] ?? {
      host_action_id: completion.host_action_id,
      tool_id: completion.tool_id,
      status: completion.status,
      ...(completion.summary ? { summary: completion.summary } : {}),
      ...(completion.error ? { error: completion.error } : {}),
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

  private preToolUseBoundaryOutput(input: unknown): ReturnType<typeof preToolUseBoundaryOutput> {
    const output = preToolUseBoundaryOutput(input);
    if (!input || typeof input !== "object" || Array.isArray(input)) {
      return output;
    }
    const record = input as Record<string, unknown>;
    if (record.hook_event_name !== "PreToolUse") {
      return output;
    }
    const toolName = typeof record.tool_name === "string" ? record.tool_name : "";
    const originalInput = normalizeToolInput(record.tool_input);
    const normalizedInput = sanitizeToolInput(toolName, originalInput, this.runPlan);
    if (shallowRecordEqual(originalInput, normalizedInput)) {
      return output;
    }
    return {
      continue: true,
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        updatedInput: normalizedInput,
      },
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
    this.requestedGeeHostAction = true;

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

        try {
          await this.sendQueuedMessage(nextMessage);
          let sawStreamEvent = false;
          for await (const message of this.sdkSession.stream()) {
            if (nextMessage.includeRuntimeBootstrap && !sawStreamEvent) {
              this.runtimeBootstrapState = "sent";
            }
            sawStreamEvent = true;
            if (this.handleSdkMessage(message)) {
              break;
            }
          }
          if (nextMessage.includeRuntimeBootstrap && !sawStreamEvent) {
            this.forgetUnconfirmedBootstrap(nextMessage);
          }
        } catch (error) {
          this.forgetUnconfirmedBootstrap(nextMessage);
          throw error;
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

  private async sendQueuedMessage(message: QueuedRuntimeMessage): Promise<void> {
    const runtimePrompt = message.includeRuntimeBootstrap
      ? sdkSessionBootstrapPrompt(this.config)
      : undefined;
    await this.sdkSession.send(runtimeUserMessage(message.content, runtimePrompt));
  }

  private forgetUnconfirmedBootstrap(message: QueuedRuntimeMessage): void {
    if (!message.includeRuntimeBootstrap || this.runtimeBootstrapState === "sent") {
      return;
    }
    this.runtimeBootstrapState = "not_sent";
    this.promoteNextQueuedBootstrap();
  }

  private promoteNextQueuedBootstrap(): void {
    if (this.runtimeBootstrapState !== "not_sent") {
      return;
    }
    const nextMessage = this.queuedMessages[0];
    if (!nextMessage || nextMessage.includeRuntimeBootstrap) {
      return;
    }
    nextMessage.includeRuntimeBootstrap = true;
    this.runtimeBootstrapState = "queued";
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
            input: sanitizeToolInput(block.name, block.input, this.runPlan),
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

function isGeeHostToolName(toolName: string): boolean {
  return (
    isGeeHostSdkTool(toolName) ||
    [
      "gee.app.openSurface",
      "gee.gear.listCapabilities",
      "gee.gear.invoke",
    ].includes(toolName)
  );
}

export const __sessionTestHooks = {
  buildSystemPrompt,
  claudeConfigDir,
  isGeeHostToolName,
  normalizeToolInput,
  preToolUseBoundaryOutput,
  runtimeUserMessage,
  sanitizeToolInput,
  sanitizedSdkEnvironment,
  sdkSessionBootstrapPrompt,
  summarizeToolResultContent,
  gearCapabilityContracts,
  validateGearCapabilityArgs,
};
