import { execFile } from "node:child_process";
import { mkdtemp, readdir, readFile, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { isAbsolute, join, resolve } from "node:path";
import { promisify } from "node:util";

import type { AgentProfile } from "./types.js";

const execFileAsync = promisify(execFile);

type AgentPackManifest = {
  definition_version?: string;
  id?: string;
  name?: string;
  tagline?: string;
  identity_prompt_path?: string;
  soul_path?: string;
  playbook_path?: string;
  tools_context_path?: string;
  memory_seed_path?: string;
  heartbeat_path?: string;
  appearance?: Record<string, unknown>;
  skills?: Array<{ id: string; path?: string }>;
  allowed_tool_ids?: string[];
  source?: string;
  version?: string;
};

export async function preparePackRoot(rawPath: string): Promise<string> {
  const packPath = resolve(rawPath.trim());
  if (await isDirectory(packPath)) {
    return normalizedPackRoot(packPath);
  }
  if (!packPath.toLowerCase().endsWith(".zip")) {
    throw new Error(`agent definition import expects a directory or .zip archive, got \`${packPath}\``);
  }
  const extractDir = await mkdtemp(join(tmpdir(), "geeagent-agent-pack-"));
  await execFileAsync("/usr/bin/ditto", ["-x", "-k", packPath, extractDir]);
  return normalizedPackRoot(extractDir);
}

export async function loadRuntimeProfileFromPack(
  root: string,
  forcedSource?: string,
): Promise<AgentProfile> {
  const manifest = await readPackManifest(root);
  const source = forcedSource ?? manifest.source ?? "module_pack";
  if (source === "first_party") {
    throw new Error("source `first_party` is reserved and cannot be imported from an agent definition");
  }
  return validateProfile({
    id: requireString(manifest.id, "id"),
    name: requireString(manifest.name, "name"),
    tagline: requireString(manifest.tagline, "tagline"),
    personality_prompt: await compilePrompt(root, manifest),
    appearance: resolveAppearance(root, manifest.appearance),
    skills: resolveSkills(root, manifest.skills ?? []),
    ...(manifest.allowed_tool_ids ? { allowed_tool_ids: manifest.allowed_tool_ids } : {}),
    source,
    version: requireString(manifest.version, "version"),
  });
}

async function readPackManifest(root: string): Promise<AgentPackManifest> {
  const manifest = JSON.parse(await readFile(join(root, "agent.json"), "utf8")) as AgentPackManifest;
  if (manifest.definition_version !== "2") {
    throw new Error(
      manifest.definition_version
        ? `[pack.unsupported_definition_version] unsupported definition_version \`${manifest.definition_version}\` (expected \`2\`)`
        : "[pack.missing_definition_version] missing definition_version in agent.json",
    );
  }
  return manifest;
}

async function compilePrompt(root: string, manifest: AgentPackManifest): Promise<string> {
  const sections: Array<[string, string | undefined, string]> = [
    ["IDENTITY", manifest.identity_prompt_path, "identity_prompt_path"],
    ["SOUL", manifest.soul_path, "soul_path"],
    ["PLAYBOOK", manifest.playbook_path, "playbook_path"],
    ["TOOLS", manifest.tools_context_path, "tools_context_path"],
    ["MEMORY", manifest.memory_seed_path, "memory_seed_path"],
    ["HEARTBEAT", manifest.heartbeat_path, "heartbeat_path"],
  ];
  const compiled: string[] = [];
  for (const [title, relativePath, field] of sections) {
    if (!relativePath) {
      if (["IDENTITY", "SOUL", "PLAYBOOK"].includes(title)) {
        throw new Error(`[pack.invalid_profile] missing required layered file path \`${field}\` in agent.json`);
      }
      continue;
    }
    const body = (await readFile(resolvePackPath(root, relativePath, field), "utf8")).trim();
    if (!body) {
      throw new Error(`[pack.invalid_profile] ${field} cannot point at an empty file`);
    }
    compiled.push(`[${title}]\n${body}`);
  }
  return compiled.join("\n\n");
}

function resolveAppearance(
  root: string,
  appearance: Record<string, unknown> | undefined,
): Record<string, unknown> {
  if (!appearance) {
    return { kind: "abstract" };
  }

  const live2DBundlePath =
    resolveOptionalAppearancePath(root, appearance.live2d_bundle_path, "appearance.live2d_bundle_path") ??
    resolveOptionalAppearancePath(root, recordValue(appearance.live2d)?.bundle_path, "appearance.live2d.bundle_path") ??
    (appearance.kind === "live2d"
      ? resolveOptionalAppearancePath(root, appearance.bundle_path, "appearance.bundle_path")
      : undefined);
  const videoAssetPath =
    resolveOptionalAppearancePath(root, appearance.video_asset_path, "appearance.video_asset_path") ??
    resolveOptionalAppearancePath(root, recordValue(appearance.video)?.asset_path, "appearance.video.asset_path") ??
    (appearance.kind === "video"
      ? resolveOptionalAppearancePath(root, appearance.asset_path, "appearance.asset_path")
      : undefined);
  const imageAssetPath =
    resolveOptionalAppearancePath(root, appearance.image_asset_path, "appearance.image_asset_path") ??
    resolveOptionalAppearancePath(root, appearance.static_image_asset_path, "appearance.static_image_asset_path") ??
    resolveOptionalAppearancePath(root, recordValue(appearance.image)?.asset_path, "appearance.image.asset_path") ??
    resolveOptionalAppearancePath(root, recordValue(appearance.static_image)?.asset_path, "appearance.static_image.asset_path") ??
    (appearance.kind === "static_image"
      ? resolveOptionalAppearancePath(root, appearance.asset_path, "appearance.asset_path")
      : undefined);
  const globalBackground = resolveGlobalBackground(root, recordValue(appearance.global_background));
  const kind = live2DBundlePath
    ? "live2d"
    : videoAssetPath
      ? "video"
      : imageAssetPath
        ? "static_image"
        : "abstract";
  const normalized: Record<string, unknown> = { kind };

  if (live2DBundlePath) {
    normalized.live2d_bundle_path = live2DBundlePath;
  }
  if (videoAssetPath) {
    normalized.video_asset_path = videoAssetPath;
  }
  if (imageAssetPath) {
    normalized.image_asset_path = imageAssetPath;
  }
  if (globalBackground) {
    normalized.global_background = globalBackground;
  }

  if (kind === "live2d") {
    normalized.bundle_path = live2DBundlePath;
  } else if (kind === "video") {
    normalized.asset_path = videoAssetPath;
  } else if (kind === "static_image") {
    normalized.asset_path = imageAssetPath;
  }

  return normalized;
}

function resolveGlobalBackground(
  root: string,
  background: Record<string, unknown> | undefined,
): Record<string, unknown> | undefined {
  if (!background) {
    return undefined;
  }
  const videoAssetPath =
    resolveOptionalAppearancePath(root, background.video_asset_path, "appearance.global_background.video_asset_path") ??
    resolveOptionalAppearancePath(root, background.video_path, "appearance.global_background.video_path") ??
    (background.kind === "video"
      ? resolveOptionalAppearancePath(root, background.asset_path, "appearance.global_background.asset_path")
      : undefined);
  const imageAssetPath =
    resolveOptionalAppearancePath(root, background.image_asset_path, "appearance.global_background.image_asset_path") ??
    resolveOptionalAppearancePath(root, background.image_path, "appearance.global_background.image_path") ??
    (background.kind === "static_image" || background.kind === "image"
      ? resolveOptionalAppearancePath(root, background.asset_path, "appearance.global_background.asset_path")
      : undefined);

  if (videoAssetPath) {
    return {
      kind: "video",
      asset_path: videoAssetPath,
      video_asset_path: videoAssetPath,
      ...(imageAssetPath ? { image_asset_path: imageAssetPath } : {}),
    };
  }
  if (imageAssetPath) {
    return {
      kind: "static_image",
      asset_path: imageAssetPath,
      image_asset_path: imageAssetPath,
    };
  }
  return undefined;
}

function recordValue(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : undefined;
}

function resolveOptionalAppearancePath(
  root: string,
  value: unknown,
  field: string,
): string | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value !== "string") {
    throw new Error(`[pack.invalid_profile] ${field} must be a string when provided`);
  }
  if (!value.trim()) {
    return undefined;
  }
  return resolvePackPath(root, value, field);
}

