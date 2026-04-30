import { randomUUID } from "node:crypto";
import { appendFileSync } from "node:fs";
import http, {
  type IncomingMessage,
  type ServerResponse,
} from "node:http";
import type { AddressInfo } from "node:net";

import { normalizeToolBoundaryInput } from "./tool-boundary-gateway.js";

const DEFAULT_XENODIA_CHAT_COMPLETIONS_URL =
  "https://api.xenodia.xyz/v1/chat/completions";
const DEFAULT_BACKEND_MODEL = "gpt-5.4";
const DEFAULT_REQUEST_TIMEOUT_SECONDS = 45;
const CONTEXT_WINDOW_TOKENS = 256_000;
const DEFAULT_MAX_OUTPUT_TOKENS = 32_000;
const DEFAULT_COMPLETION_TOKENS = 8_192;

type AnthropicGatewayOptions = {
  xenodiaApiKey: string;
  backendUrl?: string;
  modelOverride?: string;
  requestTimeoutSeconds?: number;
  maxCompletionTokens?: number;
  temperature?: number;
};

export type AnthropicGatewayHandle = {
  apiKey: string;
  baseUrl: string;
  close: () => Promise<void>;
};

type AnthropicToolDefinition = {
  name?: unknown;
  description?: unknown;
  input_schema?: unknown;
};

type AnthropicToolChoice =
  | {
      type?: unknown;
    }
  | {
      type?: unknown;
      name?: unknown;
      disable_parallel_tool_use?: unknown;
    };

type AnthropicMessage = {
  role?: unknown;
  content?: unknown;
};

type AnthropicMessagesRequest = {
  model?: unknown;
  max_tokens?: unknown;
  system?: unknown;
  messages?: unknown;
  tools?: unknown;
  tool_choice?: unknown;
  temperature?: unknown;
  stream?: unknown;
};

type OpenAIChatMessage = {
  role: "system" | "user" | "assistant" | "tool";
  content?: string | null;
  tool_calls?: OpenAIToolCall[];
  tool_call_id?: string;
};

type OpenAIToolCall = {
  id: string;
  type: "function";
  function: {
    name: string;
    arguments: string;
  };
};

type OpenAIChatCompletionRequest = {
  model: string;
  messages: OpenAIChatMessage[];
  tools?: Array<{
    type: "function";
    function: {
      name: string;
      description?: string;
      parameters: Record<string, unknown>;
    };
  }>;
  tool_choice?:
    | "auto"
    | "none"
    | "required"
    | {
        type: "function";
        function: {
          name: string;
        };
      };
  temperature?: number;
  max_completion_tokens?: number;
  stream: false;
};

type XenodiaUsage = {
  prompt_tokens?: unknown;
  completion_tokens?: unknown;
  input_tokens?: unknown;
  output_tokens?: unknown;
  total_tokens?: unknown;
};

type XenodiaToolCall = {
  id?: unknown;
  type?: unknown;
  function?: {
    name?: unknown;
    arguments?: unknown;
  };
};

type XenodiaChoiceMessage = {
  content?: unknown;
  tool_calls?: unknown;
};

type XenodiaChoice = {
  message?: XenodiaChoiceMessage;
};

type XenodiaChatCompletionResponse = {
  id?: unknown;
  choices?: unknown;
  usage?: XenodiaUsage;
};

class XenodiaGatewayError extends Error {
  readonly retryable: boolean;
  readonly statusCode?: number;

  constructor(message: string, options: { retryable: boolean; statusCode?: number }) {
    super(message);
    this.name = "XenodiaGatewayError";
    this.retryable = options.retryable;
    if (options.statusCode !== undefined) {
      this.statusCode = options.statusCode;
    }
  }
}

type AnthropicTextBlock = {
  type: "text";
  text: string;
  citations: null;
};

type AnthropicToolUseBlock = {
  type: "tool_use";
  id: string;
  name: string;
  input: Record<string, unknown>;
  caller: "direct";
};

type AnthropicContentBlock = AnthropicTextBlock | AnthropicToolUseBlock;

type AnthropicMessageResponse = {
  id: string;
  type: "message";
  role: "assistant";
  model: string;
  content: AnthropicContentBlock[];
  stop_reason: "end_turn" | "tool_use";
  stop_sequence: null;
  container: null;
  usage: {
    input_tokens: number;
    cache_creation_input_tokens: null;
    cache_read_input_tokens: null;
    output_tokens: number;
    server_tool_use: null;
  };
};

