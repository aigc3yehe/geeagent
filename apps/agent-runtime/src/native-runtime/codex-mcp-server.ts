import readline from "node:readline";
import type { Readable, Writable } from "node:stream";

import {
  codexExportStatus,
  describeCodexExportCapability,
  EXPORT_STANDARD,
  IMPLEMENTED_CODEX_EXPORT_TOOLS,
  LIVE_BRIDGE_CODEX_EXPORT_TOOLS,
  listCodexExportCapabilities,
  PLANNED_CODEX_EXPORT_TOOLS,
  type CodexExportOptions,
} from "./codex-export.js";
import {
  createExternalInvocation,
  getExternalInvocation,
  waitForExternalInvocation,
} from "./codex-external-invocations.js";
import { resolveConfigDir } from "./paths.js";

type JsonRpcID = string | number | null;

type JsonRpcRequest = {
  jsonrpc?: unknown;
  id?: unknown;
  method?: unknown;
  params?: unknown;
};

type JsonRpcResponse =
  | {
      jsonrpc: "2.0";
      id: JsonRpcID;
      result: unknown;
    }
  | {
      jsonrpc: "2.0";
      id: JsonRpcID;
      error: {
        code: number;
        message: string;
        data?: unknown;
      };
    };

type McpTool = {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>;
};

type ToolCallParams = {
  name?: unknown;
  arguments?: unknown;
};

type CodexMcpServerOptions = {
  input?: Readable;
  output?: Writable;
  stderr?: Writable;
  configDir?: string;
};

type CodexMcpRequestContext = {
  configDir?: string;
};

const CODEX_MCP_PROTOCOL_VERSION = "2024-11-05";
const CODEX_MCP_SERVER_NAME = "geeagent-codex";
const CODEX_MCP_SERVER_VERSION = "0.1.0";

const emptyObjectSchema = {
  type: "object",
  properties: {},
  additionalProperties: false,
};

const codexExportOptionsProperties = {
  gear_roots: {
    type: "array",
    items: { type: "string" },
    description: "Optional Gear manifest root directories. Mainly for local development and tests.",
  },
  gear_id: {
    type: "string",
    description: "Optional Gear id filter.",
  },
  detail: {
    type: "string",
    enum: ["summary", "capabilities", "schema"],
    description: "Disclosure level for returned capability records.",
  },
  config_dir: {
    type: "string",
    description: "Optional GeeAgent config directory override.",
  },
};

const externalInvocationProperties = {
  caller: {
    type: "object",
    description: "Optional Codex caller metadata.",
    additionalProperties: true,
  },
  wait_ms: {
    type: "number",
    description: "How long the MCP tool should wait for GeeAgentMac to complete the external invocation.",
  },
  config_dir: {
    type: "string",
    description: "Optional GeeAgent config directory override.",
  },
};

