import { mkdir, readFile, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join, relative, resolve, sep } from "node:path";

import {
  EXPORT_STANDARD,
  listCodexExportCapabilities,
  type CodexExportCapability,
  type CodexExportIssue,
} from "./codex-export.js";

type CodexPluginGenerationOptions = {
  output_dir?: unknown;
  runtime_command?: unknown;
  runtime_args?: unknown;
  gear_roots?: unknown;
  marketplace_path?: unknown;
  marketplace_name?: unknown;
  marketplace_display_name?: unknown;
  marketplace_plugin_path?: unknown;
  marketplace_category?: unknown;
};

type CodexPluginInstallOptions = CodexPluginGenerationOptions & {
  home_dir?: unknown;
};

export type CodexPluginGenerationResult = {
  status: "success";
  standard: string;
  plugin_root: string;
  files: string[];
  capability_index: {
    status: "success" | "degraded" | "failed";
    capability_count: number;
    files: string[];
    issues: CodexExportIssue[];
  };
  mcp_server: {
    name: "geeagent";
    command: string;
    args: string[];
  };
  marketplace_file?: string;
};

export type CodexPluginInstallResult = CodexPluginGenerationResult & {
  install_hint: string;
};

const PLUGIN_NAME = "geeagent-codex";
const PLUGIN_VERSION = "0.1.3";
const BASE_GENERATED_FILES = [
  ".codex-plugin/plugin.json",
  ".mcp.json",
  "skills/gee-capabilities/SKILL.md",
] as const;

export async function generateCodexPluginPackage(
  options: CodexPluginGenerationOptions,
): Promise<CodexPluginGenerationResult> {
  const pluginRoot = outputDir(options.output_dir);
  const defaultInvocation = defaultRuntimeInvocation();
  const command = stringValue(options.runtime_command) ?? defaultInvocation.command;
  const args = stringArray(options.runtime_args) ?? defaultInvocation.args;

  await mkdir(join(pluginRoot, ".codex-plugin"), { recursive: true });
  const skillRoot = join(pluginRoot, "skills", "gee-capabilities");
  await mkdir(skillRoot, { recursive: true });

  await writeJson(join(pluginRoot, ".codex-plugin", "plugin.json"), pluginManifest());
  await writeJson(join(pluginRoot, ".mcp.json"), mcpConfig(command, args));
  const capabilityReferences = await writeCapabilityReferences(skillRoot, options);
  await writeFile(
    join(skillRoot, "SKILL.md"),
    geeCapabilitiesSkill(capabilityReferences),
    "utf8",
  );
  const marketplaceFile = await maybeRefreshMarketplace(options, pluginRoot);
  const files = [...BASE_GENERATED_FILES, ...capabilityReferences.files].sort();

  return {
    status: "success",
    standard: EXPORT_STANDARD,
    plugin_root: pluginRoot,
    files,
    capability_index: {
      status: capabilityReferences.status,
      capability_count: capabilityReferences.capabilityCount,
      files: capabilityReferences.files,
      issues: capabilityReferences.issues,
    },
    mcp_server: {
      name: "geeagent",
      command,
      args,
    },
    marketplace_file: marketplaceFile,
  };
}

export async function installCodexPluginPackage(
  options: CodexPluginInstallOptions = {},
): Promise<CodexPluginInstallResult> {
  const home = resolve(stringValue(options.home_dir) ?? homedir());
  const pluginRoot =
    stringValue(options.output_dir) ?? join(home, "plugins", PLUGIN_NAME);
  const marketplacePath =
    stringValue(options.marketplace_path) ?? join(home, ".agents", "plugins", "marketplace.json");
  const result = await generateCodexPluginPackage({
    ...options,
    output_dir: pluginRoot,
    marketplace_path: marketplacePath,
    marketplace_name: stringValue(options.marketplace_name) ?? "geeagent-local",
    marketplace_display_name:
      stringValue(options.marketplace_display_name) ?? "GeeAgent Local",
    marketplace_plugin_path:
      stringValue(options.marketplace_plugin_path) ?? `./plugins/${PLUGIN_NAME}`,
  });
  return {
    ...result,
    install_hint:
      "Refresh Codex plugins, enable geeagent-codex, and keep GeeAgentMac running so it can drain Gear invocations through GearHost.",
  };
}

export function parseCodexPluginGenerationOptions(
  raw: string | undefined,
): CodexPluginGenerationOptions {
  if (!raw || !raw.trim()) {
    throw new Error("Codex plugin generation options JSON is required");
  }
  const parsed = JSON.parse(raw) as unknown;
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("Codex plugin generation options must be a JSON object");
  }
  return parsed as CodexPluginGenerationOptions;
}

