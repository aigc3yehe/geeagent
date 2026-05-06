import {
  loadXenodiaGatewayBackend,
  type XenodiaGatewayBackend,
} from "../chat-runtime.js";
import { randomUUID } from "node:crypto";
import { join } from "node:path";
import {
  startAnthropicGateway,
  type AnthropicGatewayHandle,
} from "../gateway.js";
import type {
  RuntimeEvent,
  RuntimeContext,
  RuntimeHostActionCompletion,
  RuntimeHostActionIntent,
} from "../protocol.js";
import {
  DEFAULT_SDK_AVAILABLE_TOOLS,
  DEFAULT_SDK_AUTO_APPROVE_TOOLS,
  DEFAULT_SDK_DISALLOWED_TOOLS,
  isGeeHostSdkTool,
} from "../sdk-tool-policy.js";
import { ClaudeRuntimeSession } from "../session.js";
import {
  sdkRuntimeBashScope,
  terminalAccessDecisionForScope,
  type TerminalAccessScope,
} from "./store/terminal-permissions.js";
import type { AgentProfile } from "./store/types.js";
import { loadSecurityPreferences } from "./store/persistence.js";
import { skillPromptMetadataForProfile } from "./store/skill-sources.js";
import { resolveConfigDir, runtimeProjectPath } from "./paths.js";
import {
  materializeToolResult,
  type ToolArtifactRef,
} from "./context/tool-artifacts.js";
import { prepareHostActionCompletionsForModel } from "./context/host-action-results.js";
import { normalizeGearInvokeArgumentsEnvelope } from "./tools/args.js";
import {
  gearCapabilityContracts,
  validateGearCapabilityArgs,
  type GearCapabilityValidationResult,
} from "./capabilities/gear-validation.js";
import {
  capabilityFocusArgsForPlan,
  capabilityFocusForStage,
  currentRuntimePlanStage,
  mergeDeterministicArgsForCapability,
  renderRuntimeRunPlanForPrompt,
  type RuntimeRunPlan,
} from "./turns/planning.js";

export type TurnRoute = {
  mode: "quick_prompt" | "workspace_message";
  source: "quick_input" | "workspace_chat" | "telegram.bridge";
  surface: "cli_quick_input" | "cli_workspace_chat" | "telegram";
};

export type SdkToolEvent =
  | {
      kind: "invocation";
      invocation_id: string;
      tool_name: string;
      input_summary?: string;
    }
  | {
      kind: "result";
      invocation_id: string;
      status: "succeeded" | "failed";
      summary?: string;
      error?: string;
      artifacts?: SdkToolArtifactRef[];
    };

export type SdkToolArtifactRef = {
  artifactId: string;
  type: string;
  title: string;
  payloadRef: string;
  inlinePreviewSummary?: string;
};

export type PendingTerminalApproval = {
  runtime_session_id: string;
  runtime_request_id: string;
  scope: TerminalAccessScope;
  command: string;
  cwd?: string;
  input_summary?: string;
};

export type SdkTurnResult = {
  assistant_chunks: string[];
  host_action_control_chunks?: string[];
  final_result?: string;
  tool_events: SdkToolEvent[];
  auto_approved_tools: number;
  failed_reason?: string;
  pending_terminal_approval?: PendingTerminalApproval;
  pending_host_actions?: RuntimeHostActionIntent[];
  pending_host_action_mode?: "mcp" | "directive";
  terminal_access_denied_reason?: string;
};

type ManagedSession = {
  session: ClaudeRuntimeSession;
  events: RuntimeEvent[];
  waiters: Array<(event: RuntimeEvent) => void>;
  toolBoundaryMode: "default" | "gear_first";
  runPlan?: RuntimeRunPlan | null;
  toolInvocationCount?: number;
  pendingHostActionMode?: "mcp" | "directive";
};

type RuntimeTurnOptions = {
  availableTools?: string[];
  autoApproveTools?: string[];
  disallowedTools?: string[];
  enableGeeHostTools?: boolean;
  eventIdleTimeoutMs?: number;
  toolBoundaryMode?: "default" | "gear_first";
  runPlan?: RuntimeRunPlan | null;
  onAssistantText?: (delta: string) => void | Promise<void>;
  onToolEvent?: (event: SdkToolEvent) => void | Promise<void>;
};

const ITERATIVE_TURN_MAX_STEPS = 8;
const DEFAULT_SDK_EVENT_IDLE_TIMEOUT_MS = 75_000;

const sessions = new Map<string, ManagedSession>();
let gateway: AnthropicGatewayHandle | null = null;
let gatewayKey = "";

export async function runSdkRuntimeTurn(
  configDir: string,
  runtimeSessionId: string,
  route: TurnRoute,
  activeProfile: AgentProfile,
  prompt: string,
  transientAllowedTerminalScopes: TerminalAccessScope[] = [],
  options: RuntimeTurnOptions = {},
): Promise<SdkTurnResult> {
  const managed = await ensureSession(configDir, runtimeSessionId, route, activeProfile, options);
  managed.runPlan = options.runPlan ?? managed.runPlan ?? null;
  managed.session.updateRunPlan(managed.runPlan);
  const turn = emptyTurnResult();
  managed.session.send(
    options.toolBoundaryMode === "gear_first"
      ? gearFirstTurnPrompt(prompt, options.runPlan ?? null)
      : prompt,
  );
  try {
    await collectEventsUntilPauseOrResult(
      configDir,
      managed,
      runtimeSessionId,
      transientAllowedTerminalScopes,
      turn,
      options.onToolEvent,
      options.onAssistantText,
      options.eventIdleTimeoutMs,
      options.toolBoundaryMode ?? "default",
      options.runPlan ?? null,
    );
    closeUnfinishedToolEventsOnFailure(turn);
    rememberPendingHostActionMode(managed, turn);
  } finally {
    closeCompletedManagedSession(runtimeSessionId, managed, turn);
    await recycleGatewayAfterFailedTurn(turn);
  }
  return turn;
}

export async function resumeSdkRuntimeApproval(
  runtimeSessionId: string,
  runtimeRequestId: string,
  decision: "allow" | "deny",
): Promise<SdkTurnResult> {
  const managed = sessions.get(runtimeSessionId);
  if (!managed) {
    throw new Error(
      "The paused SDK runtime session is no longer alive, so GeeAgent cannot resume this approval inside the same run.",
    );
  }
  const turn = emptyTurnResult();
  managed.session.resolveApproval(runtimeRequestId, {
    decision,
    message:
      decision === "deny"
        ? "GeeAgent terminal permission review denied this Bash request."
        : undefined,
  });
  try {
    await collectEventsUntilPauseOrResult(
      undefined,
      managed,
      runtimeSessionId,
      [],
      turn,
      undefined,
      undefined,
      undefined,
      managed.toolBoundaryMode,
      managed.runPlan ?? null,
    );
    closeUnfinishedToolEventsOnFailure(turn);
    rememberPendingHostActionMode(managed, turn);
  } finally {
    closeCompletedManagedSession(runtimeSessionId, managed, turn);
    await recycleGatewayAfterFailedTurn(turn);
  }
  return turn;
}

