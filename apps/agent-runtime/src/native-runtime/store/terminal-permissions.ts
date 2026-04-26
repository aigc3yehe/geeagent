import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname } from "node:path";

import { terminalAccessPath } from "../paths.js";
import { currentTimestamp } from "./defaults.js";

export type TerminalAccessDecision = "allow" | "deny";

export type TerminalAccessScope =
  | {
      kind: "controlled_terminal_plan";
      signature: string;
    }
  | {
      kind: "sdk_runtime_bash" | "sdk_bridge_bash";
      command: string;
      cwd?: string;
    };

type TerminalAccessRule = {
  scope?: TerminalAccessScope | Record<string, unknown>;
  decision?: TerminalAccessDecision | string;
  label?: string;
  updated_at?: string;
};

function ruleId(rule: TerminalAccessRule): string {
  const canonical = canonicalScopeJSON(rule.scope ?? {});
  return `terminal_access_${legacyTerminalRuleHash(canonical)}`;
}

export async function loadTerminalAccessRuleRecords(configDir: string): Promise<unknown[]> {
  const permissions = await loadTerminalAccessPermissions(configDir);
  return permissions.rules.map((rule) => {
    const scope = (isRecord(rule.scope) ? rule.scope : {}) as Record<string, unknown>;
    return {
      rule_id: ruleId(rule),
      decision: rule.decision ?? "allow",
      kind: ruleKind(rule.scope),
      label: rule.label ?? "Terminal access",
      command: typeof scope.command === "string" ? scope.command : null,
      cwd: typeof scope.cwd === "string" ? scope.cwd : null,
      updated_at: rule.updated_at ?? "",
    };
  });
}

export async function deleteTerminalAccessRule(
  configDir: string,
  requestedRuleId: string,
): Promise<void> {
  const trimmedRuleId = requestedRuleId.trim();
  if (!trimmedRuleId) {
    throw new Error("terminal permission rule id is required");
  }

  const permissions = await loadTerminalAccessPermissions(configDir);
  const before = permissions.rules.length;
  permissions.rules = permissions.rules.filter((rule) => ruleId(rule) !== trimmedRuleId);
  if (permissions.rules.length === before) {
    throw new Error(`terminal permission rule \`${trimmedRuleId}\` was not found`);
  }
  await writeFile(
    terminalAccessPath(configDir),
    `${JSON.stringify(permissions, null, 2)}\n`,
    "utf8",
  );
}

export async function terminalAccessDecisionForScope(
  configDir: string,
  scope: TerminalAccessScope,
): Promise<TerminalAccessDecision | undefined> {
  const permissions = await loadTerminalAccessPermissions(configDir);
  const found = permissions.rules.find((rule) =>
    scopesEqual(rule.scope, scope),
  );
  return found?.decision === "allow" || found?.decision === "deny"
    ? found.decision
    : undefined;
}

