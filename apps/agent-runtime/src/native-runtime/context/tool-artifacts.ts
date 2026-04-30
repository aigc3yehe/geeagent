import { mkdir, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { extname, isAbsolute, relative, resolve } from "node:path";
import { inspect } from "node:util";
import { estimateTextTokens } from "./token-estimator.js";

export type ToolArtifactRef = {
  kind: "tool_result_artifact";
  artifact_id: string;
  invocation_id?: string;
  tool_name?: string;
  status: "succeeded" | "failed";
  path: string;
  sha256: string;
  byteCount: number;
  tokenEstimate: number;
  mimeType: string;
  summary: string;
};

export type ToolArtifactInput = {
  artifactRoot: string;
  invocationId?: string;
  toolName?: string;
  status: "succeeded" | "failed";
  result?: unknown;
  error?: unknown;
  summary?: string;
  mimeType?: string;
  maxInlineBytes?: number;
  maxInlineTokens?: number;
};

export type ToolArtifactMaterialization = {
  status: "succeeded" | "failed";
  materialized: boolean;
  summary: string;
  byteCount: number;
  tokenEstimate: number;
  contextText: string;
  artifact?: ToolArtifactRef;
};

const DEFAULT_MAX_INLINE_BYTES = 12_000;
const DEFAULT_MAX_INLINE_TOKENS = 2_000;
const PREVIEW_HEAD_LINES = 8;
const PREVIEW_TAIL_LINES = 4;
const PREVIEW_MAX_CHARS = 1_200;

export function shouldMaterializeToolResult(input: ToolArtifactInput): boolean {
  const normalized = normalizeToolResult(input);
  return (
    normalized.byteCount > inlineByteLimit(input) ||
    normalized.tokenEstimate > inlineTokenLimit(input)
  );
}

export async function materializeToolResult(
  input: ToolArtifactInput,
): Promise<ToolArtifactMaterialization> {
  const normalized = normalizeToolResult(input);
  const summary = summarizeToolResultForContext(input);
  if (!shouldMaterializeToolResult(input)) {
    return {
      status: input.status,
      materialized: false,
      summary,
      byteCount: normalized.byteCount,
      tokenEstimate: normalized.tokenEstimate,
      contextText: inlineContextText(input, normalized.text, summary),
    };
  }

  const artifactRoot = resolve(input.artifactRoot);
  const sha256 = createHash("sha256").update(normalized.bytes).digest("hex");
  const artifactId = artifactIdForInput(input, sha256);
  const directory = safeArtifactDirectory(artifactRoot, input.toolName);
  const path = safeArtifactPath(
    directory,
    `${artifactId}${extensionForMimeType(normalized.mimeType)}`,
  );
  await mkdir(directory, { recursive: true });
  await writeFile(path, normalized.bytes, { flag: "wx" }).catch(async (error: unknown) => {
    if (isNodeError(error) && error.code === "EEXIST") {
      return;
    }
    throw error;
  });

  const artifact: ToolArtifactRef = {
    kind: "tool_result_artifact",
    artifact_id: artifactId,
    ...(input.invocationId ? { invocation_id: input.invocationId } : {}),
    ...(input.toolName ? { tool_name: input.toolName } : {}),
    status: input.status,
    path,
    sha256,
    byteCount: normalized.byteCount,
    tokenEstimate: normalized.tokenEstimate,
    mimeType: normalized.mimeType,
    summary,
  };

  return {
    status: input.status,
    materialized: true,
    summary,
    byteCount: normalized.byteCount,
    tokenEstimate: normalized.tokenEstimate,
    contextText: artifactContextText(artifact),
    artifact,
  };
}

export function summarizeToolResultForContext(input: ToolArtifactInput): string {
  const normalized = normalizeToolResult(input);
  const explicit = input.summary?.trim();
  const statusPrefix = input.status === "failed" ? "Tool failed" : "Tool succeeded";
  const toolPrefix = input.toolName?.trim()
    ? `${statusPrefix}: ${input.toolName.trim()}`
    : statusPrefix;
  const metrics = `${normalized.lineCount} line${normalized.lineCount === 1 ? "" : "s"}, ${normalized.byteCount} bytes, ~${normalized.tokenEstimate} tokens`;

  if (explicit) {
    return `${toolPrefix}. ${truncateSingleLine(explicit, 420)} (${metrics}).`;
  }

  if (input.status === "failed") {
    const errorText = stringifyUnknown(input.error ?? input.result).trim();
    const preview = previewText(errorText);
    return `${toolPrefix}. Error output (${metrics}): ${preview}`;
  }

  if (normalized.kind === "json") {
    return `${toolPrefix}. JSON result (${metrics}): ${previewText(normalized.text)}`;
  }

  return `${toolPrefix}. Output (${metrics}): ${previewText(normalized.text)}`;
}

function normalizeToolResult(input: ToolArtifactInput): {
  kind: "json" | "text";
  text: string;
  bytes: Buffer;
  byteCount: number;
  tokenEstimate: number;
  lineCount: number;
  mimeType: string;
} {
  const payload = input.status === "failed" && input.error !== undefined
    ? input.error
    : input.result;
  const kind = typeof payload === "string" || payload === undefined ? "text" : "json";
  const text = kind === "json" ? stableJson(payload) : stringifyUnknown(payload);
  const bytes = Buffer.from(text, "utf8");
  return {
    kind,
    text,
    bytes,
    byteCount: bytes.byteLength,
    tokenEstimate: estimateTextTokens(text),
    lineCount: countLines(text),
    mimeType: input.mimeType ?? (kind === "json" ? "application/json" : "text/plain"),
  };
}

function inlineContextText(
  input: ToolArtifactInput,
  text: string,
  summary: string,
): string {
  if (input.status === "failed") {
    return [`[Tool result: failed]`, summary, text].filter(Boolean).join("\n");
  }
  return [`[Tool result: succeeded]`, summary, text].filter(Boolean).join("\n");
}

function artifactContextText(artifact: ToolArtifactRef): string {
  const statusLabel = artifact.status === "failed" ? "failed" : "succeeded";
  return [
    `[Tool result: ${statusLabel}, materialized]`,
    artifact.summary,
    `Artifact: ${artifact.path}`,
    `SHA-256: ${artifact.sha256}`,
    `Size: ${artifact.byteCount} bytes, ~${artifact.tokenEstimate} tokens`,
    "The full output is stored in the artifact file and is intentionally not inlined into context.",
  ].join("\n");
}

function inlineByteLimit(input: ToolArtifactInput): number {
  return input.maxInlineBytes ?? DEFAULT_MAX_INLINE_BYTES;
}

function inlineTokenLimit(input: ToolArtifactInput): number {
  return input.maxInlineTokens ?? DEFAULT_MAX_INLINE_TOKENS;
}

function artifactIdForInput(input: ToolArtifactInput, sha256: string): string {
  const invocation = input.invocationId
    ? `${safePathSegment(input.invocationId).slice(0, 48)}-`
    : "";
  return `${invocation}${sha256.slice(0, 16)}`;
}

function safeArtifactDirectory(artifactRoot: string, toolName: string | undefined): string {
  const directory = resolve(
    artifactRoot,
    "tool-results",
    safePathSegment(toolName ?? "unknown-tool"),
  );
  assertPathInsideRoot(artifactRoot, directory);
  return directory;
}

function safeArtifactPath(directory: string, filename: string): string {
  const path = resolve(directory, safePathSegment(filename, true));
  assertPathInsideRoot(directory, path);
  return path;
}

function assertPathInsideRoot(root: string, candidate: string): void {
  const relativePath = relative(root, candidate);
  if (relativePath.startsWith("..") || isAbsolute(relativePath)) {
    throw new Error(`Artifact path escaped root: ${candidate}`);
  }
}

function safePathSegment(value: string, allowDot = false): string {
  const trimmed = value.trim();
  const sanitized = trimmed
    .replace(/[^A-Za-z0-9._-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 96);
  const fallback = allowDot ? "artifact" : "unknown";
  const segment = sanitized || fallback;
  if (segment === "." || segment === ".." || (!allowDot && segment.includes("."))) {
    return segment.replace(/\./g, "-") || fallback;
  }
  return segment;
}

function extensionForMimeType(mimeType: string): string {
  if (mimeType === "application/json") {
    return ".json";
  }
  if (mimeType === "text/markdown") {
    return ".md";
  }
  if (mimeType === "text/html") {
    return ".html";
  }
  if (mimeType.startsWith("text/")) {
    return ".txt";
  }
  const extension = extname(mimeType);
  return extension || ".bin";
}

function stableJson(value: unknown): string {
  try {
    return `${JSON.stringify(sortJsonValue(value, new WeakSet<object>()), null, 2)}\n`;
  } catch {
    return `${inspect(value, { depth: 8, maxArrayLength: 200, breakLength: 100 })}\n`;
  }
}

function sortJsonValue(value: unknown, seen: WeakSet<object>): unknown {
  if (Array.isArray(value)) {
    if (seen.has(value)) {
      return "[Circular]";
    }
    seen.add(value);
    return value.map((child) => sortJsonValue(child, seen));
  }
  if (isPlainRecord(value)) {
    if (seen.has(value)) {
      return "[Circular]";
    }
    seen.add(value);
    return Object.fromEntries(
      Object.entries(value)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, child]) => [key, sortJsonValue(child, seen)]),
    );
  }
  if (typeof value === "bigint") {
    return value.toString();
  }
  return value;
}