export async function resumeSdkRuntimeHostActions(
  configDir: string,
  runtimeSessionId: string,
  completions: RuntimeHostActionCompletion[],
  eventIdleTimeoutMs?: number,
  onAssistantText?: (delta: string) => void | Promise<void>,
): Promise<SdkTurnResult | null> {
  const managed = sessions.get(runtimeSessionId);
  if (!managed) {
    return null;
  }
  const turn = emptyTurnResult();
  if (managed.pendingHostActionMode === "mcp") {
    for (const completion of completions) {
      managed.session.resolveHostAction(completion.host_action_id, completion);
    }
  } else {
    managed.session.send(
      await composeHostActionContinuationPrompt(
        completions,
        toolArtifactRoot(configDir),
      ),
    );
  }
  try {
    await collectEventsUntilPauseOrResult(
      configDir,
      managed,
      runtimeSessionId,
      [],
      turn,
      undefined,
      onAssistantText,
      eventIdleTimeoutMs,
      managed.toolBoundaryMode,
      managed.runPlan ?? null,
    );
    closeUnfinishedToolEventsOnFailure(turn);
    rememberPendingHostActionMode(managed, turn);
  } finally {
    closeCompletedManagedSession(runtimeSessionId, managed, turn);
    await recycleGatewayAfterFailedTurn(turn);
  }
  return turn;
}

export function updateSdkRuntimeRunPlan(
  runtimeSessionId: string,
  runPlan: RuntimeRunPlan,
): void {
  const managed = sessions.get(runtimeSessionId);
  if (managed) {
    managed.runPlan = runPlan;
    managed.session.updateRunPlan(runPlan);
  }
}

export function closeSdkRuntimeSession(runtimeSessionId: string): void {
  const managed = sessions.get(runtimeSessionId);
  if (managed) {
    closeManagedSession(runtimeSessionId, managed);
  }
}

export async function shutdownSdkRuntime(): Promise<void> {
  for (const managed of sessions.values()) {
    managed.session.close();
  }
  sessions.clear();

  if (gateway) {
    await gateway.close();
    gateway = null;
    gatewayKey = "";
  }
}

function emptyTurnResult(): SdkTurnResult {
  return {
    assistant_chunks: [],
    tool_events: [],
    auto_approved_tools: 0,
  };
}

function gearFirstTurnPrompt(prompt: string, runPlan: RuntimeRunPlan | null = null): string {
  const discoveryArgs = JSON.stringify(capabilityFocusArgsForPlan(runPlan));
  return [
    "[GeeAgent Gear-First Execution Boundary]",
    "This turn has been classified as a Gee Gear or built-in app task.",
    `Your first assistant action in this turn must be a direct tool call to \`mcp__gee__gear_list_capabilities\` with arguments \`${discoveryArgs}\`.`,
    "Do not write prose before that first Gee MCP tool call.",
    "Do not infer Gee bridge availability from previous transcript messages, previous failures, or local files. The current SDK session must test the current bridge by calling the Gee MCP tool.",
    "After the focused summary returns, continue with the smallest necessary Gee MCP Gear calls to complete the current plan stage and then the user's full objective.",
    "When the active runtime plan later advances to a stage with no Gear focus or required Gear capability, continue that planned stage with the normal approved SDK tools such as Bash for inspectable local or web research.",
    "Do not request an unscoped full capability summary while the plan has a locked focus set. Reopen discovery only for a listed trigger in the runtime plan.",
    "If the Gee MCP tool is unavailable or fails, report that structured runtime failure. Do not use shell, file, source-inspection, web, skill, directive, or other fallback paths before the Gee MCP call.",
    "",
    renderRuntimeRunPlanForPrompt(runPlan),
    "",
    "[Original Turn Prompt]",
    prompt,
  ].join("\n");
}

async function ensureSession(
  configDir: string,
  sessionId: string,
  route: TurnRoute,
  activeProfile: AgentProfile,
  options: RuntimeTurnOptions = {},
): Promise<ManagedSession> {
  const existing = sessions.get(sessionId);
  if (existing) {
    const nextToolBoundaryMode = options.toolBoundaryMode ?? "default";
    if (existing.toolBoundaryMode === nextToolBoundaryMode) {
      existing.runPlan = options.runPlan ?? existing.runPlan ?? null;
      return existing;
    }
    closeManagedSession(sessionId, existing);
  }

  const backend = await loadXenodiaGatewayBackend(configDir);
  const activeGateway = await ensureGateway(backend);
  const runtimeFacts = captureRuntimeFacts(route.surface);
  const security = await loadSecurityPreferences(configDir);
  const availableTools = options.availableTools ?? DEFAULT_SDK_AVAILABLE_TOOLS;
  const disallowedTools = options.disallowedTools ?? DEFAULT_SDK_DISALLOWED_TOOLS;
  const autoApproveTools = sdkAutoApproveToolsForSecurity({
    requestedAutoApproveTools: options.autoApproveTools ?? DEFAULT_SDK_AUTO_APPROVE_TOOLS,
    availableTools,
    disallowedTools,
    highestAuthorizationEnabled: security.highest_authorization_enabled,
    toolBoundaryMode: options.toolBoundaryMode ?? "default",
  });
  const hostCapabilities = [
    "bash",
    "read",
    "write",
    "edit",
    "grep",
    "glob",
    "ls",
  ];
  if (options.enableGeeHostTools ?? true) {
    hostCapabilities.push("gee_host_bridge");
  }

  let managed: ManagedSession;
  const session = new ClaudeRuntimeSession(
    {
      sessionId,
      cwd: runtimeProjectPath(runtimeFacts.cwd),
      model: "sonnet",
      maxTurns: ITERATIVE_TURN_MAX_STEPS,
      systemPrompt: await activeAgentSystemPrompt(configDir, activeProfile),
      runtimeContext: {
        localTime: runtimeFacts.localTime,
        timezone: runtimeFacts.timezone,
        surface: route.surface,
        cwd: runtimeFacts.cwd,
        approvalPosture: security.highest_authorization_enabled
          ? "highest_authorization"
          : "gee_terminal_permissions",
        capabilities: hostCapabilities,
      } satisfies RuntimeContext,
      availableTools,
      autoApproveTools,
      disallowedTools,
      enableGeeHostTools: options.enableGeeHostTools ?? true,
      toolBoundaryMode: options.toolBoundaryMode ?? "default",
      runPlan: options.runPlan ?? null,
      artifactRoot: toolArtifactRoot(configDir),
      gatewayBaseUrl: activeGateway.baseUrl,
      gatewayApiKey: activeGateway.apiKey,
    },
    (event) => emitToManagedSession(managed, event),
  );

  managed = {
    session,
    events: [],
    waiters: [],
    toolBoundaryMode: options.toolBoundaryMode ?? "default",
    runPlan: options.runPlan ?? null,
    toolInvocationCount: 0,
  };
  sessions.set(sessionId, managed);
  managed.events.push({
    type: "session.created",
    sessionId,
    model: "sonnet",
    cwd: runtimeFacts.cwd,
  });
  return managed;
}

