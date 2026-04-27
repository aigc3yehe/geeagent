import { createHash } from "node:crypto";
import {
  mkdir,
  readdir,
  readFile,
  stat,
  writeFile,
} from "node:fs/promises";
import { basename, dirname, join, resolve } from "node:path";

import { runtimeSkillSourcesPath } from "../paths.js";
import { currentTimestamp } from "./defaults.js";
import type {
  AgentProfile,
  AgentSkillReference,
  RuntimeSkillSourceRecord,
  RuntimeSkillSourcesSnapshot,
} from "./types.js";

type RuntimeSkillSourceRegistry = {
  version: 1;
  system_sources: PersistedSkillSource[];
  persona_sources: Record<string, PersistedSkillSource[]>;
};

type PersistedSkillSource = {
  id: string;
  path: string;
  enabled: boolean;
  added_at: string;
  last_scanned_at?: string;
  status?: "ready" | "unavailable" | "invalid";
  error?: string;
  skills?: AgentSkillReference[];
};

type SkillSourceScan = {
  status: "ready" | "unavailable" | "invalid";
  error?: string;
  skills: AgentSkillReference[];
  scannedAt: string;
};

type SkillMetadata = {
  id: string;
  name?: string;
  description?: string;
  path: string;
  skill_file_path: string;
};

const MAX_SKILL_MD_BYTES = 512 * 1024;

export async function addSystemSkillSource(
  configDir: string,
  rawPath: string,
): Promise<void> {
  const registry = await loadSkillSourceRegistry(configDir);
  const source = await createOrUpdateSource("system", undefined, rawPath, registry.system_sources);
  const scan = await scanSkillSource(source.path, "system", source.id);
  Object.assign(source, sourceFieldsFromScan(scan));
  await persistSkillSourceRegistry(configDir, registry);
}

export async function addPersonaSkillSource(
  configDir: string,
  profileId: string,
  rawPath: string,
): Promise<void> {
  const trimmedProfileId = profileId.trim();
  if (!trimmedProfileId) {
    throw new Error("profile id is required");
  }
  const registry = await loadSkillSourceRegistry(configDir);
  const sources = registry.persona_sources[trimmedProfileId] ?? [];
  registry.persona_sources[trimmedProfileId] = sources;
  const source = await createOrUpdateSource("persona", trimmedProfileId, rawPath, sources);
  const scan = await scanSkillSource(source.path, "persona", source.id, trimmedProfileId);
  Object.assign(source, sourceFieldsFromScan(scan));
  await persistSkillSourceRegistry(configDir, registry);
}

export async function removeSystemSkillSource(
  configDir: string,
  sourceId: string,
): Promise<void> {
  const registry = await loadSkillSourceRegistry(configDir);
  registry.system_sources = registry.system_sources.filter(
    (source) => source.id !== sourceId.trim(),
  );
  await persistSkillSourceRegistry(configDir, registry);
}

export async function removePersonaSkillSource(
  configDir: string,
  profileId: string,
  sourceId: string,
): Promise<void> {
  const trimmedProfileId = profileId.trim();
  const trimmedSourceId = sourceId.trim();
  if (!trimmedProfileId) {
    throw new Error("profile id is required");
  }
  if (!trimmedSourceId) {
    throw new Error("skill source id is required");
  }
  const registry = await loadSkillSourceRegistry(configDir);
  const sources = registry.persona_sources[trimmedProfileId];
  if (!sources) {
    return;
  }
  const nextSources = sources.filter((source) => source.id !== trimmedSourceId);
  if (nextSources.length === sources.length) {
    return;
  }
  if (nextSources.length === 0) {
    delete registry.persona_sources[trimmedProfileId];
  } else {
    registry.persona_sources[trimmedProfileId] = nextSources;
  }
  await persistSkillSourceRegistry(configDir, registry);
}

