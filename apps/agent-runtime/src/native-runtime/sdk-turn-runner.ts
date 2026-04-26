import { readFile } from "node:fs/promises";
import { join } from "node:path";

import {
  loadXenodiaGatewayBackend,
  type XenodiaGatewayBackend,
} from "../chat-runtime.js";
import {
  startAnthropicGateway,
  type AnthropicGatewayHandle,
} from "../gateway.js";
import type { RuntimeEvent, RuntimeContext } from "../protocol.js";
import {
  DEFAULT_SDK_AUTO_APPROVE_TOOLS,
  DEFAULT_SDK_DISALLOWED_TOOLS,
} from "../sdk-tool-policy.js";
import { ClaudeRuntimeSession } from "../session.js";
import {
  sdkRuntimeBashScope,
  terminalAccessDecisionForScope,
  type TerminalAccessScope,
} from "./store/terminal-permissions.js";
import type { AgentProfile } from "./store/types.js";
import { loadSecurityPreferences } from "./store/persistence.js";
import { runtimeProjectPath } from "./paths.js";

export type TurnRoute = {
  mode: "quick_prompt" | "workspace_message";
  source: "quick_input" | "workspace_chat";
  surface: "cli_quick_input" | "cli_workspace_chat";
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
  final_result?: string;
  tool_events: SdkToolEvent[];
  auto_approved_tools: number;
  failed_reason?: string;
  pending_terminal_approval?: PendingTerminalApproval;
  terminal_access_denied_reason?: string;
};

type ManagedSession = {
  session: ClaudeRuntimeSession;
  events: RuntimeEvent[];
  waiters: Array<(event: RuntimeEvent) => void>;
};

const ITERATIVE_TURN_MAX_STEPS = 8;
const PERSONA_SKILL_PROMPT_CHAR_LIMIT = 20_000;
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
): Promise<SdkTurnResult> {
  const managed = await ensureSession(configDir, runtimeSessionId, route, activeProfile);
  const turn = emptyTurnResult();
  managed.session.send(prompt);
  try {
    await collectEventsUntilPauseOrResult(
      configDir,
      managed,
      runtimeSessionId,
      transientAllowedTerminalScopes,
      turn,
    );
    closeUnfinishedToolEventsOnFailure(turn);
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
    );
    closeUnfinishedToolEventsOnFailure(turn);
  } finally {
    closeCompletedManagedSession(runtimeSessionId, managed, turn);
    await recycleGatewayAfterFailedTurn(turn);
  }
  return turn;
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

async function ensureSession(
  configDir: string,
  sessionId: string,
  route: TurnRoute,
  activeProfile: AgentProfile,
): Promise<ManagedSession> {
  const existing = sessions.get(sessionId);
  if (existing) {
    return existing;
  }

  const backend = await loadXenodiaGatewayBackend(configDir);
  const activeGateway = await ensureGateway(backend);
  const runtimeFacts = captureRuntimeFacts(route.surface);
  const security = await loadSecurityPreferences(configDir);

  let managed: ManagedSession;
  const session = new ClaudeRuntimeSession(
    {
      sessionId,
      cwd: runtimeProjectPath(runtimeFacts.cwd),
      model: "sonnet",
      maxTurns: ITERATIVE_TURN_MAX_STEPS,
      systemPrompt: await activeAgentSystemPrompt(activeProfile),
      runtimeContext: {
        localTime: runtimeFacts.localTime,
        timezone: runtimeFacts.timezone,
        surface: route.surface,
        cwd: runtimeFacts.cwd,
        approvalPosture: security.highest_authorization_enabled
          ? "highest_authorization"
          : "gee_terminal_permissions",
        capabilities: [
          "bash",
          "read",
          "write",
          "edit",
          "grep",
          "glob",
          "ls",
        ],
      } satisfies RuntimeContext,
      autoApproveTools: DEFAULT_SDK_AUTO_APPROVE_TOOLS,
      disallowedTools: DEFAULT_SDK_DISALLOWED_TOOLS,
      gatewayBaseUrl: activeGateway.baseUrl,
      gatewayApiKey: activeGateway.apiKey,
    },
    (event) => emitToManagedSession(managed, event),
  );

  managed = { session, events: [], waiters: [] };
  sessions.set(sessionId, managed);
  managed.events.push({
    type: "session.created",
    sessionId,
    model: "sonnet",
    cwd: runtimeFacts.cwd,
  });
  return managed;
}