function stringifyUnknown(value: unknown): string {
  if (value === undefined || value === null) {
    return "";
  }
  if (typeof value === "string") {
    return value;
  }
  if (value instanceof Error) {
    return value.stack ?? value.message;
  }
  return stableJson(value);
}

function previewText(text: string): string {
  const trimmed = text.trim();
  if (!trimmed) {
    return "(empty)";
  }
  const lines = trimmed.split(/\r?\n/);
  const previewLines =
    lines.length > PREVIEW_HEAD_LINES + PREVIEW_TAIL_LINES
      ? [
          ...lines.slice(0, PREVIEW_HEAD_LINES),
          `... ${lines.length - PREVIEW_HEAD_LINES - PREVIEW_TAIL_LINES} lines omitted ...`,
          ...lines.slice(-PREVIEW_TAIL_LINES),
        ]
      : lines;
  return truncateSingleLine(previewLines.join(" / "), PREVIEW_MAX_CHARS);
}

function truncateSingleLine(text: string, maxChars: number): string {
  const normalized = text.replace(/\s+/g, " ").trim();
  if (normalized.length <= maxChars) {
    return normalized;
  }
  return `${normalized.slice(0, Math.max(0, maxChars - 1))}...`;
}

function countLines(text: string): number {
  if (!text) {
    return 0;
  }
  return text.split(/\r?\n/).length;
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isNodeError(error: unknown): error is NodeJS.ErrnoException {
  return error instanceof Error && "code" in error;
}

export const __toolArtifactsTestHooks = {
  artifactIdForInput,
  normalizeToolResult,
  previewText,
  safePathSegment,
};