export async function removePersonaSkillSourcesForProfile(
  configDir: string,
  profileId: string,
): Promise<void> {
  const trimmedProfileId = profileId.trim();
  if (!trimmedProfileId) {
    return;
  }
  const registry = await loadSkillSourceRegistry(configDir);
  if (!(trimmedProfileId in registry.persona_sources)) {
    return;
  }
  delete registry.persona_sources[trimmedProfileId];
  await persistSkillSourceRegistry(configDir, registry);
}

export async function refreshPersonaSkillSources(
  configDir: string,
  profileId: string,
): Promise<void> {
  const trimmedProfileId = profileId.trim();
  const registry = await loadSkillSourceRegistry(configDir);
  const sources = registry.persona_sources[trimmedProfileId] ?? [];
  let changed = false;
  for (const source of sources) {
    if (!source.enabled) {
      continue;
    }
    const scan = await scanSkillSource(source.path, "persona", source.id, trimmedProfileId);
    Object.assign(source, sourceFieldsFromScan(scan));
    changed = true;
  }
  if (changed) {
    await persistSkillSourceRegistry(configDir, registry);
  }
}

export async function skillSourcesSnapshot(
  configDir: string,
  profileIds: string[],
): Promise<RuntimeSkillSourcesSnapshot> {
  const registry = await loadSkillSourceRegistry(configDir);
  const systemSources = await Promise.all(
    registry.system_sources.map((source) => projectSystemSource(source)),
  );
  const personaSources: Record<string, RuntimeSkillSourceRecord[]> = {};
  for (const profileId of profileIds) {
    personaSources[profileId] = (registry.persona_sources[profileId] ?? []).map(
      (source) => projectCachedPersonaSource(source, profileId),
    );
  }
  return {
    system_sources: systemSources,
    persona_sources: personaSources,
  };
}

export async function profilesWithEffectiveSkills(
  configDir: string,
  profiles: AgentProfile[],
  snapshot?: RuntimeSkillSourcesSnapshot,
): Promise<AgentProfile[]> {
  const sourceSnapshot =
    snapshot ?? (await skillSourcesSnapshot(configDir, profiles.map((profile) => profile.id)));
  return Promise.all(
    profiles.map(async (profile) => ({
      ...profile,
      skills: await effectiveSkillsForProfile(configDir, profile, sourceSnapshot),
    })),
  );
}

export async function effectiveSkillsForProfile(
  configDir: string,
  profile: AgentProfile,
  snapshot?: RuntimeSkillSourcesSnapshot,
): Promise<AgentSkillReference[]> {
  const sourceSnapshot =
    snapshot ?? (await skillSourcesSnapshot(configDir, [profile.id]));
  const systemSkills = sourceSnapshot.system_sources.flatMap((source) =>
    source.enabled && source.status === "ready" ? source.skills : [],
  );
  const profileSkills = await Promise.all(
    (profile.skills ?? []).map((skill) => profileSkillReference(skill)),
  );
  const personaSkills = (sourceSnapshot.persona_sources[profile.id] ?? []).flatMap(
    (source) => (source.enabled && source.status === "ready" ? source.skills : []),
  );
  return dedupeSkills([...systemSkills, ...profileSkills, ...personaSkills]);
}

export async function skillPromptMetadataForProfile(
  configDir: string,
  profile: AgentProfile,
): Promise<string> {
  const skills = await effectiveSkillsForProfile(configDir, profile);
  const externalSkills = skills.filter((skill) => skill.path || skill.description);
  if (externalSkills.length === 0) {
    return "";
  }
  const lines = [
    "[AVAILABLE GEE SKILLS]",
    "Only the following explicitly configured skill metadata is available. GeeAgent does not inject SKILL.md bodies into this prompt. When a request matches a skill, use the metadata to decide whether to inspect that skill's SKILL.md through the normal file/tool path.",
    "",
  ];
  for (const skill of externalSkills) {
    lines.push(`- ${skill.id}`);
    if (skill.description) {
      lines.push(`  description: ${skill.description}`);
    }
    if (skill.source_scope) {
      lines.push(`  scope: ${skill.source_scope}`);
    }
    if (skill.path) {
      lines.push(`  path: ${skill.path}`);
    }
    if (skill.skill_file_path) {
      lines.push(`  skill_file_path: ${skill.skill_file_path}`);
    }
  }
  return lines.join("\n");
}