export function parseCodexPluginInstallOptions(
  raw: string | undefined,
): CodexPluginInstallOptions {
  if (!raw || !raw.trim()) {
    return {};
  }
  const parsed = JSON.parse(raw) as unknown;
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("Codex plugin install options must be a JSON object");
  }
  return parsed as CodexPluginInstallOptions;
}

function pluginManifest(): Record<string, unknown> {
  return {
    name: PLUGIN_NAME,
    version: PLUGIN_VERSION,
    description:
      "Expose intentionally exported GeeAgent Gear capabilities to Codex through the local Gee MCP bridge.",
    author: {
      name: "GeeAgent",
    },
    license: "UNLICENSED",
    keywords: ["geeagent", "gear", "mcp", "codex"],
    skills: "./skills/",
    mcpServers: "./.mcp.json",
    interface: {
      displayName: "GeeAgent",
      shortDescription: "Use exported GeeAgent capabilities from Codex.",
      longDescription:
        "Connects Codex to GeeAgent's local MCP export bridge. Gear remains the authoritative native package and execution boundary.",
      developerName: "GeeAgent",
      category: "Productivity",
      capabilities: ["MCP", "Skills"],
      defaultPrompt: [
        "List exported GeeAgent capabilities.",
        "Describe a GeeAgent Gear capability.",
        "Invoke an exported GeeAgent capability through the live Gee bridge.",
      ],
      brandColor: "#0A84FF",
    },
  };
}

function mcpConfig(command: string, args: string[]): Record<string, unknown> {
  return {
    mcpServers: {
      geeagent: {
        command,
        args,
      },
    },
  };
}

function defaultRuntimeInvocation(): { command: string; args: string[] } {
  const entrypoint = process.argv[1]?.trim()
    ? resolve(process.argv[1])
    : resolve(process.cwd(), "dist/native-runtime/index.mjs");
  return {
    command: process.execPath,
    args: [...process.execArgv, entrypoint, "codex-mcp"],
  };
}

async function maybeRefreshMarketplace(
  options: CodexPluginGenerationOptions,
  pluginRoot: string,
): Promise<string | undefined> {
  const path = stringValue(options.marketplace_path);
  if (!path) {
    return undefined;
  }

  const marketplacePath = resolve(path);
  const marketplace = await readMarketplace(marketplacePath);
  const pluginPath =
    stringValue(options.marketplace_plugin_path) ??
    relativePluginPath(dirname(marketplacePath), pluginRoot);
  const category = stringValue(options.marketplace_category) ?? "Productivity";
  const existingInterface = objectRecord(marketplace.interface) ?? {};
  const existingPlugins = Array.isArray(marketplace.plugins)
    ? marketplace.plugins.filter(objectRecord)
    : [];
  const nextPlugins = existingPlugins.filter((entry) => entry.name !== PLUGIN_NAME);
  nextPlugins.push({
    name: PLUGIN_NAME,
    source: {
      source: "local",
      path: pluginPath,
    },
    policy: {
      installation: "AVAILABLE",
      authentication: "ON_INSTALL",
    },
    category,
  });

  await mkdir(dirname(marketplacePath), { recursive: true });
  await writeJson(marketplacePath, {
    ...marketplace,
    name: stringValue(marketplace.name) ?? stringValue(options.marketplace_name) ?? "geeagent-local",
    interface: {
      ...existingInterface,
      displayName:
        stringValue(existingInterface.displayName) ??
        stringValue(options.marketplace_display_name) ??
        "GeeAgent Local",
    },
    plugins: nextPlugins,
  });
  return marketplacePath;
}

async function readMarketplace(path: string): Promise<Record<string, unknown>> {
  try {
    const parsed = JSON.parse(await readFile(path, "utf8")) as unknown;
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("marketplace JSON must be an object");
    }
    return parsed as Record<string, unknown>;
  } catch (error) {
    if (error && typeof error === "object" && "code" in error && error.code === "ENOENT") {
      return {};
    }
    throw error;
  }
}

function relativePluginPath(marketplaceDir: string, pluginRoot: string): string {
  const normalized = relative(marketplaceDir, pluginRoot).split(sep).join("/");
  if (!normalized || normalized === ".") {
    return ".";
  }
  return normalized.startsWith(".") ? normalized : `./${normalized}`;
}

type CapabilityReferenceBuildResult = {
  status: "success" | "degraded" | "failed";
  capabilityCount: number;
  files: string[];
  issues: CodexExportIssue[];
  gearReferences: Array<{
    gear_id: string;
    gear_name: string;
    file: string;
    capability_count: number;
  }>;
};