type AnthropicStreamEvent =
  | {
      type: "message_start";
      message: Omit<AnthropicMessageResponse, "content" | "stop_reason" | "usage"> & {
        content: [];
        stop_reason: null;
        usage: Omit<AnthropicMessageResponse["usage"], "output_tokens"> & {
          output_tokens: 0;
        };
      };
    }
  | {
      type: "content_block_start";
      index: number;
      content_block: AnthropicContentBlock;
    }
  | {
      type: "content_block_delta";
      index: number;
      delta:
        | {
            type: "text_delta";
            text: string;
          }
        | {
            type: "input_json_delta";
            partial_json: string;
          };
    }
  | {
      type: "content_block_stop";
      index: number;
    }
  | {
      type: "message_delta";
      delta: {
        stop_reason: "end_turn" | "tool_use";
        stop_sequence: null;
        container: null;
      };
      usage: AnthropicMessageResponse["usage"];
    }
  | {
      type: "message_stop";
    };

function firstHeaderValue(value: string | string[] | undefined): string | null {
  if (Array.isArray(value)) {
    const first = value[0]?.trim();
    return first && first.length > 0 ? first : null;
  }
  const trimmed = value?.trim();
  return trimmed && trimmed.length > 0 ? trimmed : null;
}

function isAuthorizedRequest(
  request: IncomingMessage,
  gatewayApiKey: string,
): boolean {
  const xApiKey = firstHeaderValue(request.headers["x-api-key"]);
  if (xApiKey === gatewayApiKey) {
    return true;
  }

  const authorization = firstHeaderValue(request.headers.authorization);
  if (!authorization) {
    return false;
  }

  const match = /^Bearer\s+(.+)$/i.exec(authorization);
  return match?.[1] === gatewayApiKey;
}

async function readJsonBody(request: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  for await (const chunk of request) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }

  const raw = Buffer.concat(chunks).toString("utf8").trim();
  if (!raw) {
    return {};
  }

  return JSON.parse(raw);
}

function writeJson(
  response: ServerResponse,
  statusCode: number,
  payload: unknown,
): void {
  response.writeHead(statusCode, {
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
  });
  response.end(JSON.stringify(payload));
}

function writeAnthropicError(
  response: ServerResponse,
  statusCode: number,
  message: string,
): void {
  writeJson(response, statusCode, {
    type: "error",
    error: {
      type: statusCode >= 500 ? "api_error" : "invalid_request_error",
      message,
    },
  });
}

function asString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value : null;
}

function asNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function asArray<T>(value: unknown): T[] {
  return Array.isArray(value) ? (value as T[]) : [];
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return null;
}

function normalizeTextContent(content: unknown): string | null {
  if (typeof content === "string") {
    const trimmed = content.trim();
    return trimmed.length > 0 ? trimmed : null;
  }

  const blocks = asArray<Record<string, unknown>>(content);
  const text = blocks
    .map((block) => {
      const type = asString(block.type);
      if (type === "text") {
        return asString(block.text) ?? "";
      }
      return "";
    })
    .filter((value) => value.length > 0)
    .join("\n");

  return text.trim().length > 0 ? text.trim() : null;
}

function normalizeToolResultContent(content: unknown): string {
  if (typeof content === "string") {
    return content;
  }

  const blocks = asArray<Record<string, unknown>>(content);
  const text = blocks
    .map((block) => {
      const type = asString(block.type);
      if (type === "text") {
        return asString(block.text) ?? "";
      }
      return JSON.stringify(block);
    })
    .filter((value) => value.trim().length > 0)
    .join("\n");

  if (text.trim().length > 0) {
    return text;
  }

  return JSON.stringify(content ?? "");
}

function normalizeSystemPrompt(system: unknown): string | null {
  if (typeof system === "string") {
    return system.trim().length > 0 ? system : null;
  }

  const blocks = asArray<Record<string, unknown>>(system);
  const text = blocks
    .map((block) => {
      if (asString(block.type) === "text") {
        return asString(block.text) ?? "";
      }
      return "";
    })
    .filter((value) => value.length > 0)
    .join("\n");

  return text.trim().length > 0 ? text.trim() : null;
}