async function createOrUpdateSource(
  scope: "system" | "persona",
  profileId: string | undefined,
  rawPath: string,
  sources: PersistedSkillSource[],
): Promise<PersistedSkillSource> {
  const path = await normalizeSourcePath(rawPath);
  const id = skillSourceId(scope, profileId, path);
  const existing = sources.find((source) => source.id === id || source.path === path);
  if (existing) {
    existing.enabled = true;
    existing.path = path;
    return existing;
  }
  const source: PersistedSkillSource = {
    id,
    path,
    enabled: true,
    added_at: currentTimestamp(),
    skills: [],
  };
  sources.push(source);
  return source;
}

async function normalizeSourcePath(rawPath: string): Promise<string> {
  const trimmed = rawPath.trim();
  if (!trimmed) {
    throw new Error("skill source path is required");
  }
  const path = resolve(trimmed);
  let info;
  try {
    info = await stat(path);
  } catch {
    throw new Error(`skill source folder does not exist: ${path}`);
  }
  if (!info.isDirectory()) {
    throw new Error(`skill source must be a folder: ${path}`);
  }
  return path;
}

async function loadSkillSourceRegistry(
  configDir: string,
): Promise<RuntimeSkillSourceRegistry> {
  try {
    const parsed = JSON.parse(
      await readFile(runtimeSkillSourcesPath(configDir), "utf8"),
    ) as Partial<RuntimeSkillSourceRegistry>;
    return {
      version: 1,
      system_sources: Array.isArray(parsed.system_sources)
        ? parsed.system_sources.map(normalizePersistedSource)
        : [],
      persona_sources: normalizePersonaSources(parsed.persona_sources),
    };
  } catch (error) {
    if (isMissingFileError(error)) {
      return defaultRegistry();
    }
    throw new Error(
      `failed to load skill sources at ${runtimeSkillSourcesPath(configDir)}: ${errorMessage(error)}`,
    );
  }
}

