import { homedir } from "node:os";
import { join, resolve } from "node:path";

export const RUNTIME_STORE_FILE = "runtime-store.json";
export const RUNTIME_SECURITY_FILE = "runtime-security.json";
export const TERMINAL_ACCESS_FILE = "terminal-access.json";
export const SKILL_SOURCES_FILE = "runtime-skill-sources.json";

export function resolveConfigDir(configDir?: string): string {
  if (configDir?.trim()) {
    return resolve(configDir);
  }

  const envConfigDir = process.env.GEEAGENT_CONFIG_DIR?.trim();
  if (envConfigDir) {
    return resolve(envConfigDir);
  }

  return join(homedir(), "Library", "Application Support", "GeeAgent");
}

export function runtimeProjectPath(fallback?: string): string {
  const envProjectPath = process.env.GEEAGENT_RUNTIME_PROJECT_PATH?.trim();
  if (envProjectPath) {
    return resolve(envProjectPath);
  }
  if (fallback?.trim()) {
    return resolve(fallback);
  }
  return homedir();
}

export function runtimeStorePath(configDir: string): string {
  return join(configDir, RUNTIME_STORE_FILE);
}

export function runtimeSecurityPath(configDir: string): string {
  return join(configDir, RUNTIME_SECURITY_FILE);
}

export function terminalAccessPath(configDir: string): string {
  return join(configDir, TERMINAL_ACCESS_FILE);
}

export function runtimeSkillSourcesPath(configDir: string): string {
  return join(configDir, SKILL_SOURCES_FILE);
}

export function agentsDir(configDir: string): string {
  return join(configDir, "agents");
}

export function personaAssetsRoot(configDir?: string): string {
  const envRoot = process.env.GEEAGENT_PERSONAS_ROOT?.trim();
  if (envRoot) {
    return resolve(envRoot);
  }
  if (configDir) {
    return join(configDir, "Personas");
  }
  return join(homedir(), "Library", "Application Support", "GeeAgent", "Personas");
}
