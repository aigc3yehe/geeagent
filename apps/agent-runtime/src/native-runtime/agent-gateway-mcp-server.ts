import readline from "node:readline";
import type { Readable, Writable } from "node:stream";

import {
  AGENT_GATEWAY_STANDARD,
  agentGatewayStatus,
  clientID,
  describeAgentGatewayCapability,
  IMPLEMENTED_AGENT_GATEWAY_TOOLS,
  LIVE_BRIDGE_AGENT_GATEWAY_TOOLS,
  PLANNED_AGENT_GATEWAY_TOOLS,
  searchAgentGatewayCapabilities,
  type AgentGatewayCapability,
  type AgentGatewayOptions,
} from "./agent-gateway.js";
import {
  createExternalInvocation,
  getExternalInvocation,
  waitForExternalInvocation,
  type ExternalInvocationResult,
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

type AgentGatewayMcpServerOptions = {
  input?: Readable;
  output?: Writable;
  stderr?: Writable;
  configDir?: string;
  client?: string;
};

type AgentGatewayMcpRequestContext = {
  configDir?: string;
  client?: string;
};

const AGENT_GATEWAY_MCP_PROTOCOL_VERSION = "2024-11-05";
const AGENT_GATEWAY_MCP_SERVER_NAME = "geeagent-gateway";
const AGENT_GATEWAY_MCP_SERVER_VERSION = "0.1.0";

const emptyObjectSchema = {
  type: "object",
  properties: {},
  additionalProperties: false,
};

const agentGatewayOptionsProperties = {
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
  query: {
    type: "string",
    description: "Optional text search across capability refs, titles, descriptions, examples, risk, side effects, and permissions.",
  },
};

const externalRunProperties = {
  caller: {
    type: "object",
    description: "Optional personal-agent caller metadata.",
    additionalProperties: true,
  },
  wait_ms: {
    type: "number",
    description: "How long the MCP tool should wait for GeeAgentMac to complete the run.",
  },
};

export const AGENT_GATEWAY_MCP_TOOLS: McpTool[] = [
  {
    name: "gee_status",
    description: "Report the GeeAgent personal-agent gateway status and supported tool contract.",
    inputSchema: emptyObjectSchema,
  },
  {
    name: "gee_search_capabilities",
    description: "Search manifest-exported GeeAgent Gear capabilities allowed for this personal-agent client.",
    inputSchema: {
      type: "object",
      properties: agentGatewayOptionsProperties,
      additionalProperties: false,
    },
  },
  {
    name: "gee_describe_capability",
    description: "Describe one manifest-exported GeeAgent Gear capability allowed for this personal-agent client.",
    inputSchema: {
      type: "object",
      required: ["capability_ref"],
      properties: {
        ...agentGatewayOptionsProperties,
        capability_ref: {
          type: "string",
          description: "Capability reference in the form <gear_id>/<capability_id>.",
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: "gee_run_capability",
    description:
      "Queue one exported GeeAgent capability invocation for the live GeeAgent host bridge.",
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
        ...externalRunProperties,
      },
      additionalProperties: false,
    },
  },
  {
    name: "gee_get_run",
    description:
      "Fetch the status and artifacts for a prior external GeeAgent run. Returns pending or structured failure state when GeeAgentMac has not drained the queue.",
    inputSchema: {
      type: "object",
      required: ["run_id"],
      properties: {
        run_id: { type: "string" },
        ...externalRunProperties,
      },
      additionalProperties: false,
    },
  },
  {
    name: "gee_prepare_gear",
    description:
      "Inspect Gear setup readiness for a Gear or capability. Installing dependencies is not performed by this MCP tool.",
    inputSchema: {
      type: "object",
      properties: {
        gear_id: { type: "string" },
        capability_ref: { type: "string" },
        action: {
          type: "string",
          enum: ["inspect", "prepare"],
          description: "Use inspect for status. prepare returns a structured blocked result until GeeAgentMac setup UI is implemented.",
        },
        ...externalRunProperties,
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
        ...externalRunProperties,
      },
      additionalProperties: false,
    },
  },
];

export async function runAgentGatewayMcpServer(
  options: AgentGatewayMcpServerOptions = {},
): Promise<void> {
  const input = options.input ?? process.stdin;
  const output = options.output ?? process.stdout;
  const stderr = options.stderr ?? process.stderr;
  const lines = readline.createInterface({ input, crlfDelay: Infinity });

  for await (const line of lines) {
    if (!line.trim()) {
      continue;
    }
    const response = await handleAgentGatewayMcpLine(line, stderr, {
      configDir: options.configDir,
      client: options.client,
    });
    if (response) {
      output.write(`${JSON.stringify(response)}\n`);
    }
  }
}

export async function handleAgentGatewayMcpLine(
  line: string,
  stderr: Writable = process.stderr,
  context: AgentGatewayMcpRequestContext = {},
): Promise<JsonRpcResponse | null> {
  let request: JsonRpcRequest;
  try {
    request = JSON.parse(line) as JsonRpcRequest;
  } catch (error) {
    return rpcError(null, -32700, "Parse error", errorMessage(error));
  }

  try {
    return await handleAgentGatewayMcpRequest(request, context);
  } catch (error) {
    stderr.write(`agent gateway MCP request failed: ${errorMessage(error)}\n`);
    return rpcError(jsonRpcID(request.id), -32603, "Internal error", errorMessage(error));
  }
}

export async function handleAgentGatewayMcpRequest(
  request: JsonRpcRequest,
  context: AgentGatewayMcpRequestContext = {},
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
        protocolVersion: AGENT_GATEWAY_MCP_PROTOCOL_VERSION,
        capabilities: {
          tools: {},
        },
        serverInfo: {
          name: AGENT_GATEWAY_MCP_SERVER_NAME,
          version: AGENT_GATEWAY_MCP_SERVER_VERSION,
        },
      });
    case "tools/list":
      return rpcResult(id, {
        tools: AGENT_GATEWAY_MCP_TOOLS,
      });
    case "tools/call":
      return rpcResult(id, await callAgentGatewayMcpTool(request.params, context));
    default:
      return rpcError(id, -32601, "Method not found", request.method);
  }
}