async function persistSkillSourceRegistry(
  configDir: string,
  registry: RuntimeSkillSourceRegistry,
): Promise<void> {
  const path = runtimeSkillSourcesPath(configDir);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify(registry, null, 2)}\n`, "utf8");
}

function defaultRegistry(): RuntimeSkillSourceRegistry {
  return {
    version: 1,
    system_sources: [],
    persona_sources: {},
  };
}

function normalizePersonaSources(
  value: unknown,
): Record<string, PersistedSkillSource[]> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return {};
  }
  const out: Record<string, PersistedSkillSource[]> = {};
  for (const [profileId, sources] of Object.entries(value)) {
    out[profileId] = Array.isArray(sources)
      ? sources.map(normalizePersistedSource)
      : [];
  }
  return out;
}

function normalizePersistedSource(value: unknown): PersistedSkillSource {
  const record = isRecord(value) ? value : {};
  const id = stringField(record, "id") ?? skillSourceId("system", undefined, stringField(record, "path") ?? "");
  const path = stringField(record, "path") ?? "";
  return {
    id,
    path,
    enabled: record.enabled !== false,
    added_at: stringField(record, "added_at") ?? currentTimestamp(),
    last_scanned_at: stringField(record, "last_scanned_at") ?? undefined,
    status: sourceStatus(record.status),
    error: stringField(record, "error") ?? undefined,
    skills: Array.isArray(record.skills)
      ? record.skills.map(normalizeSkillReference).filter((skill) => skill.id)
      : [],
  };
}

async function projectSystemSource(
  source: PersistedSkillSource,
): Promise<RuntimeSkillSourceRecord> {
  if (!source.enabled) {
    return projectSource(source, "system", undefined, {
      status: sourceStatus(source.status),
      error: source.error,
      skills: source.skills ?? [],
      scannedAt: source.last_scanned_at ?? currentTimestamp(),
    });
  }
  const scan = await scanSkillSource(source.path, "system", source.id);
  return projectSource(source, "system", undefined, scan);
}

function projectCachedPersonaSource(
  source: PersistedSkillSource,
  profileId: string,
): RuntimeSkillSourceRecord {
  return projectSource(source, "persona", profileId, {
    status: sourceStatus(source.status),
    error: source.error,
    skills: (source.skills ?? []).map((skill) => ({
      ...skill,
      source_scope: "persona",
      profile_id: profileId,
    })),
    scannedAt: source.last_scanned_at ?? source.added_at,
  });
}

function projectSource(
  source: PersistedSkillSource,
  scope: "system" | "persona",
  profileId: string | undefined,
  scan: SkillSourceScan,
): RuntimeSkillSourceRecord {
  return {
    id: source.id,
    path: source.path,
    scope,
    ...(profileId ? { profile_id: profileId } : {}),
    enabled: source.enabled,
    added_at: source.added_at,
    last_scanned_at: scan.scannedAt,
    status: scan.status,
    ...(scan.error ? { error: scan.error } : {}),
    skills: scan.skills,
  };
}

async function scanSkillSource(
  sourcePath: string,
  scope: "system" | "persona",
  sourceId: string,
  profileId?: string,
): Promise<SkillSourceScan> {
  const scannedAt = currentTimestamp();
  try {
    const rootInfo = await stat(sourcePath);
    if (!rootInfo.isDirectory()) {
      return {
        status: "invalid",
        error: "source path is not a directory",
        skills: [],
        scannedAt,
      };
    }

    const candidates = await skillCandidates(sourcePath);
    const skills: AgentSkillReference[] = [];
    for (const candidate of candidates) {
      const metadata = await readSkillMetadata(candidate);
      if (!metadata) {
        continue;
      }
      skills.push({
        id: metadata.id,
        name: metadata.name ?? metadata.id,
        ...(metadata.description ? { description: metadata.description } : {}),
        path: metadata.path,
        skill_file_path: metadata.skill_file_path,
        source_id: sourceId,
        source_scope: scope,
        source_path: sourcePath,
        ...(profileId ? { profile_id: profileId } : {}),
        status: "ready",
      });
    }
    return {
      status: "ready",
      skills: skills.sort((left, right) => left.id.localeCompare(right.id)),
      scannedAt,
    };
  } catch (error) {
    return {
      status: "unavailable",
      error: errorMessage(error),
      skills: [],
      scannedAt,
    };
  }
}

async function skillCandidates(sourcePath: string): Promise<string[]> {
  const directSkill = join(sourcePath, "SKILL.md");
  if (await isFile(directSkill)) {
    return [sourcePath];
  }
  const entries = await readdir(sourcePath, { withFileTypes: true });
  const candidates: string[] = [];
  for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name))) {
    if (!entry.isDirectory() || entry.name.startsWith(".")) {
      continue;
    }
    const child = join(sourcePath, entry.name);
    if (await isFile(join(child, "SKILL.md"))) {
      candidates.push(child);
    }
  }
  return candidates;
}

async function readSkillMetadata(skillPath: string): Promise<SkillMetadata | null> {
  const skillFilePath = join(skillPath, "SKILL.md");
  const info = await stat(skillFilePath);
  if (!info.isFile() || info.size > MAX_SKILL_MD_BYTES) {
    return null;
  }
  const raw = await readFile(skillFilePath, "utf8");
  const frontmatter = parseFrontmatter(raw);
  const id = normalizeSkillId(frontmatter.name) || normalizeSkillId(basename(skillPath));
  if (!id) {
    return null;
  }
  return {
    id,
    name: stringOrUndefined(frontmatter.name) ?? id,
    description: stringOrUndefined(frontmatter.description),
    path: skillPath,
    skill_file_path: skillFilePath,
  };
}

async function profileSkillReference(skill: AgentSkillReference): Promise<AgentSkillReference> {
  if (!skill.path) {
    return {
      ...skill,
      source_scope: skill.source_scope ?? "profile",
    };
  }
  try {
    const metadata = await readSkillMetadata(skill.path);
    if (!metadata) {
      return {
        ...skill,
        source_scope: skill.source_scope ?? "profile",
        status: "invalid",
      };
    }
    return {
      ...skill,
      id: metadata.id,
      name: metadata.name ?? skill.name ?? metadata.id,
      description: metadata.description ?? skill.description,
      path: metadata.path,
      skill_file_path: metadata.skill_file_path,
      source_scope: skill.source_scope ?? "profile",
      status: "ready",
    };
  } catch (error) {
    return {
      ...skill,
      source_scope: skill.source_scope ?? "profile",
      status: "unavailable",
      error: errorMessage(error),
    };
  }
}

function sourceFieldsFromScan(
  scan: SkillSourceScan,
): Pick<PersistedSkillSource, "last_scanned_at" | "status" | "error" | "skills"> {
  return {
    last_scanned_at: scan.scannedAt,
    status: scan.status,
    error: scan.error,
    skills: scan.skills,
  };
}

function dedupeSkills(skills: AgentSkillReference[]): AgentSkillReference[] {
  const byId = new Map<string, AgentSkillReference>();
  for (const skill of skills) {
    if (!skill.id.trim()) {
      continue;
    }
    byId.set(skill.id, skill);
  }
  return [...byId.values()].sort((left, right) => left.id.localeCompare(right.id));
}

function normalizeSkillReference(value: unknown): AgentSkillReference {
  const record = isRecord(value) ? value : {};
  const id = stringField(record, "id") ?? "";
  return {
    id,
    name: stringField(record, "name") ?? undefined,
    description: stringField(record, "description") ?? undefined,
    path: stringField(record, "path") ?? undefined,
    skill_file_path: stringField(record, "skill_file_path") ?? undefined,
    source_id: stringField(record, "source_id") ?? undefined,
    source_scope:
      record.source_scope === "system" ||
      record.source_scope === "persona" ||
      record.source_scope === "profile"
        ? record.source_scope
        : undefined,
    source_path: stringField(record, "source_path") ?? undefined,
    profile_id: stringField(record, "profile_id") ?? undefined,
    status: sourceStatus(record.status),
    error: stringField(record, "error") ?? undefined,
  };
}

function parseFrontmatter(raw: string): Record<string, string> {
  const trimmedStart = raw.trimStart();
  if (!trimmedStart.startsWith("---")) {
    return {};
  }
  const lines = trimmedStart.split(/\r?\n/);
  const out: Record<string, string> = {};
  for (let index = 1; index < lines.length; index += 1) {
    const line = lines[index];
    if (line.trim() === "---") {
      break;
    }
    const match = /^([A-Za-z0-9_-]+):\s*(.*)$/.exec(line);
    if (!match) {
      continue;
    }
    out[match[1].trim()] = unquote(match[2].trim());
  }
  return out;
}

function unquote(value: string): string {
  if (
    (value.startsWith("\"") && value.endsWith("\"")) ||
    (value.startsWith("'") && value.endsWith("'"))
  ) {
    return value.slice(1, -1);
  }
  return value;
}

function normalizeSkillId(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function stringOrUndefined(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

async function isFile(path: string): Promise<boolean> {
  try {
    return (await stat(path)).isFile();
  } catch {
    return false;
  }
}

function skillSourceId(
  scope: "system" | "persona",
  profileId: string | undefined,
  path: string,
): string {
  const hash = createHash("sha256")
    .update(scope)
    .update(profileId ?? "")
    .update(resolve(path))
    .digest("hex")
    .slice(0, 16);
  return `skill_src_${hash}`;
}

function sourceStatus(value: unknown): "ready" | "unavailable" | "invalid" {
  return value === "ready" || value === "unavailable" || value === "invalid"
    ? value
    : "ready";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringField(record: Record<string, unknown>, key: string): string | null {
  const value = record[key];
  return typeof value === "string" ? value : null;
}

function isMissingFileError(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    (error as { code?: unknown }).code === "ENOENT"
  );
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
