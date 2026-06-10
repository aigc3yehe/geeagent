import { resolve } from "node:path";

import {
  AGENT_GATEWAY_STANDARD,
  SUPPORTED_AGENT_GATEWAY_CLIENTS,
} from "./agent-gateway.js";

const EXTERNAL_AGENT_GATEWAY_CLIENTS = [
  {
    client_id: "codex",
    title: "Codex",
    priority: 1,
    config_targets: [
      "Codex plugin .mcp.json",
      "Codex MCP server configuration",
    ],
  },
  {
    client_id: "claude_code",
    title: "Claude Code",
    priority: 2,
    config_targets: [
      "Claude Code MCP server entry",
      "Project or user-level Claude Code MCP configuration",
    ],
  },
  {
    client_id: "workbuddy",
    title: "WorkBuddy / OpenClaw",
    priority: 3,
    config_targets: [
      "OpenClaw-compatible MCP server configuration",
      "WorkBuddy local tool settings",
    ],
  },
] as const;

type AgentGatewayClientStatusOptions = {
  runtime_command?: unknown;
  runtime_entrypoint?: unknown;
  config_dir?: unknown;
};

export type AgentGatewayClientIntegrationRecord = {
  client_id: string;
  title: string;
  priority: number;
  integration_state: "configuration_available";
  connection_state: "not_verified";
  transport: "stdio";
  install_policy: "manual_user_action_required";
  fallback_attempted: false;
  mcp_server: {
    name: "geeagent";
    command: string;
    args: string[];
  };
  config_targets: string[];
  config_snippets: Array<{
    label: string;
    format: "json" | "shell";
    body: string;
  }>;
  notes: string[];
};

export type AgentGatewayClientStatusResult = {
  status: "success";
  standard: string;
  client_count: number;
  default_priority: string[];
  supported_clients: string[];
  runtime_entrypoint: string;
  config_dir?: string;
  clients: AgentGatewayClientIntegrationRecord[];
};

export function agentGatewayClientStatus(
  options: AgentGatewayClientStatusOptions = {},
): AgentGatewayClientStatusResult {
  const command = stringValue(options.runtime_command) ?? process.execPath;
  const runtimeEntrypoint =
    stringValue(options.runtime_entrypoint) ?? stableNativeRuntimeEntrypoint(currentRuntimeEntrypoint());
  const configDir = stringValue(options.config_dir);
  const clients = EXTERNAL_AGENT_GATEWAY_CLIENTS.map((client) =>
    clientIntegrationRecord({
      clientID: client.client_id,
      title: client.title,
      priority: client.priority,
      configTargets: [...client.config_targets],
      command,
      runtimeEntrypoint,
      configDir,
    }),
  );

  return {
    status: "success",
    standard: AGENT_GATEWAY_STANDARD,
    client_count: clients.length,
    default_priority: clients.map((client) => client.client_id),
    supported_clients: [...SUPPORTED_AGENT_GATEWAY_CLIENTS],
    runtime_entrypoint: runtimeEntrypoint,
    config_dir: configDir,
    clients,
  };
}

export function parseAgentGatewayClientStatusOptions(
  raw: string | undefined,
): AgentGatewayClientStatusOptions {
  if (!raw || !raw.trim()) {
    return {};
  }
  const parsed = JSON.parse(raw) as unknown;
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("Agent Gateway client status options must be a JSON object");
  }
  return parsed as AgentGatewayClientStatusOptions;
}

function clientIntegrationRecord(options: {
  clientID: string;
  title: string;
  priority: number;
  configTargets: string[];
  command: string;
  runtimeEntrypoint: string;
  configDir?: string;
}): AgentGatewayClientIntegrationRecord {
  const args = gatewayServerArgs(options.runtimeEntrypoint, options.clientID, options.configDir);
  const jsonSnippet = JSON.stringify(
    {
      mcpServers: {
        geeagent: {
          command: options.command,
          args,
        },
      },
    },
    null,
    2,
  );
  const shellSnippet = shellSnippetForClient(options.clientID, options.command, args);

  return {
    client_id: options.clientID,
    title: options.title,
    priority: options.priority,
    integration_state: "configuration_available",
    connection_state: "not_verified",
    transport: "stdio",
    install_policy: "manual_user_action_required",
    fallback_attempted: false,
    mcp_server: {
      name: "geeagent",
      command: options.command,
      args,
    },
    config_targets: options.configTargets,
    config_snippets: [
      {
        label: "MCP server JSON",
        format: "json",
        body: jsonSnippet,
      },
      ...(shellSnippet
        ? [
            {
              label: "Command",
              format: "shell" as const,
              body: shellSnippet,
            },
          ]
        : []),
    ],
    notes: notesForClient(options.clientID),
  };
}

function gatewayServerArgs(
  runtimeEntrypoint: string,
  clientID: string,
  configDir: string | undefined,
): string[] {
  const args = [runtimeEntrypoint, "agent-gateway-mcp", "--client", clientID];
  if (configDir) {
    args.push("--config-dir", configDir);
  }
  return args;
}

function shellSnippetForClient(
  clientID: string,
  command: string,
  args: string[],
): string | undefined {
  if (clientID !== "claude_code") {
    return undefined;
  }
  return ["claude", "mcp", "add", "geeagent", "--", command, ...args]
    .map(shellEscape)
    .join(" ");
}

function notesForClient(clientID: string): string[] {
  switch (clientID) {
    case "codex":
      return [
        "Codex can use either the generated GeeAgent Codex plugin or this neutral Agent Gateway MCP server.",
        "Use the Codex plugin when you want offline capability reference files; use this server for the shared multi-agent entrypoint.",
      ];
    case "claude_code":
      return [
        "GeeAgent exposes the same stdio MCP server to Claude Code through a manual MCP server entry.",
        "GeeAgentMac must stay running for live Gear execution and surface-opening tools.",
      ];
    case "workbuddy":
      return [
        "WorkBuddy/OpenClaw should use the JSON MCP server entry if it supports stdio MCP tools.",
        "GeeAgent does not auto-write WorkBuddy settings until the user chooses an installer action.",
      ];
    default:
      return [];
  }
}

function currentRuntimeEntrypoint(): string {
  return process.argv[1]?.trim()
    ? resolve(process.argv[1])
    : resolve(process.cwd(), "dist/native-runtime/index.mjs");
}

function stableNativeRuntimeEntrypoint(entrypoint: string): string {
  const normalized = resolve(entrypoint);
  const sourceEntrypointSuffix = "src/native-runtime/index.ts";
  if (!normalized.endsWith(sourceEntrypointSuffix)) {
    return normalized;
  }
  const packageRoot = normalized.slice(0, -sourceEntrypointSuffix.length);
  return resolve(packageRoot, "dist/native-runtime/index.mjs");
}

function shellEscape(value: string): string {
  if (/^[A-Za-z0-9_/:=.,@%+-]+$/.test(value)) {
    return value;
  }
  return `'${value.replaceAll("'", "'\\''")}'`;
}

function stringValue(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}