function anthropicToolChoiceToOpenAI(
  value: unknown,
): OpenAIChatCompletionRequest["tool_choice"] | undefined {
  const choice = asRecord(value) as AnthropicToolChoice | null;
  const type = asString(choice?.type);
  if (!type) {
    return undefined;
  }

  if (type === "none") {
    return "none";
  }

  if (type === "tool") {
    const name = asString((choice as { name?: unknown }).name);
    if (name) {
      return {
        type: "function",
        function: {
          name,
        },
      };
    }
  }

  if (type === "any") {
    return "required";
  }

  return "auto";
}

function anthropicToolsToOpenAI(
  value: unknown,
): OpenAIChatCompletionRequest["tools"] | undefined {
  const tools = asArray<AnthropicToolDefinition>(value)
    .map((tool) => {
      const name = asString(tool.name);
      if (!name) {
        return null;
      }

      return {
        type: "function" as const,
        function: {
          name,
          description: asString(tool.description) ?? undefined,
          parameters: asRecord(tool.input_schema) ?? {
            type: "object",
            properties: {},
          },
        },
      };
    })
    .filter((tool): tool is NonNullable<typeof tool> => tool !== null);

  return tools.length > 0 ? tools : undefined;
}

function anthropicMessagesToOpenAI(messages: unknown): OpenAIChatMessage[] {
  const output: OpenAIChatMessage[] = [];

  for (const message of asArray<AnthropicMessage>(messages)) {
    const role = asString(message.role);
    if (role !== "user" && role !== "assistant") {
      continue;
    }

    if (typeof message.content === "string") {
      if (message.content.trim().length > 0) {
        output.push({
          role,
          content: message.content,
        });
      }
      continue;
    }

    const blocks = asArray<Record<string, unknown>>(message.content);
    const textBlocks: string[] = [];
    const toolCalls: OpenAIToolCall[] = [];
    const toolResults: OpenAIChatMessage[] = [];

    for (const block of blocks) {
      const blockType = asString(block.type);
      if (blockType === "text") {
        const text = asString(block.text);
        if (text) {
          textBlocks.push(text);
        }
        continue;
      }

      if (role === "assistant" && blockType === "tool_use") {
        const id = asString(block.id) ?? `toolu_${randomUUID()}`;
        const name = asString(block.name) ?? "tool";
        const input = asRecord(block.input) ?? {};
        toolCalls.push({
          id,
          type: "function",
          function: {
            name,
            arguments: JSON.stringify(input),
          },
        });
        continue;
      }

      if (role === "user" && blockType === "tool_result") {
        const toolUseId = asString(block.tool_use_id);
        if (!toolUseId) {
          continue;
        }

        toolResults.push({
          role: "tool",
          tool_call_id: toolUseId,
          content: normalizeToolResultContent(block.content),
        });
      }
    }

    if (role === "assistant") {
      if (textBlocks.length > 0 || toolCalls.length > 0) {
        output.push({
          role: "assistant",
          content: textBlocks.length > 0 ? textBlocks.join("\n") : null,
          tool_calls: toolCalls.length > 0 ? toolCalls : undefined,
        });
      }
      continue;
    }

    if (textBlocks.length > 0) {
      output.push({
        role: "user",
        content: textBlocks.join("\n"),
      });
    }

    output.push(...toolResults);
  }

  return output;
}

function resolveBackendModel(
  anthropicModel: string,
  modelOverride: string | undefined,
): string {
  const override = modelOverride?.trim();
  if (override) {
    return override;
  }

  const normalized = anthropicModel.trim().toLowerCase();
  if (
    normalized === "sonnet" ||
    normalized.startsWith("claude-") ||
    normalized.startsWith("claude_")
  ) {
    return DEFAULT_BACKEND_MODEL;
  }

  return anthropicModel;
}

function resolveRequestTimeoutMs(options: AnthropicGatewayOptions): number {
  const seconds = options.requestTimeoutSeconds;
  if (typeof seconds === "number" && Number.isFinite(seconds) && seconds > 0) {
    return Math.ceil(seconds * 1000);
  }
  return DEFAULT_REQUEST_TIMEOUT_SECONDS * 1000;
}

