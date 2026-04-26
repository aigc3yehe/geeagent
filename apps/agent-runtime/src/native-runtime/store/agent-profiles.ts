import { cp, mkdir, rm, stat } from "node:fs/promises";
import { dirname, join } from "node:path";

import { agentsDir, personaAssetsRoot } from "../paths.js";
import {
  loadAgentProfiles,
  requireMutableProfile,
  workspaceRootForProfile,
  writeInstalledProfile,
} from "./agent-profile-files.js";
import {
  loadRuntimeProfileFromPack,
  preparePackRoot,
} from "./agent-pack.js";
import type { AgentProfile, RuntimeStore } from "./types.js";

export async function refreshAgentProfiles(
  store: RuntimeStore,
  configDir: string,
): Promise<void> {
  const profiles = await loadAgentProfiles(configDir);
  const activeProfileExists = profiles.some(
    (profile) => profile.id === store.active_agent_profile_id,
  );
  store.agent_profiles = profiles;
  store.active_agent_profile_id = activeProfileExists
    ? store.active_agent_profile_id
    : profiles[0]?.id ?? "gee";
}

export async function setActiveAgentProfile(
  store: RuntimeStore,
  configDir: string,
  profileId: string,
): Promise<void> {
  await refreshAgentProfiles(store, configDir);
  const trimmed = profileId.trim();
  if (!store.agent_profiles.some((profile) => profile.id === trimmed)) {
    throw new Error(`unknown agent profile \`${trimmed}\``);
  }
  store.active_agent_profile_id = trimmed;
}

export async function installAgentPack(
  store: RuntimeStore,
  configDir: string,
  packPath: string,
): Promise<void> {
  const preparedRoot = await preparePackRoot(packPath);
  const profile = await loadRuntimeProfileFromPack(preparedRoot);
  const destination = join(personaAssetsRoot(configDir), profile.id);
  await mkdir(dirname(destination), { recursive: true });
  if (await exists(destination)) {
    throw new Error(`agent profile workspace \`${profile.id}\` already exists at \`${destination}\``);
  }
  await cp(preparedRoot, destination, { recursive: true });
  const installed = await loadRuntimeProfileFromPack(destination);
  await writeInstalledProfile(configDir, installed, false);
  await refreshAgentProfiles(store, configDir);
}

export async function reloadAgentProfile(
  store: RuntimeStore,
  configDir: string,
  profileId: string,
): Promise<void> {
  await refreshAgentProfiles(store, configDir);
  const existing = requireMutableProfile(store, profileId, "reloaded");
  const workspaceRoot = workspaceRootForProfile(configDir, existing.id);
  if (!(await isDirectory(workspaceRoot))) {
    throw new Error(
      `agent profile \`${existing.id}\` has no local workspace at \`${workspaceRoot}\``,
    );
  }
  const reloaded = await loadRuntimeProfileFromPack(workspaceRoot, existing.source);
  if (reloaded.id !== existing.id) {
    throw new Error(
      `agent profile workspace \`${workspaceRoot}\` now declares id \`${reloaded.id}\`; rename the folder or restore the original id before reloading`,
    );
  }
  await writeInstalledProfile(configDir, reloaded, true);
  await refreshAgentProfiles(store, configDir);
}

export async function deleteAgentProfile(
  store: RuntimeStore,
  configDir: string,
  profileId: string,
): Promise<void> {
  await refreshAgentProfiles(store, configDir);
  const existing = requireMutableProfile(store, profileId, "deleted");
  await rm(join(agentsDir(configDir), `${existing.id}.json`), {
    force: true,
  });
  await rm(workspaceRootForProfile(configDir, existing.id), {
    force: true,
    recursive: true,
  });
  if (store.active_agent_profile_id === existing.id) {
    store.active_agent_profile_id = "gee";
  }
  await refreshAgentProfiles(store, configDir);
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