function sdkAutoApproveToolsForSecurity(input: {
  requestedAutoApproveTools: string[];
  availableTools: string[];
  disallowedTools: string[];
  highestAuthorizationEnabled: boolean;
  toolBoundaryMode: "default" | "gear_first";
}): string[] {
  const disallowed = new Set(input.disallowedTools);
  const baseTools = input.requestedAutoApproveTools.filter((tool) => !disallowed.has(tool));
  const allowed = new Set<string>(
    input.toolBoundaryMode === "gear_first"
      ? baseTools.filter(isGeeHostSdkTool)
      : baseTools,
  );

  if (input.highestAuthorizationEnabled && input.toolBoundaryMode !== "gear_first") {
    for (const tool of input.availableTools) {
      if (!disallowed.has(tool)) {
        allowed.add(tool);
      }
    }
  }

  return Array.from(allowed);
}

async function ensureGateway(
  backend: XenodiaGatewayBackend,
): Promise<AnthropicGatewayHandle> {
  const nextKey = JSON.stringify({
    apiKey: backend.api_key,
    url: backend.chat_completions_url,
    model: backend.model,
    timeout: backend.request_timeout_seconds,
    maxCompletionTokens: backend.max_completion_tokens,
    temperature: backend.temperature,
  });
  if (gateway && gatewayKey === nextKey) {
    return gateway;
  }
  if (gateway) {
    await gateway.close();
  }
  gateway = await startAnthropicGateway({
    xenodiaApiKey: backend.api_key,
    backendUrl: backend.chat_completions_url,
    modelOverride: backend.model,
    requestTimeoutSeconds: backend.request_timeout_seconds,
    maxCompletionTokens: backend.max_completion_tokens,
    temperature: backend.temperature,
  });
  gatewayKey = nextKey;
  return gateway;
}

async function recycleGatewayAfterFailedTurn(turn: SdkTurnResult): Promise<void> {
  if (!shouldRecycleGatewayAfterTurn(turn) || !gateway) {
    return;
  }
  const staleGateway = gateway;
  gateway = null;
  gatewayKey = "";
  try {
    await staleGateway.close();
  } catch {
    // Do not replace the real turn failure with a best-effort cleanup error.
  }
}

function shouldRecycleGatewayAfterTurn(turn: SdkTurnResult): boolean {
  return Boolean(turn.failed_reason?.trim()) && !turn.pending_terminal_approval;
}

function emitToManagedSession(managed: ManagedSession, event: RuntimeEvent): void {
  const waiter = managed.waiters.shift();
  if (waiter) {
    waiter(event);
    return;
  }
  managed.events.push(event);
}

function nextEventWithTimeout(
  managed: ManagedSession,
  timeoutMs: number,
): Promise<RuntimeEvent | null> {
  const event = managed.events.shift();
  if (event) {
    return Promise.resolve(event);
  }

  return new Promise((resolve) => {
    let settled = false;
    const waiter = (next: RuntimeEvent): void => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      resolve(next);
    };
    const timer = setTimeout(() => {
      if (settled) {
        return;
      }
      settled = true;
      const waiterIndex = managed.waiters.indexOf(waiter);
      if (waiterIndex >= 0) {
        managed.waiters.splice(waiterIndex, 1);
      }
      resolve(null);
    }, timeoutMs);
    managed.waiters.push(waiter);
  });
}

function closeManagedSession(sessionId: string, managed: ManagedSession): void {
  sessions.delete(sessionId);
  managed.session.close();
}

function closeCompletedManagedSession(
  sessionId: string,
  managed: ManagedSession,
  turn: SdkTurnResult,
): void {
  if (turn.pending_terminal_approval) {
    return;
  }
  if (turn.pending_host_actions && turn.pending_host_actions.length > 0) {
    return;
  }
  closeManagedSession(sessionId, managed);
}

function rememberPendingHostActionMode(
  managed: ManagedSession,
  turn: SdkTurnResult,
): void {
  if (turn.pending_host_actions && turn.pending_host_actions.length > 0) {
    managed.pendingHostActionMode = turn.pending_host_action_mode ?? "directive";
  } else {
    managed.pendingHostActionMode = undefined;
  }
}

async function composeHostActionContinuationPrompt(
  completions: RuntimeHostActionCompletion[],
  artifactRoot: string,
): Promise<string> {
  const prepared = await prepareHostActionCompletionsForModel(
    completions,
    artifactRoot,
  );
  return [
    "[GeeAgent Host Action Results]",
    "Native Gee host actions completed. Inspect these structured results, then continue the same user task.",
    "Large native results may be represented as `result_artifact`; read the compact fields first and only use the artifact path if the full payload is needed.",
    "A successful atomic Gear result is not necessarily the completed user objective. If another Gear step is needed, use the Gee MCP Gear bridge tools in this same SDK run. If those tools are unavailable, report the missing bridge as a runtime failure instead of emitting text control directives or claiming completion.",
    "Never call `gee.gear.invoke` with guessed or empty required arguments. Use the local paths, URLs, IDs, or other concrete values returned by the prior structured result; when a required argument is still unknown, inspect the capability schema or report the missing argument as a real blockage.",
    "If the runtime plan has advanced to a stage with no Gear focus or required Gear capability, use normal approved SDK tools for that planned model/research work; that is not a fallback for a Gear stage.",
    renderGearCapabilityContractHints(),
    "For X/Twitter bookmark requests that include media preservation, continue from tweet capture to `smartyt.media/smartyt.download_now`, then `media.library/media.import_files`, then `bookmark.vault/bookmark.save` with `local_media_paths`; remote media URLs are media candidates, not saved local files.",
    "",
    JSON.stringify(prepared, null, 2),
  ].join("\n");
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
    "Known Gee Gear required args:",
    ...lines,
  ].join("\n");
}

function sdkEventIdleTimeoutMs(overrideMs?: number): number {
  if (overrideMs !== undefined && Number.isFinite(overrideMs) && overrideMs >= 5_000) {
    return overrideMs;
  }
  const raw = Number.parseInt(process.env.GEEAGENT_SDK_EVENT_IDLE_TIMEOUT_MS ?? "", 10);
  if (Number.isFinite(raw) && raw >= 5_000) {
    return raw;
  }
  return DEFAULT_SDK_EVENT_IDLE_TIMEOUT_MS;
}

function sdkEventIdleTimeoutReason(timeoutMs: number): string {
  return (
    `The SDK runtime produced no new event for ${Math.ceil(timeoutMs / 1000)} seconds. ` +
    "GeeAgent stopped this run instead of leaving the conversation loading forever."
  );
}