async function callAgentGatewayMcpTool(
  params: unknown,
  context: AgentGatewayMcpRequestContext,
): Promise<Record<string, unknown>> {
  const call = objectRecord(params) as ToolCallParams | null;
  const toolName = typeof call?.name === "string" ? call.name : "";
  const args = objectRecord(call?.arguments) ?? {};

  switch (toolName) {
    case "gee_status":
      return mcpTextResult({
        ...agentGatewayStatus(toAgentGatewayOptions(args, context)),
        mcp_server: {
          name: AGENT_GATEWAY_MCP_SERVER_NAME,
          tools: [
            ...IMPLEMENTED_AGENT_GATEWAY_TOOLS,
            ...PLANNED_AGENT_GATEWAY_TOOLS,
          ],
          bridge_required_for: [...LIVE_BRIDGE_AGENT_GATEWAY_TOOLS],
        },
      });
    case "gee_search_capabilities":
      return mcpTextResult(await searchAgentGatewayCapabilities(toAgentGatewayOptions(args, context)));
    case "gee_describe_capability":
      return mcpTextResult(await describeAgentGatewayCapability(toAgentGatewayOptions(args, context)));
    case "gee_run_capability":
      return mcpTextResult(await queueCapabilityRun(args, context));
    case "gee_get_run":
      return mcpTextResult(await getRunResult(args, context));
    case "gee_prepare_gear":
      return mcpTextResult(await prepareGear(args, context));
    case "gee_open_surface":
      return mcpTextResult(await queueOpenSurface(args, context));
    default:
      return {
        isError: true,
        content: [
          {
            type: "text",
            text: JSON.stringify(
              {
                status: "failed",
                standard: AGENT_GATEWAY_STANDARD,
                code: "gee.agent_gateway.tool_unknown",
                message: `Unknown Gee Agent Gateway MCP tool \`${toolName || "<missing>"}\`.`,
              },
              null,
              2,
            ),
          },
        ],
      };
  }
}