async function writeCapabilityReferences(
  skillRoot: string,
  options: CodexPluginGenerationOptions,
): Promise<CapabilityReferenceBuildResult> {
  const referencesRoot = join(skillRoot, "references");
  await mkdir(referencesRoot, { recursive: true });
  const list = await listCodexExportCapabilities({
    detail: "schema",
    gear_roots: stringArray(options.gear_roots),
  });
  const capabilities = list.capabilities;
  const capabilitiesByGear = groupedCapabilities(capabilities);
  const gearReferences: CapabilityReferenceBuildResult["gearReferences"] = [];
  const files: string[] = [];

  for (const [gearID, gearCapabilities] of capabilitiesByGear.entries()) {
    const fileName = `${safeReferenceFileName(gearID)}.md`;
    const relativePath = `skills/gee-capabilities/references/${fileName}`;
    await writeFile(
      join(referencesRoot, fileName),
      gearReferenceMarkdown(gearID, gearCapabilities),
      "utf8",
    );
    files.push(relativePath);
    gearReferences.push({
      gear_id: gearID,
      gear_name: gearCapabilities[0]?.gear_name ?? gearID,
      file: `references/${fileName}`,
      capability_count: gearCapabilities.length,
    });
  }

  await writeFile(
    join(referencesRoot, "capability-index.md"),
    capabilityIndexMarkdown(list.status, capabilities, gearReferences, list.issues),
    "utf8",
  );
  files.push("skills/gee-capabilities/references/capability-index.md");

  return {
    status: list.status,
    capabilityCount: capabilities.length,
    files: files.sort(),
    issues: list.issues,
    gearReferences,
  };
}

function geeCapabilitiesSkill(references: CapabilityReferenceBuildResult): string {
  const gearReferenceLines = references.gearReferences.length === 0
    ? "- No offline Gear reference snapshot was generated. Use `gee_list_capabilities` as the live source of truth."
    : references.gearReferences
        .map((record) =>
          `- ${record.gear_name} (\`${record.gear_id}\`): \`${record.file}\` (${record.capability_count} exported capabilities)`,
        )
        .join("\n");
  return `---
name: gee-capabilities
description: Use exported GeeAgent Gear capabilities from Codex through the generated GeeAgent plugin skill and local Gee MCP bridge.
---

# Gee Capabilities

Use this skill when the user asks Codex to inspect, explain, or use GeeAgent Gear capabilities.

This skill is the first entry point for the GeeAgent Codex plugin. It explains what
the plugin is, where the generated capability manuals live, and how to call the
live Gee MCP bridge. The generated reference files are an offline manifest
snapshot; the live MCP tools remain the execution and validation source of truth.

Workflow:

1. Read \`references/capability-index.md\` when the user asks what Gee can do, when choosing among Gear capabilities, or when preparing an automation.
2. Read the referenced per-Gear manual only for the Gear you are about to use.
3. Call \`gee_status\` to verify the local export bridge state and supported export standard.
4. Call \`gee_list_capabilities\` with \`detail: "summary"\` to confirm the capability is intentionally exported in the live environment.
5. Call \`gee_describe_capability\` before preparing non-trivial input or when schemas, permissions, side effects, approvals, artifacts, or failure semantics matter.
6. Call \`gee_invoke_capability\`, \`gee_open_surface\`, or \`gee_get_invocation\` only through the Gee MCP tools.
7. If \`gee_invoke_capability\` or \`gee_open_surface\` returns \`pending\` or \`running\`, call \`gee_get_invocation\` with the returned invocation id until GeeAgentMac completes or returns a structured blocked/failed/degraded state.

Generated references:

- Capability index: \`references/capability-index.md\`
${gearReferenceLines}

Rules:

- Gear remains the authoritative native package, permission, dependency, data, and execution boundary.
- Only use capabilities returned by live \`gee_list_capabilities\`; do not infer hidden Gear capabilities from docs, source files, or memory.
- \`gee_invoke_capability\` and \`gee_open_surface\` create external invocations that GeeAgentMac drains through GearHost; use \`gee_get_invocation\` when a call returns \`pending\` or \`running\`.
- Do not run fallback scripts, package-local substitutes, shell shortcuts, or source-code workarounds when a Gee tool returns \`failed\`, \`blocked\`, or \`degraded\`.
- If the live GeeAgent host bridge is unavailable, report the structured Gee result and recovery guidance instead of claiming task completion.
- Provider-backed generation must only be invoked when the current user message explicitly asks for generation; do not create tasks speculatively.
- User-file capabilities must only use explicit local paths from the user or prior Gee results; do not scan the filesystem, expand globs, or invent paths in Codex.
- Push or notification capabilities require configured Gee channels and stable idempotency keys; do not call third-party APIs directly.
- Preserve artifact references returned by Gee instead of copying large payloads into the conversation.
`;
}