async function collectEventsUntilPauseOrResult(
  configDir: string | undefined,
  managed: ManagedSession,
  sessionId: string,
  transientAllowedTerminalScopes: TerminalAccessScope[],
  turn: SdkTurnResult,
  onToolEvent?: (event: SdkToolEvent) => void | Promise<void>,
  onAssistantText?: (delta: string) => void | Promise<void>,
  eventIdleTimeoutMs?: number,
  toolBoundaryMode: "default" | "gear_first" = "default",
  runPlan: RuntimeRunPlan | null = null,
): Promise<void> {
  const toolInputsById = new Map<string, SeenSdkToolInvocation>();
  const assistantControlFilter = createAssistantControlTextFilter();
  const idleTimeoutMs = sdkEventIdleTimeoutMs(eventIdleTimeoutMs);
  while (true) {
    const event = await nextEventWithTimeout(managed, idleTimeoutMs);
    if (!event) {
      turn.failed_reason = sdkEventIdleTimeoutReason(idleTimeoutMs);
      closeManagedSession(sessionId, managed);
      return;
    }
    switch (event.type) {
      case "session.approval_requested": {
        const toolName = event.toolName;
        const input = normalizeRecord(event.input);
        const boundaryViolation = gearFirstBoundaryViolationReason(
          toolBoundaryMode,
          toolName,
          runPlan,
        );
        if (boundaryViolation) {
          turn.failed_reason = boundaryViolation;
          managed.session.resolveApproval(event.requestId, {
            decision: "deny",
            message: boundaryViolation,
          });
          closeManagedSession(sessionId, managed);
          return;
        }
        if (configDir && (await loadSecurityPreferences(configDir)).highest_authorization_enabled) {
          turn.auto_approved_tools += 1;
          managed.session.resolveApproval(event.requestId, { decision: "allow" });
          continue;
        }

        if (isAutoApprovedReadOnlySdkTool(toolName)) {
          turn.auto_approved_tools += 1;
          managed.session.resolveApproval(event.requestId, { decision: "allow" });
          continue;
        }

        if (toolName === "Bash") {
          const bash = sdkBashRequestFromInput(input);
          const command = bash?.command ?? "Bash tool request";
          const cwd = bash?.cwd;
          const scope = sdkRuntimeBashScope(command, cwd);
          const transientAllow = transientAllowedTerminalScopes.some((allowed) =>
            scopesEqual(allowed, scope),
          );
          const decision = transientAllow
            ? "allow"
            : configDir
              ? await terminalAccessDecisionForScope(configDir, scope)
              : undefined;

          if (decision === "allow") {
            turn.auto_approved_tools += 1;
            managed.session.resolveApproval(event.requestId, { decision: "allow" });
            continue;
          }
          if (decision === "deny") {
            turn.terminal_access_denied_reason =
              `GeeAgent terminal permissions blocked this command: ${terminalInputSummary(command, cwd)}`;
            managed.session.resolveApproval(event.requestId, {
              decision: "deny",
              message: "GeeAgent terminal permissions deny this Bash request.",
            });
            continue;
          }

          turn.pending_terminal_approval = {
            runtime_session_id: sessionId,
            runtime_request_id: event.requestId,
            scope,
            command,
            ...(cwd ? { cwd } : {}),
            input_summary: terminalInputSummary(command, cwd),
          };
          return;
        }

        managed.session.resolveApproval(event.requestId, {
          decision: "deny",
          message:
            unsupportedToolDenialMessage(toolName),
        });
        continue;
      }
      case "session.host_action_requested":
        turn.pending_host_actions = [
          ...(turn.pending_host_actions ?? []),
          event.hostAction,
        ];
        turn.pending_host_action_mode = "mcp";
        return;
      case "session.tool_use":
        let toolInputForEvent: Record<string, unknown>;
        {
          const input = normalizeSdkGearInvokeInput(
            event.toolName,
            normalizeRecord(event.input),
            runPlan,
          );
          toolInputForEvent = input;
          const boundaryViolation = gearFirstBoundaryViolationReason(
            toolBoundaryMode,
            event.toolName,
            runPlan,
          );
          const firstToolViolation = gearFirstFirstToolViolationReason(
            toolBoundaryMode,
            event.toolName,
            (managed.toolInvocationCount ?? 0) === 0,
          );
          const focusViolation = gearFirstCapabilityFocusViolationReason(
            toolBoundaryMode,
            event.toolName,
            input,
            runPlan,
            (managed.toolInvocationCount ?? 0) === 0,
          );
          const invokeViolation = gearFirstInvokeFocusViolationReason(
            toolBoundaryMode,
            event.toolName,
            input,
            runPlan,
          );
          const violation =
            boundaryViolation ?? firstToolViolation ?? focusViolation ?? invokeViolation;
          if (violation) {
            turn.failed_reason = violation;
            closeManagedSession(sessionId, managed);
            return;
          }
          toolInputsById.set(event.toolUseId, {
            tool_name: event.toolName,
            input,
          });
        }
        managed.toolInvocationCount = (managed.toolInvocationCount ?? 0) + 1;
        const toolEvent: SdkToolEvent = {
          kind: "invocation",
          invocation_id: event.toolUseId,
          tool_name: event.toolName,
          input_summary: summarizePrompt(JSON.stringify(toolInputForEvent), 180),
        };
        turn.tool_events.push(toolEvent);
        await onToolEvent?.(toolEvent);
        continue;
      case "session.tool_result": {
        const normalized = await normalizeSdkToolResult(
          configDir,
          event,
          toolInputsById.get(event.toolUseId),
        );
        const toolEvent: SdkToolEvent = {
          kind: "result",
          invocation_id: event.toolUseId,
          status: normalized.status,
          ...(normalized.summary ? { summary: summarizePrompt(normalized.summary, 220) } : {}),
          ...(normalized.error ? { error: summarizePrompt(normalized.error, 220) } : {}),
          ...(normalized.artifacts.length > 0 ? { artifacts: normalized.artifacts } : {}),
        };
        turn.tool_events.push(toolEvent);
        await onToolEvent?.(toolEvent);
        continue;
      }
      case "session.assistant_text": {
        const partition = assistantControlFilter.push(event.text);
        if (partition.controlText.trim()) {
          turn.host_action_control_chunks = [
            ...(turn.host_action_control_chunks ?? []),
            partition.controlText.trim(),
          ];
        }
        const visibleText = stripAssistantStageProgressText(partition.visibleText);
        const trimmed = visibleText.trim();
        if (trimmed) {
          turn.assistant_chunks.push(trimmed);
          await onAssistantText?.(visibleText);
        }
        continue;
      }
      case "session.result":
        {
          const flushed = assistantControlFilter.flush();
          if (flushed.controlText.trim()) {
            turn.host_action_control_chunks = [
              ...(turn.host_action_control_chunks ?? []),
              flushed.controlText.trim(),
            ];
          }
          const visibleText = stripAssistantStageProgressText(flushed.visibleText);
          if (visibleText.trim()) {
            turn.assistant_chunks.push(visibleText.trim());
            await onAssistantText?.(visibleText);
          }
        }
        if (event.result?.trim()) {
          turn.final_result = event.result.trim();
        }
        if (isRecord(event.raw) && event.raw.is_error === true) {
          turn.failed_reason = turn.final_result ?? "The SDK returned an error result.";
        }
        if (!turn.failed_reason) {
          const hostActionDirective = extractHostActionDirectiveResult(
            hostActionDirectiveChunksForTurn(turn),
          );
          if (hostActionDirective.errors.length > 0) {
            turn.failed_reason = hostActionDirectiveFailureReason(
              hostActionDirective.errors,
            );
            turn.pending_host_actions = undefined;
          } else if (
            toolBoundaryMode === "gear_first" &&
            hostActionDirective.actions.length > 0
          ) {
            turn.failed_reason =
              "Gear-first turns must use the Gee MCP Gear bridge. Text host-action directives are disabled because they are a legacy fallback route.";
            turn.pending_host_actions = undefined;
          } else if (hostActionDirective.actions.length > 0) {
            turn.pending_host_actions = hostActionDirective.actions;
            turn.pending_host_action_mode = "directive";
          }
        }
        if (!turn.failed_reason) {
          const missingBridgeReason = gearFirstMissingBridgeResultReason(
            toolBoundaryMode,
            turn,
            runPlan,
          );
          if (missingBridgeReason) {
            turn.failed_reason = missingBridgeReason;
          }
        }
        return;
      case "session.error":
        turn.failed_reason = event.error;
        return;
      default:
        continue;
    }
  }
}