export async function upsertTerminalAccessRule(
  configDir: string,
  scope: TerminalAccessScope,
  decision: TerminalAccessDecision,
  label: string,
): Promise<void> {
  const permissions = await loadTerminalAccessPermissions(configDir);
  const existing = permissions.rules.find((rule) => scopesEqual(rule.scope, scope));
  if (existing) {
    existing.decision = decision;
    existing.label = label;
    existing.updated_at = currentTimestamp();
  } else {
    permissions.rules.unshift({
      scope,
      decision,
      label,
      updated_at: currentTimestamp(),
    });
  }
  const path = terminalAccessPath(configDir);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify(permissions, null, 2)}\n`, "utf8");
}

export function sdkRuntimeBashScope(
  command: string,
  cwd?: string,
): TerminalAccessScope {
  const trimmedCwd = cwd?.trim();
  return {
    kind: "sdk_runtime_bash",
    command: command.trim(),
    ...(trimmedCwd ? { cwd: trimmedCwd } : {}),
  };
}

export function terminalAccessLabelForScope(scope: TerminalAccessScope): string {
  if (scope.kind === "controlled_terminal_plan") {
    return `controlled terminal plan: ${summarizePrompt(scope.signature, 120)}`;
  }
  return scope.cwd
    ? `${summarizePrompt(scope.command, 120)} @ ${scope.cwd}`
    : summarizePrompt(scope.command, 120);
}

async function loadTerminalAccessPermissions(
  configDir: string,
): Promise<{ rules: TerminalAccessRule[] }> {
  try {
    const raw = await readFile(terminalAccessPath(configDir), "utf8");
    const parsed = JSON.parse(raw) as { rules?: TerminalAccessRule[] };
    return { rules: Array.isArray(parsed.rules) ? parsed.rules : [] };
  } catch {
    return { rules: [] };
  }
}

function scopesEqual(
  left: TerminalAccessRule["scope"],
  right: TerminalAccessScope,
): boolean {
  return comparisonScopeJSON((left ?? {}) as Record<string, unknown>) ===
    comparisonScopeJSON(right as unknown as Record<string, unknown>);
}

function ruleKind(scope: Record<string, unknown> | undefined): string {
  const kind = scope?.kind ?? scope?.type;
  return typeof kind === "string" ? kind : "terminal";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function canonicalScopeJSON(scope: Record<string, unknown>): string {
  const kind = ruleKind(scope);
  if (isSdkTerminalScopeKind(kind)) {
    return sdkTerminalScopeJSON(scope, kind);
  }
  if (kind === "controlled_terminal_plan") {
    return JSON.stringify({
      kind,
      signature: typeof scope.signature === "string" ? scope.signature : "",
    });
  }
  return JSON.stringify(scope);
}

function comparisonScopeJSON(scope: Record<string, unknown>): string {
  const kind = ruleKind(scope);
  if (isSdkTerminalScopeKind(kind)) {
    return sdkTerminalScopeJSON(scope, "sdk_runtime_bash");
  }
  return canonicalScopeJSON(scope);
}

function isSdkTerminalScopeKind(kind: unknown): kind is "sdk_runtime_bash" | "sdk_bridge_bash" {
  return kind === "sdk_runtime_bash" || kind === "sdk_bridge_bash";
}

function sdkTerminalScopeJSON(
  scope: Record<string, unknown>,
  kind: "sdk_runtime_bash" | "sdk_bridge_bash",
): string {
  const canonical: Record<string, unknown> = {
    kind,
    command: typeof scope.command === "string" ? scope.command : "",
  };
  if (typeof scope.cwd === "string") {
    canonical.cwd = scope.cwd;
  }
  return JSON.stringify(canonical);
}

function summarizePrompt(prompt: string, maxLength: number): string {
  const trimmed = prompt.trim().replace(/\s+/g, " ");
  if (trimmed.length <= maxLength) {
    return trimmed;
  }
  return `${trimmed.slice(0, Math.max(0, maxLength - 1))}…`;
}

// Preserve the historical terminal permission ID format so previously saved
// rules remain visible and removable after the native TS runtime takes over.
function legacyTerminalRuleHash(value: string): string {
  const bytes = [...Buffer.from(value, "utf8"), 0xff];
  return sipHash13(bytes, 0n, 0n).toString(16).padStart(16, "0");
}

function sipHash13(bytes: number[], key0: bigint, key1: bigint): bigint {
  const mask = 0xffff_ffff_ffff_ffffn;
  let v0 = 0x736f_6d65_7073_6575n ^ key0;
  let v1 = 0x646f_7261_6e64_6f6dn ^ key1;
  let v2 = 0x6c79_6765_6e65_7261n ^ key0;
  let v3 = 0x7465_6462_7974_6573n ^ key1;

  const sipRound = (): void => {
    v0 = (v0 + v1) & mask;
    v1 = rotateLeft(v1, 13n);
    v1 ^= v0;
    v0 = rotateLeft(v0, 32n);
    v2 = (v2 + v3) & mask;
    v3 = rotateLeft(v3, 16n);
    v3 ^= v2;
    v0 = (v0 + v3) & mask;
    v3 = rotateLeft(v3, 21n);
    v3 ^= v0;
    v2 = (v2 + v1) & mask;
    v1 = rotateLeft(v1, 17n);
    v1 ^= v2;
    v2 = rotateLeft(v2, 32n);
  };

  let offset = 0;
  while (offset + 8 <= bytes.length) {
    const m = readU64LittleEndian(bytes, offset);
    v3 ^= m;
    sipRound();
    v0 ^= m;
    offset += 8;
  }

  let last = BigInt(bytes.length) << 56n;
  for (let index = 0; offset + index < bytes.length; index += 1) {
    last |= BigInt(bytes[offset + index]) << BigInt(index * 8);
  }

  v3 ^= last;
  sipRound();
  v0 ^= last;
  v2 ^= 0xffn;
  sipRound();
  sipRound();
  sipRound();
  return (v0 ^ v1 ^ v2 ^ v3) & mask;
}

function readU64LittleEndian(bytes: number[], offset: number): bigint {
  let value = 0n;
  for (let index = 0; index < 8; index += 1) {
    value |= BigInt(bytes[offset + index]) << BigInt(index * 8);
  }
  return value;
}

function rotateLeft(value: bigint, bits: bigint): bigint {
  const mask = 0xffff_ffff_ffff_ffffn;
  return ((value << bits) | (value >> (64n - bits))) & mask;
}
