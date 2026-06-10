import { existsSync } from "node:fs";
import { readdir, readFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const AGENT_GATEWAY_STANDARD = "gee.agent_gateway.v0.1";
const DEFAULT_DETAIL = "summary";
const DEFAULT_CLIENT_ID = "codex";

export const IMPLEMENTED_AGENT_GATEWAY_TOOLS = [
  "gee_status",
  "gee_search_capabilities",
  "gee_describe_capability",
  "gee_run_capability",
  "gee_get_run",
  "gee_prepare_gear",
  "gee_open_surface",
] as const;
export const PLANNED_AGENT_GATEWAY_TOOLS = [] as const;
export const LIVE_BRIDGE_AGENT_GATEWAY_TOOLS = [
  "gee_run_capability",
  "gee_open_surface",
] as const;
export const SUPPORTED_AGENT_GATEWAY_CLIENTS = [
  "codex",
  "claude_code",
  "workbuddy",
  "gee_internal",
] as const;

type AgentGatewayStatus = "success" | "degraded" | "failed";

export type AgentGatewayOptions = {
  gear_roots?: string[];
  gear_id?: string;
  capability_ref?: string;
  detail?: string;
  query?: string;
  client?: string;
};

export type AgentGatewayIssue = {
  code: string;
  message: string;
  path?: string;
  gear_id?: string;
};

type CapabilityExportPolicy = {
  enabled?: unknown;
  clients?: unknown;
  client?: unknown;
  risk?: unknown;
  requires_approval?: unknown;
  skill_hint?: unknown;
  reason?: unknown;
};

type GearCapabilityManifest = {
  id?: unknown;
  title?: unknown;
  description?: unknown;
  examples?: unknown;
  input_schema?: unknown;
  output_schema?: unknown;
  side_effect?: unknown;
  permissions?: unknown;
  exports?: {
    agent_gateway?: CapabilityExportPolicy;
    codex?: CapabilityExportPolicy;
  };
};

type GearManifest = {
  schema?: unknown;
  id?: unknown;
  name?: unknown;
  description?: unknown;
  agent?: {
    enabled?: unknown;
    capabilities?: unknown;
  };
};

type ScannedGearManifest = {
  id: string;
  name: string;
  agent: {
    enabled: true;
    capabilities: unknown[];
  };
};

type ResolvedExportPolicy = {
  source: "agent_gateway" | "codex_compat";
  client: string;
  policy: CapabilityExportPolicy;
};

export type AgentGatewayCapability = {
  capability_ref: string;
  gear_id: string;
  gear_name: string;
  capability_id: string;
  title: string;
  description: string;
  examples: string[];
  client: string;
  export_policy_source: "agent_gateway" | "codex_compat";
  risk?: string;
  requires_approval?: boolean;
  side_effect?: string;
  skill_hint?: string;
  input_schema?: unknown;
  output_schema?: unknown;
  permissions?: string[];
};

export type AgentGatewayListResult = {
  status: AgentGatewayStatus;
  standard: string;
  bridge_state: "manifest_projection";
  default_export_policy: "explicit_only";
  client: string;
  capabilities: AgentGatewayCapability[];
  issues: AgentGatewayIssue[];
};

export type AgentGatewayDescribeResult =
  | {
      status: "success";
      standard: string;
      bridge_state: "manifest_projection";
      client: string;
      capability: AgentGatewayCapability;
      issues: AgentGatewayIssue[];
    }
  | {
      status: "failed";
      standard: string;
      client: string;
      code: string;
      message: string;
      issues: AgentGatewayIssue[];
    };

export type AgentGatewayStatusResult = {
  status: "success";
  standard: string;
  bridge_state: "manifest_projection_external_invocation_queue";
  implemented_tools: string[];
  planned_tools: string[];
  available_mcp_tools: string[];
  bridge_required_tools: string[];
  supported_clients: string[];
  default_client: string;
  transport_policy: {
    stdio: "implemented";
    streamable_http: "planned";
    http_local_only: true;
  };
};

export function agentGatewayStatus(
  options: Pick<AgentGatewayOptions, "client"> = {},
): AgentGatewayStatusResult {
  const client = clientID(options);
  return {
    status: "success",
    standard: AGENT_GATEWAY_STANDARD,
    bridge_state: "manifest_projection_external_invocation_queue",
    implemented_tools: [...IMPLEMENTED_AGENT_GATEWAY_TOOLS],
    planned_tools: [...PLANNED_AGENT_GATEWAY_TOOLS],
    available_mcp_tools: [
      ...IMPLEMENTED_AGENT_GATEWAY_TOOLS,
      ...PLANNED_AGENT_GATEWAY_TOOLS,
    ],
    bridge_required_tools: [...LIVE_BRIDGE_AGENT_GATEWAY_TOOLS],
    supported_clients: [...SUPPORTED_AGENT_GATEWAY_CLIENTS],
    default_client: client,
    transport_policy: {
      stdio: "implemented",
      streamable_http: "planned",
      http_local_only: true,
    },
  };
}

export async function searchAgentGatewayCapabilities(
  options: AgentGatewayOptions = {},
): Promise<AgentGatewayListResult> {
  const scan = await scanAgentGatewayCapabilities(options);
  return {
    status: scan.scannedRoots === 0 ? "failed" : scan.issues.length > 0 ? "degraded" : "success",
    standard: AGENT_GATEWAY_STANDARD,
    bridge_state: "manifest_projection",
    default_export_policy: "explicit_only",
    client: clientID(options),
    capabilities: filterDetail(filterQuery(scan.capabilities, options.query), options.detail),
    issues: scan.issues,
  };
}

export async function describeAgentGatewayCapability(
  options: AgentGatewayOptions = {},
): Promise<AgentGatewayDescribeResult> {
  const client = clientID(options);
  const capabilityRef = typeof options.capability_ref === "string" ? options.capability_ref.trim() : "";
  if (!capabilityRef) {
    return {
      status: "failed",
      standard: AGENT_GATEWAY_STANDARD,
      client,
      code: "gee.agent_gateway.capability_ref_missing",
      message: "required string `capability_ref` is missing",
      issues: [],
    };
  }

  const scan = await scanAgentGatewayCapabilities(options);
  const capability = scan.capabilities.find((record) => record.capability_ref === capabilityRef);
  if (!capability) {
    return {
      status: "failed",
      standard: AGENT_GATEWAY_STANDARD,
      client,
      code: "gee.agent_gateway.capability_not_found",
      message: `Agent-gateway capability \`${capabilityRef}\` was not found for client \`${client}\`.`,
      issues: scan.issues,
    };
  }

  return {
    status: "success",
    standard: AGENT_GATEWAY_STANDARD,
    bridge_state: "manifest_projection",
    client,
    capability,
    issues: scan.issues,
  };
}

export function parseAgentGatewayOptions(raw: string | undefined): AgentGatewayOptions {
  if (!raw || !raw.trim()) {
    return {};
  }
  const parsed = JSON.parse(raw) as unknown;
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("Agent Gateway options must be a JSON object");
  }
  return parsed as AgentGatewayOptions;
}