function capabilityIndexMarkdown(
  status: "success" | "degraded" | "failed",
  capabilities: CodexExportCapability[],
  gearReferences: CapabilityReferenceBuildResult["gearReferences"],
  issues: CodexExportIssue[],
): string {
  const gearLines = gearReferences.length === 0
    ? "- No Codex-exported Gear capabilities were found in the manifest snapshot."
    : gearReferences
        .map((record) =>
          `- [${escapeMarkdown(record.gear_name)}](./${record.file.replace(/^references\//, "")}) (\`${record.gear_id}\`): ${record.capability_count} exported capabilities`,
        )
        .join("\n");
  const capabilityLines = capabilities.length === 0
    ? "- None."
    : capabilities
        .map((capability) =>
          `- \`${capability.capability_ref}\` - ${escapeMarkdown(capability.title)}; risk: ${capability.risk ?? "unspecified"}; side effect: ${capability.side_effect ?? "unspecified"}`,
        )
        .join("\n");
  const issueLines = issues.length === 0
    ? "- None."
    : issues
        .map((issue) =>
          `- \`${issue.code}\`${issue.gear_id ? ` for \`${issue.gear_id}\`` : ""}${issue.path ? ` at \`${issue.path}\`` : ""}: ${escapeMarkdown(issue.message)}`,
        )
        .join("\n");

  return `# GeeAgent Capability Index

Generated from Gear manifests for the GeeAgent Codex plugin.

This file is an offline snapshot for orientation. Before invoking anything,
confirm availability with \`gee_list_capabilities\` and validate arguments with
\`gee_describe_capability\`.

- Export standard: \`${EXPORT_STANDARD}\`
- Snapshot status: \`${status}\`
- Exported capability count: ${capabilities.length}

## Gear Manuals

${gearLines}

## Exported Capabilities

${capabilityLines}

## Snapshot Issues

${issueLines}
`;
}

function gearReferenceMarkdown(
  gearID: string,
  capabilities: CodexExportCapability[],
): string {
  const gearName = capabilities[0]?.gear_name ?? gearID;
  const capabilitySections = capabilities.map(capabilityMarkdown).join("\n\n");
  return `# ${escapeMarkdown(gearName)}

Gear id: \`${gearID}\`

This file is a generated Codex-facing manual for exported GeeAgent capabilities
in this Gear. The live Gee MCP bridge is authoritative: call
\`gee_list_capabilities\` and \`gee_describe_capability\` before invoking.

${capabilitySections || "No exported capabilities were present when this reference was generated."}
`;
}

function capabilityMarkdown(capability: CodexExportCapability): string {
  const requiredArgs = schemaRequiredArgs(capability.input_schema);
  const optionalArgs = schemaOptionalArgs(capability.input_schema, requiredArgs);
  const propertyLines = schemaPropertyLines(capability.input_schema);
  const examples = capability.examples.length === 0
    ? "- None."
    : capability.examples.map((example) => `- ${escapeMarkdown(example)}`).join("\n");
  const permissions = capability.permissions && capability.permissions.length > 0
    ? capability.permissions.map((permission) => `\`${permission}\``).join(", ")
    : "none declared";
  const hint = capability.skill_hint
    ? `\nCodex hint: ${escapeMarkdown(capability.skill_hint)}\n`
    : "";

  return `## ${escapeMarkdown(capability.title)}

- Capability ref: \`${capability.capability_ref}\`
- Capability id: \`${capability.capability_id}\`
- Description: ${escapeMarkdown(capability.description)}
- Risk: \`${capability.risk ?? "unspecified"}\`
- Requires approval: \`${capability.requires_approval === undefined ? "unspecified" : String(capability.requires_approval)}\`
- Side effect: \`${capability.side_effect ?? "unspecified"}\`
- Permissions: ${permissions}
- Required args: ${requiredArgs.length > 0 ? requiredArgs.map((arg) => `\`${arg}\``).join(", ") : "none"}
- Optional args: ${optionalArgs.length > 0 ? optionalArgs.map((arg) => `\`${arg}\``).join(", ") : "none"}
${hint}
Examples:

${examples}

Argument notes:

${propertyLines}

Invoke through Gee MCP:

\`\`\`json
${JSON.stringify(invocationTemplate(capability, requiredArgs), null, 2)}
\`\`\`

After invocation, preserve returned artifacts and structured status. If the
result is \`pending\` or \`running\`, call \`gee_get_invocation\` with the
returned invocation id.`;
}

function invocationTemplate(
  capability: CodexExportCapability,
  requiredArgs: string[],
): Record<string, unknown> {
  return {
    capability_ref: capability.capability_ref,
    args: schemaArgsTemplate(capability.input_schema, requiredArgs),
    wait_ms: 30000,
    caller: {
      client: "codex",
      thread_id: "<codex-thread-id>",
      cwd: "<current-working-directory>",
    },
  };
}

function groupedCapabilities(
  capabilities: CodexExportCapability[],
): Map<string, CodexExportCapability[]> {
  const groups = new Map<string, CodexExportCapability[]>();
  for (const capability of capabilities) {
    const group = groups.get(capability.gear_id) ?? [];
    group.push(capability);
    groups.set(capability.gear_id, group);
  }
  return new Map(
    [...groups.entries()]
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([gearID, records]) => [
        gearID,
        records.sort((left, right) => left.capability_ref.localeCompare(right.capability_ref)),
      ]),
  );
}

function schemaRequiredArgs(schema: unknown): string[] {
  const record = objectRecord(schema);
  return stringList(record?.required);
}

function schemaOptionalArgs(schema: unknown, requiredArgs: string[]): string[] {
  const record = objectRecord(schema);
  const properties = objectRecord(record?.properties) ?? {};
  const required = new Set(requiredArgs);
  return Object.keys(properties).filter((key) => !required.has(key)).sort();
}

function schemaPropertyLines(schema: unknown): string {
  const record = objectRecord(schema);
  const properties = objectRecord(record?.properties);
  if (!properties || Object.keys(properties).length === 0) {
    return "- No argument properties are declared in the manifest snapshot.";
  }
  return Object.entries(properties)
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([name, value]) => {
      const property = objectRecord(value) ?? {};
      const type = typeof property.type === "string" ? property.type : "unknown";
      const enumValues = stringList(property.enum);
      const description = stringValue(property.description);
      const pieces = [`type: \`${type}\``];
      if (enumValues.length > 0) {
        pieces.push(`enum: ${enumValues.map((item) => `\`${item}\``).join(", ")}`);
      }
      if (typeof property.minimum === "number") {
        pieces.push(`minimum: \`${property.minimum}\``);
      }
      if (typeof property.maximum === "number") {
        pieces.push(`maximum: \`${property.maximum}\``);
      }
      if (typeof property.maxItems === "number") {
        pieces.push(`maxItems: \`${property.maxItems}\``);
      }
      if (description) {
        pieces.push(escapeMarkdown(description));
      }
      return `- \`${name}\`: ${pieces.join("; ")}`;
    })
    .join("\n");
}

function schemaArgsTemplate(schema: unknown, requiredArgs: string[]): Record<string, unknown> {
  const record = objectRecord(schema);
  const properties = objectRecord(record?.properties) ?? {};
  const names = requiredArgs.length > 0
    ? requiredArgs
    : Object.keys(properties).sort().slice(0, 5);
  return Object.fromEntries(
    names.map((name) => [name, placeholderForProperty(objectRecord(properties[name]))]),
  );
}

function placeholderForProperty(property: Record<string, unknown> | null): unknown {
  if (!property) {
    return "<value>";
  }
  const enumValues = stringList(property.enum);
  if (enumValues.length > 0) {
    return `<one of: ${enumValues.join(" | ")}>`;
  }
  switch (property.type) {
    case "boolean":
      return false;
    case "integer":
    case "number":
      return 0;
    case "array":
      return [];
    case "object":
      return {};
    case "string":
      return "<string>";
    default:
      return "<value>";
  }
}

function safeReferenceFileName(value: string): string {
  return value.replace(/[^A-Za-z0-9._-]+/g, "-") || "gear";
}

function escapeMarkdown(value: string): string {
  return value.replace(/\|/g, "\\|");
}

async function writeJson(path: string, value: unknown): Promise<void> {
  await writeFile(path, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function outputDir(value: unknown): string {
  const path = stringValue(value);
  if (!path) {
    throw new Error("Codex plugin generation requires string `output_dir`");
  }
  return resolve(path);
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0 ? value : undefined;
}

function stringArray(value: unknown): string[] | undefined {
  if (!Array.isArray(value)) {
    return undefined;
  }
  return value.filter((item): item is string => typeof item === "string" && item.trim().length > 0);
}

function stringList(value: unknown): string[] {
  return stringArray(value) ?? [];
}

function objectRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}
