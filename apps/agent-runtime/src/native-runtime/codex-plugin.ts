import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join, relative, resolve, sep } from "node:path";

import { EXPORT_STANDARD } from "./codex-export.js";

type CodexPluginGenerationOptions = {
  output_dir?: unknown;
  runtime_command?: unknown;
  runtime_args?: unknown;
  marketplace_path?: unknown;
  marketplace_name?: unknown;
  marketplace_display_name?: unknown;
  marketplace_plugin_path?: unknown;
  marketplace_category?: unknown;
};

export type CodexPluginGenerationResult = {
  status: "success";
  standard: string;
  plugin_root: string;
  files: string[];
  mcp_server: {
    name: "geeagent";
    command: string;
    args: string[];
  };
  marketplace_file?: string;
};

const PLUGIN_NAME = "geeagent-codex";
const GENERATED_FILES = [
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
  await mkdir(join(pluginRoot, "skills", "gee-capabilities"), { recursive: true });

  await writeJson(join(pluginRoot, ".codex-plugin", "plugin.json"), pluginManifest());
  await writeJson(join(pluginRoot, ".mcp.json"), mcpConfig(command, args));
  await writeFile(
    join(pluginRoot, "skills", "gee-capabilities", "SKILL.md"),
    geeCapabilitiesSkill(),
    "utf8",
  );
  const marketplaceFile = await maybeRefreshMarketplace(options, pluginRoot);

  return {
    status: "success",
    standard: EXPORT_STANDARD,
    plugin_root: pluginRoot,
    files: [...GENERATED_FILES],
    mcp_server: {
      name: "geeagent",
      command,
      args,
    },
    marketplace_file: marketplaceFile,
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

function pluginManifest(): Record<string, unknown> {
  return {
    name: PLUGIN_NAME,
    version: "0.1.0",
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

function geeCapabilitiesSkill(): string {
  return `---
name: gee-capabilities
description: Use exported GeeAgent Gear capabilities from Codex through the local Gee MCP bridge.
---

# Gee Capabilities

Use this skill when the user asks Codex to inspect or use GeeAgent capabilities.

Workflow:

1. Call \`gee_status\` to verify the local export bridge state and supported export standard.
2. Call \`gee_list_capabilities\` with \`detail: "summary"\` to discover intentionally exported Gear capabilities.
3. Call \`gee_describe_capability\` before preparing non-trivial input or when schemas, permissions, side effects, or artifact semantics matter.
4. Call \`gee_invoke_capability\`, \`gee_open_surface\`, or \`gee_get_invocation\` only through the Gee MCP tools.

Rules:

- Gear remains the authoritative native package, permission, dependency, data, and execution boundary.
- Only use capabilities returned by \`gee_list_capabilities\`; do not infer hidden Gear capabilities.
- \`gee_invoke_capability\` and \`gee_open_surface\` create external invocations that GeeAgentMac drains through GearHost; use \`gee_get_invocation\` when a call returns \`pending\` or \`running\`.
- Do not run fallback scripts, package-local substitutes, shell shortcuts, or source-code workarounds when a Gee tool returns \`failed\`, \`blocked\`, or \`degraded\`.
- If the live GeeAgent host bridge is unavailable, report the structured Gee result and recovery guidance instead of claiming task completion.
- Preserve artifact references returned by Gee instead of copying large payloads into the conversation.
`;
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

function objectRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}