export function clientID(options: Pick<AgentGatewayOptions, "client"> = {}): string {
  return stringValue(options.client) ?? DEFAULT_CLIENT_ID;
}

async function scanAgentGatewayCapabilities(options: AgentGatewayOptions): Promise<{
  capabilities: AgentGatewayCapability[];
  issues: AgentGatewayIssue[];
  scannedRoots: number;
}> {
  const issues: AgentGatewayIssue[] = [];
  const capabilities: AgentGatewayCapability[] = [];
  let scannedRoots = 0;
  const client = clientID(options);

  for (const root of gearRoots(options)) {
    let entries;
    try {
      entries = await readdir(root, { withFileTypes: true });
      scannedRoots += 1;
    } catch (error) {
      issues.push({
        code: "gee.agent_gateway.gear_root_unavailable",
        message: error instanceof Error ? error.message : String(error),
        path: root,
      });
      continue;
    }

    for (const entry of entries) {
      if (!entry.isDirectory()) {
        continue;
      }
      const manifestPath = join(root, entry.name, "gear.json");
      const manifest = await readGearManifest(manifestPath, issues);
      if (!manifest) {
        continue;
      }
      if (options.gear_id && manifest.id !== options.gear_id) {
        continue;
      }
      capabilities.push(...exportedCapabilitiesForManifest(manifest, client));
    }
  }

  const uniqueCapabilities = uniqueCapabilitiesByRef(capabilities);
  uniqueCapabilities.sort((left, right) => left.capability_ref.localeCompare(right.capability_ref));
  return { capabilities: uniqueCapabilities, issues, scannedRoots };
}