async function queueCapabilityRun(
  args: Record<string, unknown>,
  context: AgentGatewayMcpRequestContext,
): Promise<Record<string, unknown>> {
  const capabilityRef = stringValue(args.capability_ref);
  if (!capabilityRef) {
    return failed("gee.agent_gateway.capability_ref_missing", "required string `capability_ref` is missing");
  }
  const capability = await describeAgentGatewayCapability(toAgentGatewayOptions(args, context));
  if (capability.status !== "success") {
    return {
      ...capability,
      tool: "gee_run_capability",
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
    caller: callerRecord(args, context),
  });
  return await waitOrReturnRun(
    configDir,
    queued.external_invocation_id,
    waitMs(args, defaultWaitMsForCapability(capability.capability)),
  );
}

async function queueOpenSurface(
  args: Record<string, unknown>,
  context: AgentGatewayMcpRequestContext,
): Promise<Record<string, unknown>> {
  const surfaceID = stringValue(args.surface_id) ?? stringValue(args.gear_id);
  if (!surfaceID) {
    return failed("gee.agent_gateway.surface_id_missing", "required string `surface_id` or `gear_id` is missing");
  }
  const gearID = stringValue(args.gear_id) ?? surfaceID;
  const listed = await searchAgentGatewayCapabilities({
    ...toAgentGatewayOptions(args, context),
    gear_id: gearID,
    detail: "summary",
  });
  if (listed.capabilities.length === 0) {
    return {
      status: "failed",
      standard: AGENT_GATEWAY_STANDARD,
      client: listed.client,
      code: "gee.agent_gateway.surface_not_exported",
      message:
        `Gear surface \`${surfaceID}\` is not exported to client \`${listed.client}\`.`,
      issues: listed.issues,
      fallback_attempted: false,
    };
  }
  const configDir = configDirFor(args, context);
  const queued = await createExternalInvocation(configDir, {
    tool: "gee_open_surface",
    surface_id: surfaceID,
    gear_id: gearID,
    caller: callerRecord(args, context),
  });
  return await waitOrReturnRun(configDir, queued.external_invocation_id, waitMs(args, 15_000));
}

async function getRunResult(
  args: Record<string, unknown>,
  context: AgentGatewayMcpRequestContext,
): Promise<Record<string, unknown>> {
  const runID = stringValue(args.run_id);
  if (!runID) {
    return failed("gee.agent_gateway.run_id_missing", "required string `run_id` is missing");
  }
  const configDir = configDirFor(args, context);
  const waitMsValue = waitMs(args, 0);
  const record =
    waitMsValue > 0
      ? await waitForExternalInvocation(configDir, runID, waitMsValue)
      : await getExternalInvocation(configDir, runID);
  if (!record) {
    return failed(
      "gee.agent_gateway.run_not_found",
      `External Gee run \`${runID}\` was not found.`,
    );
  }
  return externalRunResult(record);
}

