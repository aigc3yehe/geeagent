import { existsSync } from "node:fs";
import {
  mkdir,
  readdir,
  readFile,
  stat,
  writeFile,
} from "node:fs/promises";
import { dirname, isAbsolute, join, resolve } from "node:path";

import { agentsDir, personaAssetsRoot } from "../paths.js";
import { defaultAgentProfile } from "./defaults.js";
import type { AgentProfile, RuntimeStore } from "./types.js";

export async function loadAgentProfiles(configDir: string): Promise<AgentProfile[]> {
  const profiles = [withFileState(await defaultAgentProfileWithLocalAppearance(configDir), configDir)];
  const dir = agentsDir(configDir);
  if (!(await isDirectory(dir))) {
    return profiles;
  }

  const entries = (await readdir(dir))
    .filter((entry) => entry.endsWith(".json"))
    .sort();
  for (const entry of entries) {
    const profile = await readRuntimeProfile(join(dir, entry));
    if (!profiles.some((existing) => existing.id === profile.id)) {
      profiles.push(withFileState(profile, configDir));
    }
  }
  return profiles;
}

async function defaultAgentProfileWithLocalAppearance(
  configDir: string,
): Promise<AgentProfile> {
  const profile = defaultAgentProfile();
  const bundlePath = await findFirstLocalGeeLive2DModel(configDir, profile.id);
  if (!bundlePath) {
    return profile;
  }
  return {
    ...profile,
    appearance: {
      kind: "live2d",
      bundle_path: bundlePath,
    },
  };
}

async function findFirstLocalGeeLive2DModel(
  configDir: string,
  profileId: string,
): Promise<string | undefined> {
  const roots = [
    join(personaAssetsRoot(configDir), profileId, "live2d"),
    join(personaAssetsRoot(), profileId, "live2d"),
    join(personaAssetsRoot(configDir), profileId, "appearance"),
    join(personaAssetsRoot(), profileId, "appearance"),
  ];

  for (const root of roots) {
    const found = await findModel3Json(root);
    if (found) {
      return found;
    }
  }
  return undefined;
}

export async function writeInstalledProfile(
  configDir: string,
  profile: AgentProfile,
  overwrite: boolean,
): Promise<void> {
  const dir = agentsDir(configDir);
  const path = join(dir, `${profile.id}.json`);
  if (!overwrite && (await exists(path))) {
    throw new Error(`agent profile \`${profile.id}\` is already installed at \`${path}\``);
  }
  await mkdir(dir, { recursive: true });
  await writeFile(path, `${JSON.stringify(profile, null, 2)}\n`, "utf8");
}

export function requireMutableProfile(
  store: RuntimeStore,
  profileId: string,
  action: string,
): AgentProfile {
  const trimmed = profileId.trim();
  const profile = store.agent_profiles.find((item) => item.id === trimmed);
  if (!profile) {
    throw new Error(`unknown agent profile \`${trimmed}\``);
  }
  if (profile.source === "first_party") {
    throw new Error(`agent profile \`${trimmed}\` is bundled and cannot be ${action}`);
  }
  return profile;
}

export function workspaceRootForProfile(configDir: string, profileId: string): string {
  const candidates = [
    join(personaAssetsRoot(configDir), profileId),
    join(personaAssetsRoot(), profileId),
  ];
  return candidates.find((candidate) => existsSync(candidate)) ?? candidates[0];
}

async function readRuntimeProfile(path: string): Promise<AgentProfile> {
  const parsed = JSON.parse(await readFile(path, "utf8")) as AgentProfile;
  return normalizeProfilePaths(validateProfile(parsed), dirname(path));
}

function withFileState(profile: AgentProfile, configDir: string): AgentProfile {
  if (profile.source === "first_party") {
    return {
      ...profile,
      file_state: {
        visual_files: [],
        supplemental_files: [],
        can_reload: false,
        can_delete: false,
      },
    };
  }

  const workspaceRoot = workspaceRootForProfile(configDir, profile.id);
  const pathIfExists = (path: string): string | undefined =>
    existsSync(path) ? path : undefined;
  return {
    ...profile,
    file_state: {
      workspace_root_path: pathIfExists(workspaceRoot),
      manifest_path: pathIfExists(join(workspaceRoot, "agent.json")),
      identity_prompt_path: pathIfExists(join(workspaceRoot, "identity-prompt.md")),
      soul_path: pathIfExists(join(workspaceRoot, "soul.md")),
      playbook_path: pathIfExists(join(workspaceRoot, "playbook.md")),
      tools_context_path: pathIfExists(join(workspaceRoot, "tools.md")),
      memory_seed_path: pathIfExists(join(workspaceRoot, "memory.md")),
      heartbeat_path: pathIfExists(join(workspaceRoot, "heartbeat.md")),
      visual_files: [],
      supplemental_files: [],
      can_reload: true,
      can_delete: true,
    },
  };
}

function validateProfile(profile: AgentProfile): AgentProfile {
  for (const field of ["id", "name", "tagline", "personality_prompt", "source", "version"] as const) {
    requireString(profile[field], field);
  }
  return profile;
}

function normalizeProfilePaths(profile: AgentProfile, baseDir: string): AgentProfile {
  const appearance = { ...profile.appearance };
  for (const field of ["asset_path", "bundle_path", "live2d_bundle_path", "video_asset_path", "image_asset_path"]) {
    if (typeof appearance[field] === "string" && !isAbsolute(appearance[field])) {
      appearance[field] = resolve(baseDir, appearance[field]);
    }
  }
  if (isRecord(appearance.global_background)) {
    const globalBackground = { ...appearance.global_background };
    for (const field of ["asset_path", "video_asset_path", "image_asset_path"]) {
      if (typeof globalBackground[field] === "string" && !isAbsolute(globalBackground[field])) {
        globalBackground[field] = resolve(baseDir, globalBackground[field]);
      }
    }
    appearance.global_background = globalBackground;
  }
  const skills = profile.skills?.map((skill) => ({
    ...skill,
    ...(skill.path && !isAbsolute(skill.path)
      ? { path: resolve(baseDir, skill.path) }
      : {}),
  }));
  return { ...profile, appearance, ...(skills ? { skills } : {}) };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
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

async function findModel3Json(root: string): Promise<string | undefined> {
  let entries;
  try {
    entries = await readdir(root, { withFileTypes: true });
  } catch {
    return undefined;
  }

  const sorted = entries.sort((left, right) => left.name.localeCompare(right.name));
  for (const entry of sorted) {
    const path = join(root, entry.name);
    if (entry.isFile() && entry.name.endsWith(".model3.json")) {
      return path;
    }
    if (entry.isDirectory()) {
      const nested = await findModel3Json(path);
      if (nested) {
        return nested;
      }
    }
  }
  return undefined;
}