async function ensureGateway(
  backend: XenodiaGatewayBackend,
): Promise<AnthropicGatewayHandle> {
  const nextKey = JSON.stringify({
    apiKey: backend.api_key,
    url: backend.chat_completions_url,
    model: backend.model,
    timeout: backend.request_timeout_seconds,
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
  closeManagedSession(sessionId, managed);
}

function sdkEventIdleTimeoutMs(): number {
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
): Promise<void> {
  const toolInputsById = new Map<string, SeenSdkToolInvocation>();
  const idleTimeoutMs = sdkEventIdleTimeoutMs();
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
      case "session.tool_use":
        toolInputsById.set(event.toolUseId, {
          tool_name: event.toolName,
          input: normalizeRecord(event.input),
        });
        turn.tool_events.push({
          kind: "invocation",
          invocation_id: event.toolUseId,
          tool_name: event.toolName,
          input_summary: summarizePrompt(JSON.stringify(event.input), 180),
        });
        continue;
      case "session.tool_result": {
        const normalized = normalizeSdkToolResult(
          event,
          toolInputsById.get(event.toolUseId),
        );
        turn.tool_events.push({
          kind: "result",
          invocation_id: event.toolUseId,
          status: normalized.status,
          ...(normalized.summary ? { summary: summarizePrompt(normalized.summary, 220) } : {}),
          ...(normalized.error ? { error: summarizePrompt(normalized.error, 220) } : {}),
        });
        continue;
      }
      case "session.assistant_text": {
        const trimmed = event.text.trim();
        if (trimmed) {
          turn.assistant_chunks.push(trimmed);
        }
        continue;
      }
      case "session.result":
        if (event.result?.trim()) {
          turn.final_result = event.result.trim();
        }
        if (isRecord(event.raw) && event.raw.is_error === true) {
          turn.failed_reason = turn.final_result ?? "The SDK returned an error result.";
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

function normalizeSdkToolResult(
  event: SdkToolResultEvent,
  invocation: SeenSdkToolInvocation | undefined,
): { status: "succeeded" | "failed"; summary?: string; error?: string } {
  if (isExpectedNoMatchLsofResult(event, invocation)) {
    return {
      status: "succeeded",
      summary: "No matching listening process was found.",
    };
  }
  return {
    status: event.status,
    ...(event.summary ? { summary: event.summary } : {}),
    ...(event.error ? { error: event.error } : {}),
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

async function activeAgentSystemPrompt(profile: AgentProfile): Promise<string> {
  const sections = [profile.personality_prompt.trim()];
  const skillSections: string[] = [];
  for (const skill of profile.skills ?? []) {
    if (!skill.path) {
      continue;
    }
    try {
      const raw = await readFile(join(skill.path, "SKILL.md"), "utf8");
      const body = truncatePersonaSkillPrompt(raw);
      if (body.trim()) {
        skillSections.push(`## ${skill.id.trim()}\nPath: ${skill.path}\n\n${body}`);
      }
    } catch {
      continue;
    }
  }
  if (skillSections.length > 0) {
    sections.push(
      `[PERSONA SKILL WHITELIST]\nOnly the following persona skills are enabled. When a user request matches one of these skills, follow that skill's SKILL.md instructions. Do not assume access to unlisted local skills.\n\n${skillSections.join("\n\n")}`,
    );
  }
  return sections.map((section) => section.trim()).filter(Boolean).join("\n\n");
}

function truncatePersonaSkillPrompt(raw: string): string {
  const trimmed = raw.trim();
  if (trimmed.length <= PERSONA_SKILL_PROMPT_CHAR_LIMIT) {
    return trimmed;
  }
  return `${trimmed.slice(0, PERSONA_SKILL_PROMPT_CHAR_LIMIT)}\n\n[Skill content truncated by GeeAgent to fit the active turn context.]`;
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
      "Use Bash with an inspectable command such as curl or python urllib so the host can show and approve the exact operation."
    );
  }
  return (
    `GeeAgent host policy does not directly approve \`${toolName}\` through this boundary yet. ` +
    "Use Bash for local shell/file work so it can go through the terminal permission review flow."
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

function stringField(record: Record<string, unknown>, key: string): string | undefined {
  const value = record[key];
  return typeof value === "string" ? value : undefined;
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
  closeUnfinishedToolEventsOnFailure,
  sdkBashRequestFromInput,
  sdkEventIdleTimeoutMs,
  sdkEventIdleTimeoutReason,
  shouldRecycleGatewayAfterTurn,
  unsupportedToolDenialMessage,
  normalizeSdkToolResult,
  runtimeProjectPath,
  summarizePrompt,
};