function resolveConfiguredMaxCompletionTokens(
  options: AnthropicGatewayOptions,
): number {
  const configured = options.maxCompletionTokens;
  if (
    typeof configured === "number" &&
    Number.isFinite(configured) &&
    configured > 0
  ) {
    return configured;
  }
  return DEFAULT_COMPLETION_TOKENS;
}

function resolveMaxCompletionTokens(
  request: AnthropicMessagesRequest,
  options: AnthropicGatewayOptions,
): number {
  const requested = asNumber(request.max_tokens);
  const limit = requested ?? resolveConfiguredMaxCompletionTokens(options);
  return Math.min(Math.max(1, Math.ceil(limit)), DEFAULT_MAX_OUTPUT_TOKENS);
}

function resolveTemperature(
  request: AnthropicMessagesRequest,
  options: AnthropicGatewayOptions,
): number | undefined {
  const requested = asNumber(request.temperature);
  if (requested !== null) {
    return requested;
  }
  const configured = options.temperature;
  if (
    typeof configured === "number" &&
    Number.isFinite(configured) &&
    configured >= 0
  ) {
    return configured;
  }
  return undefined;
}

function approximateTokens(text: string): number {
  if (!text.trim()) {
    return 0;
  }
  const cjkCount = text.match(/[\u3400-\u4dbf\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]/g)?.length ?? 0;
  const otherCount = Math.max(0, [...text].length - cjkCount);
  const charEstimate = cjkCount + Math.ceil(otherCount / 4);
  const byteEstimate = Math.ceil(Buffer.byteLength(text, "utf8") / 4);
  return Math.max(1, charEstimate, byteEstimate);
}

function approximateRequestTokens(request: AnthropicMessagesRequest): number {
  const parts: string[] = [];
  const system = normalizeSystemPrompt(request.system);
  if (system) {
    parts.push(system);
  }

  for (const message of asArray<AnthropicMessage>(request.messages)) {
    const role = asString(message.role);
    if (role) {
      parts.push(role);
    }

    if (typeof message.content === "string") {
      parts.push(message.content);
      continue;
    }

    for (const block of asArray<Record<string, unknown>>(message.content)) {
      const type = asString(block.type);
      if (type === "text") {
        parts.push(asString(block.text) ?? "");
      } else {
        parts.push(JSON.stringify(block));
      }
    }
  }

  for (const tool of asArray<AnthropicToolDefinition>(request.tools)) {
    parts.push(
      JSON.stringify({
        name: tool.name,
        description: tool.description,
        input_schema: tool.input_schema,
      }),
    );
  }

  return approximateTokens(parts.join("\n"));
}

function requestToolNames(request: AnthropicMessagesRequest): string[] {
  return asArray<AnthropicToolDefinition>(request.tools)
    .map((tool) => asString(tool.name))
    .filter((name): name is string => Boolean(name));
}

function buildModelInfo(id: string): Record<string, unknown> {
  return {
    id,
    type: "model",
    display_name: id,
    created_at: "1970-01-01T00:00:00Z",
    max_input_tokens: CONTEXT_WINDOW_TOKENS,
    max_tokens: DEFAULT_MAX_OUTPUT_TOKENS,
    capabilities: null,
  };
}

function safeJsonParseRecord(input: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(input);
    return asRecord(parsed) ?? { value: parsed };
  } catch {
    return { raw: input };
  }
}

function extractToolCalls(value: unknown): OpenAIToolCall[] {
  return asArray<XenodiaToolCall>(value)
    .map((toolCall) => {
      const id = asString(toolCall.id) ?? `toolu_${randomUUID()}`;
      const name = asString(toolCall.function?.name);
      if (!name) {
        return null;
      }

      const argumentsText =
        asString(toolCall.function?.arguments) ?? JSON.stringify({});
      return {
        id,
        type: "function",
        function: {
          name,
          arguments: argumentsText,
        },
      };
    })
    .filter((toolCall): toolCall is OpenAIToolCall => toolCall !== null);
}

function normalizeAssistantContent(value: unknown): string | null {
  if (typeof value === "string") {
    return value.trim().length > 0 ? value : null;
  }

  const blocks = asArray<Record<string, unknown>>(value);
  const text = blocks
    .map((block) => {
      const blockType = asString(block.type);
      if (blockType === "text") {
        return asString(block.text) ?? "";
      }
      return "";
    })
    .filter((entry) => entry.length > 0)
    .join("\n");

  return text.trim().length > 0 ? text.trim() : null;
}