function gearRoots(options: AgentGatewayOptions): string[] {
  const configured = Array.isArray(options.gear_roots)
    ? options.gear_roots.filter((root): root is string => typeof root === "string" && root.trim().length > 0)
    : [];
  const roots = configured.length > 0 ? configured : defaultGearRootCandidates();
  return [...new Set(roots.map((root) => resolve(root)))];
}

function defaultGearRootCandidates(): string[] {
  const cwd = resolve(process.cwd());
  const moduleDir = dirname(fileURLToPath(import.meta.url));
  const entrypointDir = process.argv[1]?.trim()
    ? dirname(resolve(process.argv[1]))
    : moduleDir;
  const pluginLocalCandidates = [
    resolve(entrypointDir, "../../../gears"),
    resolve(moduleDir, "../../../gears"),
  ];
  const uniquePluginLocalCandidates = [...new Set(pluginLocalCandidates)];
  const existingPluginLocalRoots = uniquePluginLocalCandidates.filter((candidate) => existsSync(candidate));
  if (existingPluginLocalRoots.length > 0) {
    return existingPluginLocalRoots;
  }

  const candidates = [
    resolve(cwd, "apps/macos-app/Gears"),
    resolve(cwd, "../macos-app/Gears"),
    resolve(moduleDir, "../../../macos-app/Gears"),
    resolve(entrypointDir, "../../../macos-app/Gears"),
  ];
  const unique = [...new Set(candidates)];
  const existing = unique.filter((candidate) => existsSync(candidate));
  if (existing.length > 0) {
    return existing;
  }
  return unique;
}

function uniqueCapabilitiesByRef(
  capabilities: AgentGatewayCapability[],
): AgentGatewayCapability[] {
  const recordsByRef = new Map<string, AgentGatewayCapability>();
  for (const capability of capabilities) {
    if (!recordsByRef.has(capability.capability_ref)) {
      recordsByRef.set(capability.capability_ref, capability);
    }
  }
  return [...recordsByRef.values()];
}

async function readGearManifest(
  manifestPath: string,
  issues: AgentGatewayIssue[],
): Promise<ScannedGearManifest | null> {
  let parsed: GearManifest;
  try {
    parsed = JSON.parse(await readFile(manifestPath, "utf8")) as GearManifest;
  } catch (error) {
    issues.push({
      code: "gee.agent_gateway.manifest_unreadable",
      message: error instanceof Error ? error.message : String(error),
      path: manifestPath,
    });
    return null;
  }

  if (
    parsed.schema !== "gee.gear.v1" ||
    typeof parsed.id !== "string" ||
    typeof parsed.name !== "string"
  ) {
    issues.push({
      code: "gee.agent_gateway.manifest_invalid",
      message: "Gear manifest must use schema `gee.gear.v1` and include string `id` and `name`.",
      path: manifestPath,
      gear_id: typeof parsed.id === "string" ? parsed.id : undefined,
    });
    return null;
  }

  if (!parsed.agent || parsed.agent.enabled !== true || !Array.isArray(parsed.agent.capabilities)) {
    return null;
  }

  return {
    id: parsed.id,
    name: parsed.name,
    agent: {
      enabled: true,
      capabilities: parsed.agent.capabilities,
    },
  };
}