function resolveSkills(
  root: string,
  skills: Array<{ id: string; path?: string }>,
): Array<{ id: string; path?: string }> {
  return skills.map((skill) => ({
    id: requireString(skill.id, "skills[].id"),
    ...(skill.path ? { path: resolvePackPath(root, skill.path, "skills[].path") } : {}),
  }));
}

async function normalizedPackRoot(root: string): Promise<string> {
  if (await exists(join(root, "agent.json"))) {
    return root;
  }
  const childDirs = await childDirectories(root);
  if (childDirs.length === 1 && (await exists(join(childDirs[0], "agent.json")))) {
    return childDirs[0];
  }
  throw new Error(`expected \`${root}\` to be an agent definition root or contain a single wrapped agent definition directory`);
}

async function childDirectories(root: string): Promise<string[]> {
  const children = (await readdir(root))
    .filter((entry) => !entry.startsWith(".") && entry !== "__MACOSX")
    .map((entry) => join(root, entry));
  const dirs: string[] = [];
  for (const child of children) {
    if (await isDirectory(child)) {
      dirs.push(child);
    }
  }
  return dirs.sort();
}

function resolvePackPath(root: string, relativePath: string, field: string): string {
  const resolvedRoot = resolve(root);
  const resolved = isAbsolute(relativePath) ? relativePath : resolve(resolvedRoot, relativePath);
  const relative = resolved.slice(resolvedRoot.length);
  if (!resolved.startsWith(resolvedRoot) || relative.split("/").includes("..")) {
    throw new Error(`[pack.path_escapes_root] ${field} points outside the agent definition root: ${resolved}`);
  }
  return resolved;
}

function validateProfile(profile: AgentProfile): AgentProfile {
  for (const field of ["id", "name", "tagline", "personality_prompt", "source", "version"] as const) {
    requireString(profile[field], field);
  }
  return profile;
}

function requireString(value: unknown, field: string): string {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`${field} cannot be empty`);
  }
  return value;
}

async function exists(path: string): Promise<boolean> {
  try {
    await stat(path);
    return true;
  } catch {
    return false;
  }
}

async function isDirectory(path: string): Promise<boolean> {
  try {
    return (await stat(path)).isDirectory();
  } catch {
    return false;
  }
}