function buildAnthropicMessageFromXenodia(
  request: AnthropicMessagesRequest,
  response: XenodiaChatCompletionResponse,
): AnthropicMessageResponse {
  const choice = asArray<XenodiaChoice>(response.choices)[0];
  const assistantMessage = asRecord(choice?.message) ?? {};
  const text = normalizeAssistantContent(assistantMessage.content);
  const toolCalls = extractToolCalls(assistantMessage.tool_calls);

  const content: AnthropicContentBlock[] = [];
  if (text) {
    content.push({
      type: "text",
      text,
      citations: null,
    });
  }

  for (const toolCall of toolCalls) {
    content.push({
      type: "tool_use",
      id: toolCall.id,
      name: toolCall.function.name,
      input: normalizeToolBoundaryInput(
        toolCall.function.name,
        safeJsonParseRecord(toolCall.function.arguments),
      ),
      caller: "direct",
    });
  }

  const usage = asRecord(response.usage) ?? {};
  const inputTokens =
    asNumber(usage.prompt_tokens) ??
    asNumber(usage.input_tokens) ??
    approximateRequestTokens(request);
  const totalTokens = asNumber(usage.total_tokens);
  const outputTokens =
    asNumber(usage.completion_tokens) ??
    asNumber(usage.output_tokens) ??
    (totalTokens !== null ? Math.max(0, totalTokens - inputTokens) : null) ??
    approximateTokens(text ?? JSON.stringify(toolCalls));

  return {
    id: asString(response.id) ?? `msg_${randomUUID()}`,
    type: "message",
    role: "assistant",
    model: asString(request.model) ?? "sonnet",
    content,
    stop_reason: toolCalls.length > 0 ? "tool_use" : "end_turn",
    stop_sequence: null,
    container: null,
    usage: {
      input_tokens: inputTokens,
      cache_creation_input_tokens: null,
      cache_read_input_tokens: null,
      output_tokens: outputTokens,
      server_tool_use: null,
    },
  };
}

function toOpenAIChatCompletionRequest(
  request: AnthropicMessagesRequest,
  options: AnthropicGatewayOptions,
  modelOverride = options.modelOverride,
): OpenAIChatCompletionRequest {
  const anthropicModel = asString(request.model) ?? "sonnet";
  const messages = anthropicMessagesToOpenAI(request.messages);
  const system = normalizeSystemPrompt(request.system);
  if (system) {
    messages.unshift({
      role: "system",
      content: system,
    });
  }

  const body: OpenAIChatCompletionRequest = {
    model: resolveBackendModel(anthropicModel, modelOverride),
    messages,
    stream: false,
    max_completion_tokens: resolveMaxCompletionTokens(request, options),
  };

  const tools = anthropicToolsToOpenAI(request.tools);
  if (tools) {
    body.tools = tools;
  }

  const toolChoice = anthropicToolChoiceToOpenAI(request.tool_choice);
  if (toolChoice) {
    body.tool_choice = toolChoice;
  }

  const temperature = resolveTemperature(request, options);
  if (temperature !== undefined) {
    body.temperature = temperature;
  }

  return body;
}