function exportedCapabilitiesForManifest(
  manifest: ScannedGearManifest,
  client: string,
): AgentGatewayCapability[] {
  return manifest.agent.capabilities
    .filter(isCapabilityManifest)
    .flatMap((capability) => {
      const exportPolicy = resolvedExportPolicy(capability, client);
      if (!exportPolicy) {
        return [];
      }
      if (
        typeof capability.id !== "string" ||
        typeof capability.title !== "string" ||
        typeof capability.description !== "string"
      ) {
        return [];
      }
      return [
        {
          capability_ref: `${manifest.id}/${capability.id}`,
          gear_id: manifest.id,
          gear_name: manifest.name,
          capability_id: capability.id,
          title: capability.title,
          description: capability.description,
          examples: stringArray(capability.examples),
          client: exportPolicy.client,
          export_policy_source: exportPolicy.source,
          risk: stringValue(exportPolicy.policy.risk),
          requires_approval:
            typeof exportPolicy.policy.requires_approval === "boolean"
              ? exportPolicy.policy.requires_approval
              : undefined,
          side_effect: stringValue(capability.side_effect),
          skill_hint: stringValue(exportPolicy.policy.skill_hint),
          input_schema: capability.input_schema,
          output_schema: capability.output_schema,
          permissions: stringArray(capability.permissions),
        },
      ];
    });
}

function resolvedExportPolicy(
  capability: GearCapabilityManifest,
  client: string,
): ResolvedExportPolicy | null {
  const gatewayPolicy = capability.exports?.agent_gateway;
  if (gatewayPolicy) {
    if (gatewayPolicy.enabled === true && policyAllowsClient(gatewayPolicy, client)) {
      return {
        source: "agent_gateway",
        client,
        policy: gatewayPolicy,
      };
    }
    return null;
  }

  const codexPolicy = capability.exports?.codex;
  if (codexPolicy?.enabled === true) {
    return {
      source: "codex_compat",
      client,
      policy: codexPolicy,
    };
  }
  return null;
}

function policyAllowsClient(policy: CapabilityExportPolicy, client: string): boolean {
  const clients = clientList(policy.clients ?? policy.client);
  if (clients.length === 0) {
    return true;
  }
  return clients.includes(client) || clients.includes("*") || clients.includes("all");
}

function clientList(value: unknown): string[] {
  if (typeof value === "string" && value.trim()) {
    return [value.trim()];
  }
  if (!Array.isArray(value)) {
    return [];
  }
  return value.filter((item): item is string => typeof item === "string" && item.trim().length > 0);
}

function filterQuery(
  capabilities: AgentGatewayCapability[],
  query: string | undefined,
): AgentGatewayCapability[] {
  const normalized = query?.trim().toLowerCase();
  if (!normalized) {
    return capabilities;
  }
  return capabilities.filter((capability) =>
    [
      capability.capability_ref,
      capability.gear_id,
      capability.gear_name,
      capability.capability_id,
      capability.title,
      capability.description,
      capability.side_effect,
      capability.risk,
      ...capability.examples,
      ...(capability.permissions ?? []),
    ]
      .filter((value): value is string => typeof value === "string")
      .some((value) => value.toLowerCase().includes(normalized)),
  );
}

function filterDetail(
  capabilities: AgentGatewayCapability[],
  detail: string | undefined,
): AgentGatewayCapability[] {
  const normalized = detail ?? DEFAULT_DETAIL;
  return capabilities.map((capability) => {
    if (normalized === "schema") {
      return capability;
    }
    const {
      input_schema: _inputSchema,
      output_schema: _outputSchema,
      permissions: _permissions,
      ...summary
    } = capability;
    return summary;
  });
}

function isCapabilityManifest(value: unknown): value is GearCapabilityManifest {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string" && item.trim().length > 0)
    : [];
}

function stringValue(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}