export const CODEX_MCP_TOOLS: McpTool[] = [
  {
    name: "gee_status",
    description: "Report the GeeAgent Codex export bridge status and supported export standard.",
    inputSchema: emptyObjectSchema,
  },
  {
    name: "gee_list_capabilities",
    description: "List explicitly Codex-exported GeeAgent Gear capabilities.",
    inputSchema: {
      type: "object",
      properties: codexExportOptionsProperties,
      additionalProperties: false,
    },
  },
  {
    name: "gee_describe_capability",
    description: "Describe one explicitly Codex-exported GeeAgent Gear capability.",
    inputSchema: {
      type: "object",
      required: ["capability_ref"],
      properties: {
        ...codexExportOptionsProperties,
        capability_ref: {
          type: "string",
          description: "Capability reference in the form <gear_id>/<capability_id>.",
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: "gee_invoke_capability",
    description:
      "Queue an exported GeeAgent capability invocation for the live GeeAgent host bridge.",
    inputSchema: {
      type: "object",
      required: ["capability_ref"],
      properties: {
        capability_ref: {
          type: "string",
          description: "Capability reference in the form <gear_id>/<capability_id>.",
        },
        args: {
          type: "object",
          description: "Capability arguments validated by the GeeAgent Gear adapter.",
          additionalProperties: true,
        },
        ...externalInvocationProperties,
      },
      additionalProperties: false,
    },
  },
  {
    name: "gee_open_surface",
    description:
      "Queue a GeeAgent or Gear native surface open request for the live GeeAgent host bridge.",
    inputSchema: {
      type: "object",
      properties: {
        surface_id: { type: "string" },
        gear_id: { type: "string" },
        ...externalInvocationProperties,
      },
      additionalProperties: false,
    },
  },
  {
    name: "gee_get_invocation",
    description:
      "Fetch the status and artifacts for a prior external GeeAgent invocation. Returns pending or structured failure state when GeeAgentMac has not drained the queue.",
    inputSchema: {
      type: "object",
      required: ["invocation_id"],
      properties: {
        invocation_id: { type: "string" },
        config_dir: {
          type: "string",
          description: "Optional GeeAgent config directory override.",
        },
        caller: {
          type: "object",
          additionalProperties: true,
        },
      },
      additionalProperties: false,
    },
  },
];

export async function runCodexMcpServer(
  options: CodexMcpServerOptions = {},
): Promise<void> {
  const input = options.input ?? process.stdin;
  const output = options.output ?? process.stdout;
  const stderr = options.stderr ?? process.stderr;
  const lines = readline.createInterface({ input, crlfDelay: Infinity });

  for await (const line of lines) {
    if (!line.trim()) {
      continue;
    }
    const response = await handleCodexMcpLine(line, stderr, {
      configDir: options.configDir,
    });
    if (response) {
      output.write(`${JSON.stringify(response)}\n`);
    }
  }
}

export async function handleCodexMcpLine(
  line: string,
  stderr: Writable = process.stderr,
  context: CodexMcpRequestContext = {},
): Promise<JsonRpcResponse | null> {
  let request: JsonRpcRequest;
  try {
    request = JSON.parse(line) as JsonRpcRequest;
  } catch (error) {
    return rpcError(null, -32700, "Parse error", errorMessage(error));
  }

  try {
    return await handleCodexMcpRequest(request, context);
  } catch (error) {
    stderr.write(`codex MCP request failed: ${errorMessage(error)}\n`);
    return rpcError(jsonRpcID(request.id), -32603, "Internal error", errorMessage(error));
  }
}

export async function handleCodexMcpRequest(
  request: JsonRpcRequest,
  context: CodexMcpRequestContext = {},
): Promise<JsonRpcResponse | null> {
  const id = jsonRpcID(request.id);
  if (typeof request.method !== "string") {
    return rpcError(id, -32600, "Invalid Request", "method must be a string");
  }

  if (request.id === undefined) {
    return null;
  }

  switch (request.method) {
    case "initialize":
      return rpcResult(id, {
        protocolVersion: CODEX_MCP_PROTOCOL_VERSION,
        capabilities: {
          tools: {},
        },
        serverInfo: {
          name: CODEX_MCP_SERVER_NAME,
          version: CODEX_MCP_SERVER_VERSION,
        },
      });
    case "tools/list":
      return rpcResult(id, {
        tools: CODEX_MCP_TOOLS,
      });
    case "tools/call":
      return rpcResult(id, await callCodexMcpTool(request.params, context));
    default:
      return rpcError(id, -32601, "Method not found", request.method);
  }
}

async function callCodexMcpTool(
  params: unknown,
  context: CodexMcpRequestContext,
): Promise<Record<string, unknown>> {
  const call = objectRecord(params) as ToolCallParams | null;
  const toolName = typeof call?.name === "string" ? call.name : "";
  const args = objectRecord(call?.arguments) ?? {};

  switch (toolName) {
    case "gee_status":
      return mcpTextResult({
        ...codexExportStatus(),
        mcp_server: {
          name: CODEX_MCP_SERVER_NAME,
          tools: [
            ...IMPLEMENTED_CODEX_EXPORT_TOOLS,
            ...PLANNED_CODEX_EXPORT_TOOLS,
          ],
          bridge_required_for: [...LIVE_BRIDGE_CODEX_EXPORT_TOOLS],
        },
      });
    case "gee_list_capabilities":
      return mcpTextResult(await listCodexExportCapabilities(toCodexExportOptions(args)));
    case "gee_describe_capability":
      return mcpTextResult(await describeCodexExportCapability(toCodexExportOptions(args)));
    case "gee_invoke_capability":
      return mcpTextResult(await queueCapabilityInvocation(args, context));
    case "gee_open_surface":
      return mcpTextResult(await queueOpenSurface(args, context));
    case "gee_get_invocation":
      return mcpTextResult(await getInvocationResult(args, context));
    default:
      return {
        isError: true,
        content: [
          {
            type: "text",
            text: JSON.stringify(
              {
                status: "failed",
                standard: EXPORT_STANDARD,
                code: "gee.codex_export.tool_unknown",
                message: `Unknown Gee Codex MCP tool \`${toolName || "<missing>"}\`.`,
              },
              null,
              2,
            ),
          },
        ],
      };
  }
}

async function queueCapabilityInvocation(
  args: Record<string, unknown>,
  context: CodexMcpRequestContext,
): Promise<Record<string, unknown>> {
  const capabilityRef = stringValue(args.capability_ref);
  if (!capabilityRef) {
    return failed("gee.codex_export.capability_ref_missing", "required string `capability_ref` is missing");
  }
  const capability = await describeCodexExportCapability(toCodexExportOptions(args));
  if (capability.status !== "success") {
    return {
      ...capability,
      tool: "gee_invoke_capability",
      fallback_attempted: false,
    };
  }
  const configDir = configDirFor(args, context);
  const queued = await createExternalInvocation(configDir, {
    tool: "gee_invoke_capability",
    capability_ref: capabilityRef,
    gear_id: capability.capability.gear_id,
    capability_id: capability.capability.capability_id,
    args: objectRecord(args.args) ?? {},
    caller: callerRecord(args),
  });
  return await waitOrReturnInvocation(configDir, queued.external_invocation_id, waitMs(args));
}

async function queueOpenSurface(
  args: Record<string, unknown>,
  context: CodexMcpRequestContext,
): Promise<Record<string, unknown>> {
  const surfaceID = stringValue(args.surface_id) ?? stringValue(args.gear_id);
  if (!surfaceID) {
    return failed("gee.codex_export.surface_id_missing", "required string `surface_id` or `gear_id` is missing");
  }
  const configDir = configDirFor(args, context);
  const queued = await createExternalInvocation(configDir, {
    tool: "gee_open_surface",
    surface_id: surfaceID,
    gear_id: stringValue(args.gear_id) ?? surfaceID,
    caller: callerRecord(args),
  });
  return await waitOrReturnInvocation(configDir, queued.external_invocation_id, waitMs(args));
}

async function getInvocationResult(
  args: Record<string, unknown>,
  context: CodexMcpRequestContext,
): Promise<Record<string, unknown>> {
  const invocationID = stringValue(args.invocation_id);
  if (!invocationID) {
    return failed("gee.codex_export.invocation_id_missing", "required string `invocation_id` is missing");
  }
  const record = await getExternalInvocation(configDirFor(args, context), invocationID);
  if (!record) {
    return failed(
      "gee.codex_export.invocation_not_found",
      `External Gee invocation \`${invocationID}\` was not found.`,
    );
  }
  return record;
}

async function waitOrReturnInvocation(
  configDir: string,
  invocationID: string,
  waitMsValue: number,
): Promise<Record<string, unknown>> {
  const record = await waitForExternalInvocation(configDir, invocationID, waitMsValue);
  if (!record) {
    return failed(
      "gee.codex_export.invocation_not_found",
      `External Gee invocation \`${invocationID}\` was not found after it was queued.`,
    );
  }
  if (record.status === "pending" || record.status === "running") {
    return {
      ...record,
      message:
        "GeeAgentMac has not completed this external invocation yet. Use gee_get_invocation with the external_invocation_id to check again.",
      recovery: {
        kind: "start_or_focus_geeagent",
        message:
          "Start or focus GeeAgentMac so it can drain the external invocation queue through GearHost.",
      },
    };
  }
  return record;
}

function failed(code: string, message: string): Record<string, unknown> {
  return {
    status: "failed",
    standard: EXPORT_STANDARD,
    code,
    message,
    fallback_attempted: false,
  };
}

function summarizeExternalActionInput(args: Record<string, unknown>): Record<string, unknown> {
  const caller = objectRecord(args.caller);
  return {
    capability_ref: stringValue(args.capability_ref),
    gear_id: stringValue(args.gear_id),
    capability_id: stringValue(args.capability_id),
    surface_id: stringValue(args.surface_id),
    invocation_id: stringValue(args.invocation_id),
    caller:
      caller === null
        ? undefined
        : {
            client: stringValue(caller.client),
            thread_id: stringValue(caller.thread_id),
            cwd: stringValue(caller.cwd),
          },
  };
}

function toCodexExportOptions(args: Record<string, unknown>): CodexExportOptions {
  return {
    gear_roots: stringArray(args.gear_roots),
    gear_id: stringValue(args.gear_id),
    capability_ref: stringValue(args.capability_ref),
    detail: stringValue(args.detail),
  };
}

function configDirFor(args: Record<string, unknown>, context: CodexMcpRequestContext): string {
  return resolveConfigDir(stringValue(args.config_dir) ?? context.configDir);
}

function waitMs(args: Record<string, unknown>): number {
  const value = args.wait_ms;
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return 15_000;
  }
  return Math.max(0, Math.min(Math.trunc(value), 60_000));
}

function callerRecord(args: Record<string, unknown>): Record<string, unknown> | undefined {
  return objectRecord(args.caller) ?? undefined;
}

function mcpTextResult(payload: unknown): Record<string, unknown> {
  return {
    isError: false,
    content: [
      {
        type: "text",
        text: JSON.stringify(payload, null, 2),
      },
    ],
  };
}

function rpcResult(id: JsonRpcID, result: unknown): JsonRpcResponse {
  return {
    jsonrpc: "2.0",
    id,
    result,
  };
}

function rpcError(
  id: JsonRpcID,
  code: number,
  message: string,
  data?: unknown,
): JsonRpcResponse {
  return {
    jsonrpc: "2.0",
    id,
    error: {
      code,
      message,
      data,
    },
  };
}

function jsonRpcID(value: unknown): JsonRpcID {
  return typeof value === "string" || typeof value === "number" ? value : null;
}

function objectRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function stringArray(value: unknown): string[] | undefined {
  if (!Array.isArray(value)) {
    return undefined;
  }
  return value.filter((item): item is string => typeof item === "string" && item.trim().length > 0);
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0 ? value : undefined;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