async function callXenodia(
  request: AnthropicMessagesRequest,
  options: AnthropicGatewayOptions,
): Promise<XenodiaChatCompletionResponse> {
  const timeoutMs = resolveRequestTimeoutMs(options);
  return callXenodiaModel(request, options, {
    modelOverride: options.modelOverride,
    timeoutMs,
    label: "primary",
  });
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function traceGatewayEvent(
  event: string,
  fields: Record<string, unknown> = {},
): void {
  const tracePath = process.env.GEEAGENT_GATEWAY_TRACE_PATH?.trim();
  if (!tracePath) {
    return;
  }
  try {
    appendFileSync(
      tracePath,
      `${JSON.stringify({ ts: new Date().toISOString(), event, ...fields })}\n`,
      "utf8",
    );
  } catch {
    // Trace logging is best-effort and must not affect runtime behavior.
  }
}

async function callXenodiaModel(
  request: AnthropicMessagesRequest,
  options: AnthropicGatewayOptions,
  attempt: {
    modelOverride?: string;
    timeoutMs: number;
    label: "primary";
  },
): Promise<XenodiaChatCompletionResponse> {
  const timeoutMs = attempt.timeoutMs;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  let response: Response;

  traceGatewayEvent("upstream.start", {
    label: attempt.label,
    model: attempt.modelOverride ?? resolveBackendModel(
      asString(request.model) ?? "sonnet",
      options.modelOverride,
    ),
    timeout_ms: timeoutMs,
  });
  try {
    response = await fetch(options.backendUrl ?? DEFAULT_XENODIA_CHAT_COMPLETIONS_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${options.xenodiaApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(
        toOpenAIChatCompletionRequest(request, options, attempt.modelOverride),
      ),
      signal: controller.signal,
    });
  } catch (error) {
    traceGatewayEvent("upstream.error", {
      label: attempt.label,
      aborted: controller.signal.aborted,
      message: errorMessage(error).slice(0, 180),
    });
    if (controller.signal.aborted) {
      throw new XenodiaGatewayError(
        `xenodia ${attempt.label} request timed out after ${Math.ceil(
          timeoutMs / 1000,
        )} seconds`,
        { retryable: true },
      );
    }
    throw new XenodiaGatewayError(errorMessage(error), { retryable: true });
  } finally {
    clearTimeout(timeout);
  }

  const raw = await response.text();
  let parsed: unknown = {};
  if (raw.trim().length > 0) {
    try {
      parsed = JSON.parse(raw);
    } catch {
      parsed = raw;
    }
  }

  if (!response.ok) {
    const envelope = asRecord(parsed);
    const errorMessage =
      asString(envelope?.error) ??
      asString(asRecord(envelope?.error)?.message) ??
      (typeof parsed === "string" ? parsed : null) ??
      `xenodia request failed with status ${response.status}`;
    traceGatewayEvent("upstream.status_error", {
      label: attempt.label,
      status: response.status,
    });
    throw new XenodiaGatewayError(errorMessage, {
      retryable: response.status !== 401 && response.status !== 403,
      statusCode: response.status,
    });
  }

  traceGatewayEvent("upstream.ok", {
    label: attempt.label,
    status: response.status,
  });
  return asRecord(parsed) as XenodiaChatCompletionResponse;
}

function writeSse(
  response: ServerResponse,
  event: AnthropicStreamEvent["type"],
  payload: AnthropicStreamEvent,
): void {
  response.write(`event: ${event}\n`);
  response.write(`data: ${JSON.stringify(payload)}\n\n`);
}

function writeAnthropicStreamResponse(
  response: ServerResponse,
  message: AnthropicMessageResponse,
): void {
  response.writeHead(200, {
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache, no-transform",
    Connection: "keep-alive",
  });

  writeSse(response, "message_start", {
    type: "message_start",
    message: {
      ...message,
      content: [],
      stop_reason: null,
      usage: {
        ...message.usage,
        output_tokens: 0,
      },
    },
  });

  message.content.forEach((block, index) => {
    if (block.type === "text") {
      writeSse(response, "content_block_start", {
        type: "content_block_start",
        index,
        content_block: {
          type: "text",
          text: "",
          citations: null,
        },
      });
      if (block.text.length > 0) {
        writeSse(response, "content_block_delta", {
          type: "content_block_delta",
          index,
          delta: {
            type: "text_delta",
            text: block.text,
          },
        });
      }
      writeSse(response, "content_block_stop", {
        type: "content_block_stop",
        index,
      });
      return;
    }

    writeSse(response, "content_block_start", {
      type: "content_block_start",
      index,
      content_block: {
        type: "tool_use",
        id: block.id,
        name: block.name,
        input: {},
        caller: "direct",
      },
    });
    writeSse(response, "content_block_delta", {
      type: "content_block_delta",
      index,
      delta: {
        type: "input_json_delta",
        partial_json: JSON.stringify(block.input),
      },
    });
    writeSse(response, "content_block_stop", {
      type: "content_block_stop",
      index,
    });
  });

  writeSse(response, "message_delta", {
    type: "message_delta",
    delta: {
      stop_reason: message.stop_reason,
      stop_sequence: null,
      container: null,
    },
    usage: message.usage,
  });
  writeSse(response, "message_stop", {
    type: "message_stop",
  });
  response.end();
}

async function handleMessagesRequest(
  request: IncomingMessage,
  response: ServerResponse,
  options: AnthropicGatewayOptions,
): Promise<void> {
  const payload = (await readJsonBody(request)) as AnthropicMessagesRequest;
  traceGatewayEvent("messages.request", {
    stream: payload.stream === true,
    model: asString(payload.model) ?? "sonnet",
    approximate_tokens: approximateRequestTokens(payload),
    tool_count: requestToolNames(payload).length,
    tool_names: requestToolNames(payload).slice(0, 40),
    tool_choice: payload.tool_choice ?? null,
  });
  const upstream = await callXenodia(payload, options);
  const anthropicMessage = buildAnthropicMessageFromXenodia(payload, upstream);

  if (payload.stream === true) {
    writeAnthropicStreamResponse(response, anthropicMessage);
    return;
  }

  writeJson(response, 200, anthropicMessage);
}

async function handleRequest(
  request: IncomingMessage,
  response: ServerResponse,
  options: AnthropicGatewayOptions,
  gatewayApiKey: string,
): Promise<void> {
  if (!isAuthorizedRequest(request, gatewayApiKey)) {
    writeAnthropicError(response, 401, "invalid local gateway credentials");
    return;
  }

  const requestUrl = new URL(request.url ?? "/", "http://127.0.0.1");
  const pathname = requestUrl.pathname;
  const method = request.method?.toUpperCase();
  traceGatewayEvent("http.request", { method, pathname });

  if (method === "POST" && pathname === "/v1/messages") {
    await handleMessagesRequest(request, response, options);
    return;
  }

  if (method === "POST" && pathname === "/v1/messages/count_tokens") {
    const payload = (await readJsonBody(request)) as AnthropicMessagesRequest;
    writeJson(response, 200, {
      input_tokens: approximateRequestTokens(payload),
    });
    return;
  }

  if (method === "GET" && pathname === "/v1/models") {
    const preferredModel =
      options.modelOverride?.trim() || DEFAULT_BACKEND_MODEL;
    const data = ["sonnet", "claude-sonnet-4-6", preferredModel].map(
      buildModelInfo,
    );
    writeJson(response, 200, {
      data,
      first_id: data[0]?.id ?? "sonnet",
      last_id: data[data.length - 1]?.id ?? preferredModel,
      has_more: false,
    });
    return;
  }

  if (method === "GET" && pathname.startsWith("/v1/models/")) {
    const modelId = decodeURIComponent(pathname.replace("/v1/models/", ""));
    writeJson(response, 200, buildModelInfo(modelId || "sonnet"));
    return;
  }

  writeAnthropicError(response, 404, `unsupported gateway route ${pathname}`);
}

export async function startAnthropicGateway(
  options: AnthropicGatewayOptions,
): Promise<AnthropicGatewayHandle> {
  if (!options.xenodiaApiKey.trim()) {
    throw new Error("xenodia API key is required for the local SDK gateway");
  }

  const gatewayApiKey = randomUUID();
  const server = http.createServer((request, response) => {
    void handleRequest(request, response, options, gatewayApiKey).catch(
      (error: unknown) => {
        writeAnthropicError(
          response,
          500,
          error instanceof Error ? error.message : String(error),
        );
      },
    );
  });

  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      server.off("error", reject);
      resolve();
    });
  });

  const address = server.address() as AddressInfo | null;
  if (!address) {
    throw new Error("local SDK gateway did not expose a listening address");
  }
  traceGatewayEvent("gateway.listen", { port: address.port });

  return {
    apiKey: gatewayApiKey,
    baseUrl: `http://127.0.0.1:${address.port}`,
    close: async () => {
      await new Promise<void>((resolve, reject) => {
        server.close((error) => {
          if (error) {
            reject(error);
            return;
          }
          resolve();
        });
      });
    },
  };
}

export const __gatewayTestHooks = {
  anthropicMessagesToOpenAI,
  anthropicToolChoiceToOpenAI,
  anthropicToolsToOpenAI,
  approximateRequestTokens,
  buildAnthropicMessageFromXenodia,
  resolveMaxCompletionTokens,
  resolveRequestTimeoutMs,
  resolveBackendModel,
  toOpenAIChatCompletionRequest,
};
