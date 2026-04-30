import { readdir, readFile } from "node:fs/promises";
import { join, resolve } from "node:path";

const EXPORT_STANDARD = "gee.capability_export.v0.1";
const DEFAULT_DETAIL = "summary";
const IMPLEMENTED_CODEX_EXPORT_TOOLS = [
  "gee_status",
  "gee_list_capabilities",
  "gee_describe_capability",
] as const;
const PLANNED_CODEX_EXPORT_TOOLS = [
  "gee_invoke_capability",
  "gee_open_surface",
  "gee_get_invocation",
] as const;

type CodexExportStatus = "success" | "degraded" | "failed";

type CodexExportOptions = {
  gear_roots?: string[];
  gear_id?: string;
  capability_ref?: string;
  detail?: string;
};

type CodexExportIssue = {
  code: string;
  message: string;
  path?: string;
  gear_id?: string;
};

type CodexExportPolicy = {
  enabled?: unknown;
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
    codex?: CodexExportPolicy;
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

export type CodexExportCapability = {
  capability_ref: string;
  gear_id: string;
  gear_name: string;
  capability_id: string;
  title: string;
  description: string;
  examples: string[];
  risk?: string;
  requires_approval?: boolean;
  side_effect?: string;
  skill_hint?: string;
  input_schema?: unknown;
  output_schema?: unknown;
  permissions?: string[];
};

export type CodexExportListResult = {
  status: CodexExportStatus;
  standard: string;
  bridge_state: "manifest_projection";
  default_export_policy: "explicit_only";
  capabilities: CodexExportCapability[];
  issues: CodexExportIssue[];
};

export type CodexExportDescribeResult =
  | {
      status: "success";
      standard: string;
      bridge_state: "manifest_projection";
      capability: CodexExportCapability;
      issues: CodexExportIssue[];
    }
  | {
      status: "failed";
      standard: string;
      code: string;
      message: string;
      issues: CodexExportIssue[];
    };

export type CodexExportStatusResult = {
  status: "success";
  standard: string;
  bridge_state: "manifest_projection";
  implemented_tools: string[];
  planned_tools: string[];
};

export function codexExportStatus(): CodexExportStatusResult {
  return {
    status: "success",
    standard: EXPORT_STANDARD,
    bridge_state: "manifest_projection",
    implemented_tools: [...IMPLEMENTED_CODEX_EXPORT_TOOLS],
    planned_tools: [...PLANNED_CODEX_EXPORT_TOOLS],
  };
}

export async function listCodexExportCapabilities(
  options: CodexExportOptions = {},
): Promise<CodexExportListResult> {
  const scan = await scanCodexExportCapabilities(options);
  return {
    status: scan.scannedRoots === 0 ? "failed" : scan.issues.length > 0 ? "degraded" : "success",
    standard: EXPORT_STANDARD,
    bridge_state: "manifest_projection",
    default_export_policy: "explicit_only",
    capabilities: filterDetail(scan.capabilities, options.detail),
    issues: scan.issues,
  };
}

export async function describeCodexExportCapability(
  options: CodexExportOptions = {},
): Promise<CodexExportDescribeResult> {
  const capabilityRef = typeof options.capability_ref === "string" ? options.capability_ref.trim() : "";
  if (!capabilityRef) {
    return {
      status: "failed",
      standard: EXPORT_STANDARD,
      code: "gee.codex_export.capability_ref_missing",
      message: "required string `capability_ref` is missing",
      issues: [],
    };
  }

  const scan = await scanCodexExportCapabilities(options);
  const capability = scan.capabilities.find((record) => record.capability_ref === capabilityRef);
  if (!capability) {
    return {
      status: "failed",
      standard: EXPORT_STANDARD,
      code: "gee.codex_export.capability_not_found",
      message: `Codex-exported capability \`${capabilityRef}\` was not found.`,
      issues: scan.issues,
    };
  }

  return {
    status: "success",
    standard: EXPORT_STANDARD,
    bridge_state: "manifest_projection",
    capability,
    issues: scan.issues,
  };
}

export function parseCodexExportOptions(raw: string | undefined): CodexExportOptions {
  if (!raw || !raw.trim()) {
    return {};
  }
  const parsed = JSON.parse(raw) as unknown;
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("Codex export options must be a JSON object");
  }
  return parsed as CodexExportOptions;
}

async function scanCodexExportCapabilities(options: CodexExportOptions): Promise<{
  capabilities: CodexExportCapability[];
  issues: CodexExportIssue[];
  scannedRoots: number;
}> {
  const issues: CodexExportIssue[] = [];
  const capabilities: CodexExportCapability[] = [];
  let scannedRoots = 0;

  for (const root of gearRoots(options)) {
    let entries;
    try {
      entries = await readdir(root, { withFileTypes: true });
      scannedRoots += 1;
    } catch (error) {
      issues.push({
        code: "gee.codex_export.gear_root_unavailable",
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
      capabilities.push(...exportedCapabilitiesForManifest(manifest));
    }
  }

  capabilities.sort((left, right) => left.capability_ref.localeCompare(right.capability_ref));
  return { capabilities, issues, scannedRoots };
}

function gearRoots(options: CodexExportOptions): string[] {
  const configured = Array.isArray(options.gear_roots)
    ? options.gear_roots.filter((root): root is string => typeof root === "string" && root.trim().length > 0)
    : [];
  const roots =
    configured.length > 0
      ? configured
      : [
          resolve(process.cwd(), "apps/macos-app/Gears"),
          resolve(process.cwd(), "../macos-app/Gears"),
        ];
  return [...new Set(roots.map((root) => resolve(root)))];
}

async function readGearManifest(
  manifestPath: string,
  issues: CodexExportIssue[],
): Promise<ScannedGearManifest | null> {
  let parsed: GearManifest;
  try {
    parsed = JSON.parse(await readFile(manifestPath, "utf8")) as GearManifest;
  } catch (error) {
    issues.push({
      code: "gee.codex_export.manifest_unreadable",
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
      code: "gee.codex_export.manifest_invalid",
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
): CodexExportCapability[] {
  return manifest.agent.capabilities
    .filter(isCapabilityManifest)
    .flatMap((capability) => {
      const policy = capability.exports?.codex;
      if (!policy || policy.enabled !== true) {
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
          risk: stringValue(policy.risk),
          requires_approval:
            typeof policy.requires_approval === "boolean" ? policy.requires_approval : undefined,
          side_effect: stringValue(capability.side_effect),
          skill_hint: stringValue(policy.skill_hint),
          input_schema: capability.input_schema,
          output_schema: capability.output_schema,
          permissions: stringArray(capability.permissions),
        },
      ];
    });
}

function filterDetail(
  capabilities: CodexExportCapability[],
  detail: string | undefined,
): CodexExportCapability[] {
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
  return typeof value === "string" && value.trim().length > 0 ? value : undefined;
}