type SeenSdkToolInvocation = {
  tool_name: string;
  input: Record<string, unknown>;
};

type SdkToolResultEvent = Extract<RuntimeEvent, { type: "session.tool_result" }>;

async function normalizeSdkToolResult(
  configDir: string | undefined,
  event: SdkToolResultEvent,
  invocation: SeenSdkToolInvocation | undefined,
): Promise<{
  status: "succeeded" | "failed";
  summary?: string;
  error?: string;
  artifacts: SdkToolArtifactRef[];
}> {
  if (isExpectedNoMatchLsofResult(event, invocation)) {
    return {
      status: "succeeded",
      summary: "No matching listening process was found.",
      artifacts: [],
    };
  }
  const materialized = await materializeToolResult({
    artifactRoot: toolArtifactRoot(configDir),
    invocationId: event.toolUseId,
    toolName: invocation?.tool_name,
    status: event.status,
    result: event.summary,
    error: event.error,
    summary: event.status === "failed" ? event.error : event.summary,
  });
  const displaySummary = materialized.materialized
    ? materialized.summary
    : event.summary;
  const displayError = event.error
    ? materialized.materialized
      ? materialized.summary
      : event.error
    : undefined;
  return {
    status: materialized.status,
    ...(displaySummary ? { summary: displaySummary } : {}),
    ...(displayError ? { error: displayError } : {}),
    artifacts: materialized.artifact ? [sdkArtifactRefFromToolArtifact(materialized.artifact)] : [],
  };
}

function toolArtifactRoot(configDir: string | undefined): string {
  return join(resolveConfigDir(configDir), "Artifacts");
}

function sdkArtifactRefFromToolArtifact(artifact: ToolArtifactRef): SdkToolArtifactRef {
  const titleTool = artifact.tool_name?.trim() || "Tool";
  return {
    artifactId: artifact.artifact_id,
    type: artifact.kind,
    title: `${titleTool} ${artifact.status === "failed" ? "error output" : "output"}`,
    payloadRef: artifact.path,
    inlinePreviewSummary: artifact.summary,
  };
}

function isExpectedNoMatchLsofResult(
  event: SdkToolResultEvent,
  invocation: SeenSdkToolInvocation | undefined,
): boolean {
  if (event.status !== "failed" || invocation?.tool_name !== "Bash") {
    return false;
  }
  const bash = sdkBashRequestFromInput(invocation.input);
  if (!bash) {
    return false;
  }
  const command = bash.command.trim().replace(/\s+/g, " ");
  const resultText = (event.error ?? event.summary ?? "").trim();
  return (
    /^lsof(\s|$)/.test(command) &&
    /\s-sTCP:LISTEN(\s|$)/.test(command) &&
    /\s-iTCP(?::|\s|$)/.test(command) &&
    /^Exit code 1\.?$/i.test(resultText)
  );
}

async function activeAgentSystemPrompt(
  configDir: string,
  profile: AgentProfile,
): Promise<string> {
  const sections = [profile.personality_prompt.trim()];
  const skillMetadata = await skillPromptMetadataForProfile(configDir, profile);
  if (skillMetadata) {
    sections.push(skillMetadata);
  }
  return sections.map((section) => section.trim()).filter(Boolean).join("\n\n");
}

function captureRuntimeFacts(surface: string): {
  localTime: string;
  timezone: string;
  cwd: string;
  surface: string;
} {
  const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone || "local";
  return {
    localTime: new Date().toLocaleString(undefined, { timeZoneName: "short" }),
    timezone,
    cwd: runtimeProjectPath(),
    surface,
  };
}

function isAutoApprovedReadOnlySdkTool(_toolName: string): boolean {
  return false;
}

function isSdkWebLookupTool(toolName: string): boolean {
  const lowered = toolName.toLowerCase();
  return lowered === "websearch" || lowered === "webfetch";
}

function unsupportedToolDenialMessage(toolName: string): string {
  if (isSdkWebLookupTool(toolName)) {
    return (
      `GeeAgent does not approve \`${toolName}\` through the SDK web tool path. ` +
      "Use Bash with an inspectable command such as curl or python3 urllib so the host can show and approve the exact operation."
    );
  }
  return (
    `GeeAgent host policy does not directly approve \`${toolName}\` through this boundary yet. ` +
    "Use Bash for local shell/file work so it can go through the terminal permission review flow."
  );
}

function gearFirstBoundaryViolationReason(
  toolBoundaryMode: "default" | "gear_first",
  toolName: string,
  runPlan: RuntimeRunPlan | null = null,
): string | null {
  if (toolBoundaryMode !== "gear_first" || isGeeHostSdkTool(toolName)) {
    return null;
  }
  if (runPlan && !runtimePlanHasLockedFocus(runPlan)) {
    return null;
  }
  return (
    `Gear-first runtime boundary rejected \`${toolName}\` before any Gee MCP Gear bridge action. ` +
    "This request must expose the missing or unavailable Gear bridge instead of probing with shell, file, source-inspection, skill, web, or other fallback tools."
  );
}

function gearFirstFirstToolViolationReason(
  toolBoundaryMode: "default" | "gear_first",
  toolName: string,
  isFirstToolUse: boolean,
): string | null {
  if (
    toolBoundaryMode !== "gear_first" ||
    !isFirstToolUse ||
    isGeeGearListCapabilitiesTool(toolName)
  ) {
    return null;
  }
  return (
    `Gear-first runtime boundary rejected \`${toolName}\` as the first tool. ` +
    "The first Gear-first action must be focused capability discovery through `mcp__gee__gear_list_capabilities`."
  );
}