async function prepareGear(
  args: Record<string, unknown>,
  context: AgentGatewayMcpRequestContext,
): Promise<Record<string, unknown>> {
  const action = stringValue(args.action) ?? "inspect";
  if (action === "prepare") {
    return {
      status: "blocked",
      standard: AGENT_GATEWAY_STANDARD,
      code: "gee.agent_gateway.prepare_requires_geeagentmac",
      message:
        "Dependency installation is user-selected setup work owned by GeeAgentMac Settings and Gear setup surfaces.",
      fallback_attempted: false,
    };
  }

  const capabilityRef = stringValue(args.capability_ref);
  if (capabilityRef) {
    const described = await describeAgentGatewayCapability(toAgentGatewayOptions(args, context));
    if (described.status !== "success") {
      return {
        ...described,
        tool: "gee_prepare_gear",
        fallback_attempted: false,
      };
    }
    return {
      status: "success",
      standard: AGENT_GATEWAY_STANDARD,
      client: described.client,
      gear_id: described.capability.gear_id,
      capability_ref: capabilityRef,
      preparation_state: "live_status_unavailable",
      install_action_available: false,
      message:
        "The MCP gateway can verify exported capability metadata. Live dependency setup status is owned by GeeAgentMac.",
      fallback_attempted: false,
    };
  }

  const gearID = stringValue(args.gear_id);
  if (!gearID) {
    return failed("gee.agent_gateway.gear_id_missing", "required string `gear_id` or `capability_ref` is missing");
  }
  const listed = await searchAgentGatewayCapabilities({
    ...toAgentGatewayOptions(args, context),
    gear_id: gearID,
    detail: "summary",
  });
  return {
    status: listed.status,
    standard: AGENT_GATEWAY_STANDARD,
    client: listed.client,
    gear_id: gearID,
    preparation_state: "live_status_unavailable",
    install_action_available: false,
    exported_capability_count: listed.capabilities.length,
    issues: listed.issues,
    message:
      "The MCP gateway can inspect exported capability metadata. Live dependency setup status is owned by GeeAgentMac.",
    fallback_attempted: false,
  };
}

async function waitOrReturnRun(
  configDir: string,
  runID: string,
  waitMsValue: number,
): Promise<Record<string, unknown>> {
  const record = await waitForExternalInvocation(configDir, runID, waitMsValue);
  if (!record) {
    return failed(
      "gee.agent_gateway.run_not_found",
      `External Gee run \`${runID}\` was not found after it was queued.`,
    );
  }
  if (record.status === "pending" || record.status === "running") {
    return {
      ...externalRunResult(record),
      message:
        "GeeAgentMac has not completed this external run yet. Use gee_get_run with the run_id to check again.",
      recovery: {
        kind: "start_or_focus_geeagent",
        message:
          "Start or focus GeeAgentMac so it can drain the external run queue through GearHost.",
      },
    };
  }
  return externalRunResult(record);
}

function externalRunResult(record: ExternalInvocationResult): Record<string, unknown> {
  return {
    ...record,
    standard: AGENT_GATEWAY_STANDARD,
    run_id: record.external_invocation_id,
  };
}

function failed(code: string, message: string): Record<string, unknown> {
  return {
    status: "failed",
    standard: AGENT_GATEWAY_STANDARD,
    code,
    message,
    fallback_attempted: false,
  };
}

function toAgentGatewayOptions(
  args: Record<string, unknown>,
  context: AgentGatewayMcpRequestContext,
): AgentGatewayOptions {
  return {
    gear_roots: stringArray(args.gear_roots),
    gear_id: stringValue(args.gear_id),
    capability_ref: stringValue(args.capability_ref),
    detail: stringValue(args.detail),
    query: stringValue(args.query),
    client: mcpClientID(context),
  };
}

function configDirFor(_args: Record<string, unknown>, context: AgentGatewayMcpRequestContext): string {
  return resolveConfigDir(context.configDir);
}

function waitMs(args: Record<string, unknown>, defaultValue: number): number {
  const value = args.wait_ms;
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return defaultValue;
  }
  return Math.max(0, Math.min(Math.trunc(value), 60_000));
}

function defaultWaitMsForCapability(capability: AgentGatewayCapability): number {
  return capability.side_effect === "read_only" ? 2_000 : 15_000;
}

function callerRecord(
  args: Record<string, unknown>,
  context: AgentGatewayMcpRequestContext,
): Record<string, unknown> | undefined {
  const caller = objectRecord(args.caller) ?? {};
  return {
    ...caller,
    client: mcpClientID(context),
  };
}

function mcpClientID(context: AgentGatewayMcpRequestContext): string {
  return clientID({ client: context.client });
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
  if (typeof value !== "string") {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