function gearFirstCapabilityFocusViolationReason(
  toolBoundaryMode: "default" | "gear_first",
  toolName: string,
  input: Record<string, unknown>,
  runPlan: RuntimeRunPlan | null,
  isFirstToolUse: boolean,
): string | null {
  if (
    toolBoundaryMode !== "gear_first" ||
    !runPlan ||
    !runtimePlanHasLockedFocus(runPlan) ||
    !isGeeGearListCapabilitiesTool(toolName)
  ) {
    return null;
  }

  const detail = (stringField(input, "detail") ?? "summary").trim();
  if (detail !== "summary") {
    return null;
  }

  const hasSpecificScope = Boolean(
    stringField(input, "gear_id")?.trim() ||
      stringField(input, "capability_id")?.trim(),
  );
  const hasMatchingFocus = listCapabilitiesInputMatchesRunPlanFocus(input, runPlan);
  const matchesCurrentStage = hasMatchingFocus &&
    stringField(input, "stage_id") === runPlan.current_stage_id;

  if (isFirstToolUse && !matchesCurrentStage) {
    return (
      "Gear-first focused capability discovery must include the runtime plan focus " +
      "`run_plan_id`, `stage_id`, `focus_gear_ids`, and `focus_capability_ids`."
    );
  }

  if (!isFirstToolUse && !hasSpecificScope && !hasMatchingFocus) {
    return (
      "Gear-first runtime boundary blocked an unscoped full capability summary after " +
      "the run plan already locked a focus set. Use the focused arguments from the plan, " +
      "inspect a specific Gear/capability, or report that the plan must be changed."
    );
  }

  return null;
}

function gearFirstInvokeFocusViolationReason(
  toolBoundaryMode: "default" | "gear_first",
  toolName: string,
  input: Record<string, unknown>,
  runPlan: RuntimeRunPlan | null,
): string | null {
  if (
    toolBoundaryMode !== "gear_first" ||
    !runPlan ||
    !isGeeGearInvokeTool(toolName)
  ) {
    return null;
  }
  const stage = currentRuntimePlanStage(runPlan);
  if (!stage || stage.required_capabilities.length === 0) {
    return null;
  }
  const envelope = normalizeGearInvokeArgumentsEnvelope(input);
  if (!envelope.ok) {
    return (
      `Gear-first runtime boundary rejected \`${toolName}\` before execution ` +
      `because its argument envelope is invalid (${envelope.code}): ${envelope.message}`
    );
  }
  const gearID = envelope.gear_id;
  const capabilityID = envelope.capability_id;
  const ref = gearID && capabilityID ? `${gearID}/${capabilityID}` : null;
  if (ref && stage.required_capabilities.includes(ref)) {
    return null;
  }
  return (
    `Gear-first runtime boundary rejected \`${toolName}\` for stage ` +
    `\`${stage.stage_id}\`. The current stage only allows required capability ` +
    `${stage.required_capabilities.join(", ")}. Advance or replan the runtime stage before invoking another Gear capability.`
  );
}

function runtimePlanHasLockedFocus(runPlan: RuntimeRunPlan): boolean {
  return (
    runPlan.focus.focus_gear_ids.length > 0 ||
    runPlan.focus.focus_capability_ids.length > 0
  );
}

function listCapabilitiesInputMatchesRunPlanFocus(
  input: Record<string, unknown>,
  runPlan: RuntimeRunPlan,
): boolean {
  const stageID = stringField(input, "stage_id");
  if (!stageID) {
    return false;
  }
  if (!runPlan.stages.some((stage) => stage.stage_id === stageID)) {
    return false;
  }
  const stageFocus = capabilityFocusForStage(runPlan, stageID);
  return (
    stringField(input, "run_plan_id") === runPlan.plan_id &&
    stringArrayContainsAll(stringArrayField(input, "focus_gear_ids"), stageFocus.focus_gear_ids) &&
    stringArrayContainsAll(
      stringArrayField(input, "focus_capability_ids"),
      stageFocus.focus_capability_ids,
    )
  );
}

function stringArrayContainsAll(actual: string[], expected: string[]): boolean {
  if (expected.length === 0) {
    return true;
  }
  const actualSet = new Set(actual);
  return expected.every((item) => actualSet.has(item));
}

function isGeeGearListCapabilitiesTool(toolName: string): boolean {
  return (
    toolName === "mcp__gee__gear_list_capabilities" ||
    toolName === "gear_list_capabilities" ||
    toolName === "gee.gear.listCapabilities"
  );
}

function isGeeGearInvokeTool(toolName: string): boolean {
  return (
    toolName === "mcp__gee__gear_invoke" ||
    toolName === "gear_invoke" ||
    toolName === "gee.gear.invoke"
  );
}

function isGeeAppOpenSurfaceTool(toolName: string): boolean {
  return (
    toolName === "mcp__gee__app_open_surface" ||
    toolName === "app_open_surface" ||
    toolName === "gee.app.openSurface"
  );
}

function normalizeSdkGearInvokeInput(
  toolName: string,
  input: Record<string, unknown>,
  runPlan: RuntimeRunPlan | null = null,
): Record<string, unknown> {
  if (!isGeeGearInvokeTool(toolName)) {
    return input;
  }
  const envelope = normalizeGearInvokeArgumentsEnvelope(input);
  if (!envelope.ok) {
    return input;
  }
  const merged = mergeDeterministicArgsForCapability(
    runPlan,
    envelope.gear_id,
    envelope.capability_id,
    envelope.args,
  );
  return {
    ...envelope.arguments,
    args: merged.ok ? merged.args : envelope.args,
  };
}

function turnUsedGeeHostBridge(turn: SdkTurnResult): boolean {
  if (turn.pending_host_actions && turn.pending_host_actions.length > 0) {
    return true;
  }
  return turn.tool_events.some(
    (event) => event.kind === "invocation" && isGeeHostSdkTool(event.tool_name),
  );
}

function turnUsedGeeHostExecution(turn: SdkTurnResult): boolean {
  if (turn.pending_host_actions && turn.pending_host_actions.length > 0) {
    return true;
  }
  return turn.tool_events.some(
    (event) =>
      event.kind === "invocation" &&
      (isGeeGearInvokeTool(event.tool_name) || isGeeAppOpenSurfaceTool(event.tool_name)),
  );
}

function gearFirstMissingBridgeResultReason(
  toolBoundaryMode: "default" | "gear_first",
  turn: SdkTurnResult,
  runPlan: RuntimeRunPlan | null,
): string | null {
  if (toolBoundaryMode !== "gear_first") {
    return null;
  }
  const usedBridge = turnUsedGeeHostBridge(turn);
  if (usedBridge && !runPlan && !turnUsedGeeHostExecution(turn)) {
    return (
      "Gear-first light turn ended after capability discovery without executing a Gear invocation or opening a Gear surface. " +
      "GeeAgent marked the run failed instead of treating capability discovery as task completion."
    );
  }
  if (usedBridge) {
    return null;
  }
  if (runPlan && !runtimePlanHasLockedFocus(runPlan)) {
    return null;
  }
  return (
    "Gear-first turn ended without requesting any Gee MCP Gear bridge action. " +
    "GeeAgent marked the run failed instead of treating a text-only response as completion."
  );
}

function closeUnfinishedToolEventsOnFailure(turn: SdkTurnResult): void {
  const reason = turn.failed_reason?.trim();
  if (!reason) {
    return;
  }
  const completed = new Set(
    turn.tool_events
      .filter((event) => event.kind === "result")
      .map((event) => event.invocation_id),
  );
  const openInvocations = turn.tool_events.filter(
    (event) => event.kind === "invocation" && !completed.has(event.invocation_id),
  );
  for (const event of openInvocations) {
    turn.tool_events.push({
      kind: "result",
      invocation_id: event.invocation_id,
      status: "failed",
      summary: "The tool did not return before the SDK run ended.",
      error: summarizePrompt(reason, 220),
    });
  }
}

function sdkBashRequestFromInput(
  input: Record<string, unknown>,
): { command: string; cwd?: string } | undefined {
  const command = stringField(input, "command")?.trim();
  if (!command) {
    return undefined;
  }
  const cwd =
    stringField(input, "cwd") ??
    stringField(input, "workdir") ??
    stringField(input, "working_directory");
  const trimmedCwd = cwd?.trim();
  return {
    command,
    ...(trimmedCwd ? { cwd: trimmedCwd } : {}),
  };
}

function terminalInputSummary(command: string, cwd: string | undefined): string {
  return summarizePrompt(cwd ? `${command} @ ${cwd}` : command, 180);
}

function scopesEqual(left: TerminalAccessScope, right: TerminalAccessScope): boolean {
  return JSON.stringify(left) === JSON.stringify(right);
}

function normalizeRecord(value: unknown): Record<string, unknown> {
  return isRecord(value) ? value : {};
}

type HostActionDirectiveValidationError = {
  action_index?: number;
  tool_id?: string;
  code: string;
  message: string;
};

type HostActionDirectiveExtraction = {
  sawDirective: boolean;
  actions: RuntimeHostActionIntent[];
  errors: HostActionDirectiveValidationError[];
};

function extractHostActionDirective(chunks: string[]): RuntimeHostActionIntent[] {
  return extractHostActionDirectiveResult(chunks).actions;
}

function extractHostActionDirectiveResult(chunks: string[]): HostActionDirectiveExtraction {
  const raw = chunks.join("\n");
  const jsonTexts = hostActionDirectiveJsonTexts(raw);
  if (jsonTexts.length === 0) {
    return { sawDirective: false, actions: [], errors: [] };
  }

  const actions: RuntimeHostActionIntent[] = [];
  const errors: HostActionDirectiveValidationError[] = [];

  for (const jsonText of jsonTexts) {
    let parsed: unknown;
    try {
      parsed = JSON.parse(jsonText);
    } catch {
      errors.push({
        code: "gee.host_actions.invalid_json",
        message: "Gee host-action directive JSON could not be parsed.",
      });
      continue;
    }

    const actionsValue = isRecord(parsed) && Array.isArray(parsed.actions)
      ? parsed.actions
      : Array.isArray(parsed)
        ? parsed
        : isRecord(parsed)
          ? [parsed]
          : [];

    if (actionsValue.length === 0) {
      errors.push({
        code: "gee.host_actions.empty",
        message: "Gee host-action directive did not include any supported actions.",
      });
      continue;
    }

    for (const value of actionsValue) {
      if (actions.length >= 8) {
        break;
      }
      const result = hostActionFromDirective(value, actions.length);
      if (result.action) {
        actions.push(result.action);
      }
      if (result.error) {
        errors.push(result.error);
      }
    }
  }

  return { sawDirective: true, actions, errors };
}

function hostActionDirectiveChunksForTurn(turn: SdkTurnResult): string[] {
  return [
    ...(turn.host_action_control_chunks ?? []),
    ...turn.assistant_chunks,
  ];
}

function partitionAssistantControlText(text: string): {
  visibleText: string;
  controlText: string;
  sawHostActionDirective: boolean;
} {
  const controlBlocks: string[] = [];
  let visibleText = text.replace(
    /<gee-host-actions>\s*[\s\S]*?\s*<\/gee-host-actions>/gi,
    (match) => {
      controlBlocks.push(match);
      return "";
    },
  );
  visibleText = visibleText.replace(
    /```gee-host-actions\s*[\s\S]*?```/gi,
    (match) => {
      controlBlocks.push(match);
      return "";
    },
  );

  return {
    visibleText,
    controlText: controlBlocks.join("\n"),
    sawHostActionDirective: controlBlocks.length > 0,
  };
}

function stripAssistantStageProgressText(text: string): string {
  return text
    .replace(
      /(^|[\n.])\s*(?:Stage complete|Stage completed)\s*:\s*[^.\n]*(?:\.\s*)?/gi,
      "$1",
    )
    .trimStart();
}

function createAssistantControlTextFilter(): {
  push(text: string): ReturnType<typeof partitionAssistantControlText>;
  flush(): ReturnType<typeof partitionAssistantControlText>;
} {
  let buffer = "";
  const openers = [
    { open: "<gee-host-actions>", close: "</gee-host-actions>" },
    { open: "```gee-host-actions", close: "```" },
  ];

  const partitionBuffered = (allowFlush: boolean): ReturnType<typeof partitionAssistantControlText> => {
    let visibleText = "";
    let controlText = "";
    let sawHostActionDirective = false;

    while (buffer.length > 0) {
      const lower = buffer.toLowerCase();
      const next = openers
        .map((pattern) => ({ ...pattern, index: lower.indexOf(pattern.open) }))
        .filter((candidate) => candidate.index >= 0)
        .sort((a, b) => a.index - b.index)[0];

      if (!next) {
        const keepLength = allowFlush ? 0 : trailingControlPrefixLength(buffer, openers.map((item) => item.open));
        visibleText += buffer.slice(0, buffer.length - keepLength);
        buffer = buffer.slice(buffer.length - keepLength);
        break;
      }

      visibleText += buffer.slice(0, next.index);
      const closeStart = lower.indexOf(next.close, next.index + next.open.length);
      if (closeStart < 0) {
        if (allowFlush) {
          controlText += buffer.slice(next.index);
          sawHostActionDirective = true;
          buffer = "";
        } else {
          buffer = buffer.slice(next.index);
        }
        break;
      }

      const closeEnd = closeStart + next.close.length;
      controlText += buffer.slice(next.index, closeEnd);
      sawHostActionDirective = true;
      buffer = buffer.slice(closeEnd);
    }

    return { visibleText, controlText, sawHostActionDirective };
  };

  return {
    push(text: string) {
      buffer += text;
      return partitionBuffered(false);
    },
    flush() {
      return partitionBuffered(true);
    },
  };
}

function trailingControlPrefixLength(buffer: string, openers: string[]): number {
  const lower = buffer.toLowerCase();
  const maxLength = Math.min(lower.length, Math.max(...openers.map((item) => item.length - 1)));
  for (let length = maxLength; length > 0; length -= 1) {
    const suffix = lower.slice(-length);
    if (openers.some((opener) => opener.startsWith(suffix))) {
      return length;
    }
  }
  return 0;
}

function hostActionDirectiveJsonTexts(raw: string): string[] {
  const jsonTexts: string[] = [];
  for (const pattern of [
    /<gee-host-actions>\s*([\s\S]*?)\s*<\/gee-host-actions>/gi,
    /```gee-host-actions\s*([\s\S]*?)```/gi,
  ]) {
    let match: RegExpExecArray | null;
    while ((match = pattern.exec(raw)) !== null) {
      const jsonText = match[1]?.trim();
      if (jsonText) {
        jsonTexts.push(jsonText);
      }
    }
  }
  return jsonTexts;
}

const ALLOWED_HOST_ACTION_TOOLS = new Set([
  "gee.app.openSurface",
  "gee.gear.listCapabilities",
  "gee.gear.invoke",
]);

function hostActionFromDirective(
  value: unknown,
  index: number,
): { action?: RuntimeHostActionIntent; error?: HostActionDirectiveValidationError } {
  if (!isRecord(value)) {
    return {
      error: {
        action_index: index,
        code: "gee.host_actions.invalid_action",
        message: `Gee host-action directive action ${index + 1} is not an object.`,
      },
    };
  }
  const toolID = stringField(value, "tool_id") ?? stringField(value, "tool");
  if (!toolID) {
    return {
      error: {
        action_index: index,
        code: "gee.host_actions.missing_tool",
        message: `Gee host-action directive action ${index + 1} is missing a supported tool_id.`,
      },
    };
  }
  if (!ALLOWED_HOST_ACTION_TOOLS.has(toolID)) {
    return {
      error: {
        action_index: index,
        tool_id: toolID,
        code: "gee.host_actions.unsupported_tool",
        message: `Gee host-action directive tool \`${toolID}\` is not supported by the native host bridge.`,
      },
    };
  }
  const rawArgs = recordField(value, "arguments") ?? recordField(value, "args") ?? {};
  const normalizedArgs = normalizeHostActionArguments(toolID, rawArgs);
  if (!normalizedArgs.ok) {
    return {
      error: {
        action_index: index,
        tool_id: toolID,
        code: normalizedArgs.code,
        message: normalizedArgs.message,
      },
    };
  }
  const args = normalizedArgs.args;
  const validation = validateHostActionDirectiveArgs(toolID, args);
  if (validation) {
    return {
      error: {
        action_index: index,
        tool_id: toolID,
        code: validation.code,
        message: validation.message,
      },
    };
  }
  const fingerprint = `${toolID}:${JSON.stringify(args)}:${index}`;
  return {
    action: {
      host_action_id: `host_action_directive_${stableHash(fingerprint)}_${randomUUID().slice(0, 8)}`,
      tool_id: toolID,
      arguments: args,
    },
  };
}

function validateHostActionDirectiveArgs(
  toolID: string,
  args: Record<string, unknown>,
): HostActionDirectiveValidationError | null {
  if (toolID !== "gee.gear.invoke") {
    return null;
  }

  const gearID = typeof args.gear_id === "string" ? args.gear_id : "";
  if (!gearID.trim()) {
    return {
      code: "gear.args.gear_id",
      message: "required string `gear_id` is missing for gee.gear.invoke.",
    };
  }

  const capabilityID =
    typeof args.capability_id === "string" ? args.capability_id : "";
  if (!capabilityID.trim()) {
    return {
      code: "gear.args.capability_id",
      message: "required string `capability_id` is missing for gee.gear.invoke.",
    };
  }

  const invokeArgs = recordField(args, "args") ?? {};
  const validation = validateGearCapabilityArgs(gearID, capabilityID, invokeArgs);
  return validation.ok ? null : gearDirectiveValidationError(validation);
}

function gearDirectiveValidationError(
  validation: Extract<GearCapabilityValidationResult, { ok: false }>,
): HostActionDirectiveValidationError {
  return {
    code: validation.code,
    message: validation.message,
  };
}

function hostActionDirectiveFailureReason(
  errors: HostActionDirectiveValidationError[],
): string {
  const details = errors
    .slice(0, 4)
    .map((error) => {
      const label = error.tool_id ? `${error.tool_id}: ` : "";
      return `${label}${error.message}`;
    })
    .join(" ");
  return `Gee host-action directive validation failed. ${details}`;
}

function normalizeHostActionArguments(
  toolID: string,
  args: Record<string, unknown>,
):
  | { ok: true; args: Record<string, unknown> }
  | { ok: false; code: string; message: string } {
  if (toolID !== "gee.gear.invoke") {
    return { ok: true, args };
  }

  const normalized = normalizeGearInvokeArgumentsEnvelope(args);
  if (!normalized.ok) {
    return normalized;
  }
  return { ok: true, args: normalized.arguments };
}

function recordField(value: Record<string, unknown>, key: string): Record<string, unknown> | undefined {
  const field = value[key];
  return isRecord(field) ? field : undefined;
}

function stableHash(value: string): string {
  let hash = 0;
  for (let index = 0; index < value.length; index += 1) {
    hash = (hash * 31 + value.charCodeAt(index)) >>> 0;
  }
  return hash.toString(16).padStart(8, "0");
}

function stringField(record: Record<string, unknown>, key: string): string | undefined {
  const value = record[key];
  return typeof value === "string" ? value : undefined;
}

function stringArrayField(record: Record<string, unknown>, key: string): string[] {
  const value = record[key];
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function summarizePrompt(prompt: string, maxLength: number): string {
  const trimmed = prompt.trim().replace(/\s+/g, " ");
  if (trimmed.length <= maxLength) {
    return trimmed;
  }
  return `${trimmed.slice(0, Math.max(0, maxLength - 1))}…`;
}

export const __sdkTurnRunnerTestHooks = {
  activeAgentSystemPrompt,
  closeUnfinishedToolEventsOnFailure,
  composeHostActionContinuationPrompt,
  sdkBashRequestFromInput,
  sdkAutoApproveToolsForSecurity,
  sdkEventIdleTimeoutMs,
  sdkEventIdleTimeoutReason,
  shouldRecycleGatewayAfterTurn,
  collectEventsUntilPauseOrResult,
  gearFirstTurnPrompt,
  gearFirstBoundaryViolationReason,
  gearFirstFirstToolViolationReason,
  gearFirstCapabilityFocusViolationReason,
  gearFirstMissingBridgeResultReason,
  normalizeSdkGearInvokeInput,
  turnUsedGeeHostExecution,
  turnUsedGeeHostBridge,
  unsupportedToolDenialMessage,
  extractHostActionDirective,
  extractHostActionDirectiveResult,
  createAssistantControlTextFilter,
  partitionAssistantControlText,
  stripAssistantStageProgressText,
  normalizeSdkToolResult,
  runtimeProjectPath,
  summarizePrompt,
  toolArtifactRoot,
};
