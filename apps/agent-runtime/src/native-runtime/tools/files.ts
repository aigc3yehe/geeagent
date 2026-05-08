import { createHash } from "node:crypto";
import { lstat, mkdir, readFile, readdir, realpath, stat, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, join, normalize, relative } from "node:path";

import { argError, errorMessage, getBoolArg, getNumberArg, getStringArg } from "./args.js";
import type { ToolOutcome, ToolRequest } from "./types.js";

const TEXT_DECODER = new TextDecoder("utf-8", { fatal: true });
const FILES_READ_MAX_DEFAULT_BYTES = 1024 * 1024;
const DIRECTORY_SNAPSHOT_DEFAULT_MAX_DEPTH = 3;
const DIRECTORY_SNAPSHOT_HARD_MAX_DEPTH = 8;
const DIRECTORY_SNAPSHOT_DEFAULT_MAX_ENTRIES = 500;
const DIRECTORY_SNAPSHOT_HARD_MAX_ENTRIES = 5_000;

export async function filesReadText(request: ToolRequest): Promise<ToolOutcome> {
  const path = getStringArg(request, "path");
  if (path === undefined) {
    return argError(request.tool_id, "path", "required string `path` is missing");
  }
  const resolved = resolveScopedPath(path, request.files_root);
  if (typeof resolved !== "string") {
    return resolved;
  }
  const maxBytes = getNumberArg(request, "max_bytes") ?? FILES_READ_MAX_DEFAULT_BYTES;
  try {
    const bytes = await readFile(resolved);
    const truncated = bytes.byteLength > maxBytes;
    const slice = truncated ? bytes.subarray(0, maxBytes) : bytes;
    try {
      const contents = TEXT_DECODER.decode(slice);
      return {
        kind: "completed",
        tool_id: request.tool_id,
        payload: {
          path: resolved,
          contents,
          truncated,
          bytes_read: slice.byteLength,
        },
      };
    } catch (error) {
      return {
        kind: "error",
        tool_id: request.tool_id,
        code: "files.not_utf8",
        message: `file is not valid UTF-8: ${errorMessage(error)}`,
      };
    }
  } catch (error) {
    return {
      kind: "error",
      tool_id: request.tool_id,
      code: "files.read_failed",
      message: errorMessage(error),
    };
  }
}

export async function filesWriteText(request: ToolRequest): Promise<ToolOutcome> {
  const path = getStringArg(request, "path");
  if (path === undefined) {
    return argError(request.tool_id, "path", "required string `path` is missing");
  }
  const contents = getStringArg(request, "contents");
  if (contents === undefined) {
    return argError(
      request.tool_id,
      "contents",
      "required string `contents` is missing",
    );
  }
  const resolved = resolveScopedPath(path, request.files_root);
  if (typeof resolved !== "string") {
    return resolved;
  }
  try {
    if (getBoolArg(request, "create_parents") === true) {
      try {
        await mkdir(dirname(resolved), { recursive: true });
      } catch (error) {
        return {
          kind: "error",
          tool_id: request.tool_id,
          code: "files.create_parents_failed",
          message: errorMessage(error),
        };
      }
    }
    await writeFile(resolved, contents, "utf8");
    return {
      kind: "completed",
      tool_id: request.tool_id,
      payload: {
        path: resolved,
        bytes_written: Buffer.byteLength(contents),
      },
    };
  } catch (error) {
    return {
      kind: "error",
      tool_id: request.tool_id,
      code: "files.write_failed",
      message: errorMessage(error),
    };
  }
}

export async function filesEditText(request: ToolRequest): Promise<ToolOutcome> {
  const path = getStringArg(request, "path");
  if (path === undefined) {
    return argError(request.tool_id, "path", "required string `path` is missing");
  }
  const oldText = getStringArg(request, "old_text");
  if (oldText === undefined) {
    return argError(request.tool_id, "old_text", "required string `old_text` is missing");
  }
  const newText = getStringArg(request, "new_text");
  if (newText === undefined) {
    return argError(request.tool_id, "new_text", "required string `new_text` is missing");
  }
  if (oldText.length === 0) {
    return argError(request.tool_id, "old_text", "must not be empty");
  }
  const resolved = resolveScopedPath(path, request.files_root);
  if (typeof resolved !== "string") {
    return resolved;
  }

  let contents: string;
  try {
    contents = await readFileStrictUtf8(resolved);
  } catch (error) {
    return {
      kind: "error",
      tool_id: request.tool_id,
      code: "files.read_failed",
      message: errorMessage(error),
    };
  }

  if (!contents.includes(oldText)) {
    return {
      kind: "error",
      tool_id: request.tool_id,
      code: "files.edit_no_match",
      message: "old_text was not found in the target file",
    };
  }
  const replaceAll = getBoolArg(request, "replace_all") ?? false;
  const matchesSeen = countMatches(contents, oldText);
  const updated = replaceAll
    ? contents.split(oldText).join(newText)
    : contents.replace(oldText, newText);
  try {
    await writeFile(resolved, updated, "utf8");
    return {
      kind: "completed",
      tool_id: request.tool_id,
      payload: {
        path: resolved,
        replace_all: replaceAll,
        matches_seen: matchesSeen,
        replacements_applied: replaceAll ? matchesSeen : 1,
        bytes_written: Buffer.byteLength(updated),
      },
    };
  } catch (error) {
    return {
      kind: "error",
      tool_id: request.tool_id,
      code: "files.write_failed",
      message: errorMessage(error),
    };
  }
}

function resolveScopedPath(input: string, root: string | undefined): string | ToolOutcome {
  if (input.length === 0) {
    return {
      kind: "error",
      tool_id: "",
      code: "files.path_empty",
      message: "path is empty",
    };
  }

  if (root === undefined) {
    return input;
  }

  const absolute = isAbsolute(input) ? input : join(root, input);
  const normalised = normalize(absolute);
  const normalisedRoot = normalize(root);
  const relativeToRoot = relative(normalisedRoot, normalised);
  if (
    relativeToRoot === ".." ||
    relativeToRoot.startsWith(`..${"/"}`) ||
    isAbsolute(relativeToRoot)
  ) {
    return {
      kind: "error",
      tool_id: "",
      code: "files.path_escapes_root",
      message: `resolved path \`${normalised}\` escapes scoped root \`${root}\``,
    };
  }
  return normalised;
}

export async function coreLs(request: ToolRequest): Promise<ToolOutcome> {
  const path = getStringArg(request, "path") ?? ".";
  const includeHidden = getBoolArg(request, "include_hidden") ?? false;
  const maxEntries = getNumberArg(request, "max_entries") ?? 200;
  const resolved = resolveScopedPath(path, request.files_root);
  if (typeof resolved !== "string") {
    return resolved;
  }

  try {
    const entries = await readdir(resolved, { withFileTypes: true });
    const rows: Record<string, unknown>[] = [];
    for (const entry of entries) {
      if (!includeHidden && entry.name.startsWith(".")) {
        continue;
      }
      const entryPath = join(resolved, entry.name);
      const metadata = await stat(entryPath).catch(() => null);
      rows.push({
        name: entry.name,
        path: entryPath,
        kind:
          metadata === null
            ? "unknown"
            : metadata.isDirectory()
              ? "directory"
              : metadata.isFile()
                ? "file"
                : "other",
        size_bytes: metadata?.isFile() === true ? metadata.size : null,
      });
      if (rows.length >= maxEntries) {
        break;
      }
    }
    return {
      kind: "completed",
      tool_id: request.tool_id,
      payload: {
        path: resolved,
        entries: rows,
        truncated: rows.length >= maxEntries,
      },
    };
  } catch (error) {
    return {
      kind: "error",
      tool_id: request.tool_id,
      code: "files.list_failed",
      message: errorMessage(error),
    };
  }
}

type DirectorySnapshotEntry = {
  relative_path: string;
  kind: "directory" | "file" | "symlink" | "other" | "unknown";
  size_bytes?: number | null;
  child_count?: number | null;
  target_kind?: string;
};

type DirectorySnapshotError = {
  path: string;
  code: string;
  message: string;
};

type DirectorySnapshotAccumulator = {
  entries: DirectorySnapshotEntry[];
  errors: DirectorySnapshotError[];
  omittedCount: number;
  maxDepthReached: boolean;
  entryLimitReached: boolean;
};

export async function filesDirectorySnapshot(request: ToolRequest): Promise<ToolOutcome> {
  const path = getStringArg(request, "path");
  if (path === undefined) {
    return argError(request.tool_id, "path", "required string `path` is missing");
  }
  const resolved = resolveScopedPath(path, request.files_root);
  if (typeof resolved !== "string") {
    return resolved;
  }

  const maxDepth = boundedIntegerArg(
    getNumberArg(request, "max_depth"),
    DIRECTORY_SNAPSHOT_DEFAULT_MAX_DEPTH,
    DIRECTORY_SNAPSHOT_HARD_MAX_DEPTH,
  );
  const maxEntries = boundedIntegerArg(
    getNumberArg(request, "max_entries"),
    DIRECTORY_SNAPSHOT_DEFAULT_MAX_ENTRIES,
    DIRECTORY_SNAPSHOT_HARD_MAX_ENTRIES,
  );
  const includeHidden = getBoolArg(request, "include_hidden") ?? false;
  const includeSizes = getBoolArg(request, "include_sizes") ?? true;
  const followSymlinks = getBoolArg(request, "follow_symlinks") ?? false;
  const realRoot = await realpathWithinScopedRoot(resolved, request.files_root, request.tool_id);
  if (typeof realRoot !== "string") {
    return realRoot;
  }

  try {
    const metadata = await stat(resolved);
    if (!metadata.isDirectory()) {
      return {
        kind: "error",
        tool_id: request.tool_id,
        code: "files.not_directory",
        message: `path is not a directory: ${resolved}`,
      };
    }
  } catch (error) {
    return {
      kind: "error",
      tool_id: request.tool_id,
      code: "files.snapshot_root_failed",
      message: errorMessage(error),
    };
  }

  const accumulator: DirectorySnapshotAccumulator = {
    entries: [],
    errors: [],
    omittedCount: 0,
    maxDepthReached: false,
    entryLimitReached: false,
  };
  await collectDirectorySnapshotEntries({
    root: resolved,
    realRoot,
    currentPath: resolved,
    depth: 0,
    maxDepth,
    maxEntries,
    includeHidden,
    includeSizes,
    followSymlinks,
    accumulator,
  });

  const truncated =
    accumulator.entryLimitReached ||
    accumulator.maxDepthReached ||
    accumulator.omittedCount > 0;
  const payload = {
    root: resolved,
    entries: accumulator.entries,
    truncated,
    omitted_count: accumulator.omittedCount,
    max_depth_reached: accumulator.maxDepthReached,
    errors: accumulator.errors,
    snapshot_hash: snapshotHash({
      root: resolved,
      entries: accumulator.entries,
      truncated,
      omitted_count: accumulator.omittedCount,
      max_depth_reached: accumulator.maxDepthReached,
      errors: accumulator.errors,
    }),
    fallback_attempted: false,
  };
  return {
    kind: "completed",
    tool_id: request.tool_id,
    payload,
  };
}

async function collectDirectorySnapshotEntries(input: {
  root: string;
  realRoot: string;
  currentPath: string;
  depth: number;
  maxDepth: number;
  maxEntries: number;
  includeHidden: boolean;
  includeSizes: boolean;
  followSymlinks: boolean;
  accumulator: DirectorySnapshotAccumulator;
}): Promise<void> {
  if (input.accumulator.entryLimitReached) {
    return;
  }
  let children;
  try {
    children = await readdir(input.currentPath, { withFileTypes: true });
  } catch (error) {
    input.accumulator.errors.push({
      path: input.currentPath,
      code: "files.snapshot_read_failed",
      message: errorMessage(error),
    });
    return;
  }

  const visibleChildren = children
    .filter((entry) => {
      if (input.includeHidden || !entry.name.startsWith(".")) {
        return true;
      }
      input.accumulator.omittedCount += 1;
      return false;
    })
    .sort((left, right) => left.name.localeCompare(right.name, "en"));

  for (const child of visibleChildren) {
    if (input.accumulator.entries.length >= input.maxEntries) {
      input.accumulator.entryLimitReached = true;
      input.accumulator.omittedCount += 1;
      continue;
    }

    const childPath = join(input.currentPath, child.name);
    const entry = await directorySnapshotEntry({
      root: input.root,
      realRoot: input.realRoot,
      path: childPath,
      includeSizes: input.includeSizes,
      followSymlinks: input.followSymlinks,
    });
    input.accumulator.entries.push(entry);

    if (entry.kind !== "directory") {
      continue;
    }
    if (input.depth + 1 >= input.maxDepth) {
      input.accumulator.maxDepthReached = true;
      input.accumulator.omittedCount += await countDirectoryChildren(childPath, input.includeHidden);
      continue;
    }
    await collectDirectorySnapshotEntries({
      ...input,
      currentPath: childPath,
      depth: input.depth + 1,
    });
  }
}

async function directorySnapshotEntry(input: {
  root: string;
  realRoot: string;
  path: string;
  includeSizes: boolean;
  followSymlinks: boolean;
}): Promise<DirectorySnapshotEntry> {
  let metadata;
  try {
    metadata = await lstat(input.path);
  } catch {
    return {
      relative_path: relative(input.root, input.path),
      kind: "unknown",
    };
  }

  if (metadata.isSymbolicLink()) {
    if (!input.followSymlinks) {
      return {
        relative_path: relative(input.root, input.path),
        kind: "symlink",
      };
    }
    const target = await symlinkTargetKind(input.realRoot, input.path);
    return {
      relative_path: relative(input.root, input.path),
      kind: target === "directory" ? "directory" : "symlink",
      target_kind: target,
    };
  }

  if (metadata.isDirectory()) {
    return {
      relative_path: relative(input.root, input.path),
      kind: "directory",
      child_count: await countDirectoryChildren(input.path, true),
    };
  }

  if (metadata.isFile()) {
    return {
      relative_path: relative(input.root, input.path),
      kind: "file",
      ...(input.includeSizes ? { size_bytes: metadata.size } : {}),
    };
  }

  return {
    relative_path: relative(input.root, input.path),
    kind: "other",
  };
}

async function symlinkTargetKind(realRoot: string, path: string): Promise<string> {
  try {
    const resolvedTarget = await realpath(path);
    const relativeToRoot = relative(normalize(realRoot), normalize(resolvedTarget));
    if (
      relativeToRoot === ".." ||
      relativeToRoot.startsWith(`..${"/"}`) ||
      isAbsolute(relativeToRoot)
    ) {
      return "escaped";
    }
    const metadata = await stat(resolvedTarget);
    if (metadata.isDirectory()) {
      return "directory";
    }
    if (metadata.isFile()) {
      return "file";
    }
    return "other";
  } catch {
    return "unknown";
  }
}

async function realpathWithinScopedRoot(
  path: string,
  root: string | undefined,
  toolId: string,
): Promise<string | ToolOutcome> {
  let resolvedPath: string;
  try {
    resolvedPath = await realpath(path);
  } catch (error) {
    return {
      kind: "error",
      tool_id: toolId,
      code: "files.snapshot_root_failed",
      message: errorMessage(error),
    };
  }

  if (root === undefined) {
    return resolvedPath;
  }

  let resolvedRoot: string;
  try {
    resolvedRoot = await realpath(root);
  } catch (error) {
    return {
      kind: "error",
      tool_id: toolId,
      code: "files.snapshot_scope_failed",
      message: errorMessage(error),
    };
  }

  const relativeToRoot = relative(normalize(resolvedRoot), normalize(resolvedPath));
  if (
    relativeToRoot === ".." ||
    relativeToRoot.startsWith(`..${"/"}`) ||
    isAbsolute(relativeToRoot)
  ) {
    return {
      kind: "error",
      tool_id: toolId,
      code: "files.path_escapes_root",
      message: `resolved path \`${resolvedPath}\` escapes scoped root \`${resolvedRoot}\``,
    };
  }

  return resolvedPath;
}

async function countDirectoryChildren(path: string, includeHidden: boolean): Promise<number> {
  try {
    const entries = await readdir(path, { withFileTypes: true });
    return includeHidden ? entries.length : entries.filter((entry) => !entry.name.startsWith(".")).length;
  } catch {
    return 0;
  }
}

function boundedIntegerArg(value: number | undefined, defaultValue: number, hardMax: number): number {
  if (value === undefined || !Number.isFinite(value)) {
    return defaultValue;
  }
  return Math.max(0, Math.min(hardMax, Math.floor(value)));
}

function snapshotHash(payload: Record<string, unknown>): string {
  return createHash("sha256").update(JSON.stringify(payload)).digest("hex");
}

export async function coreFind(request: ToolRequest): Promise<ToolOutcome> {
  const path = getStringArg(request, "path") ?? ".";
  const nameContains = getStringArg(request, "name_contains") ?? "";
  const maxResults = getNumberArg(request, "max_results") ?? 200;
  const resolved = resolveScopedPath(path, request.files_root);
  if (typeof resolved !== "string") {
    return resolved;
  }
  const matches: Record<string, unknown>[] = [];
  await collectFindResults(resolved, nameContains, maxResults, matches);
  return {
    kind: "completed",
    tool_id: request.tool_id,
    payload: {
      path: resolved,
      name_contains: nameContains,
      matches,
      truncated: matches.length >= maxResults,
    },
  };
}

async function collectFindResults(
  root: string,
  nameContains: string,
  maxResults: number,
  results: Record<string, unknown>[],
): Promise<void> {
  if (results.length >= maxResults) {
    return;
  }
  let entries;
  try {
    entries = await readdir(root, { withFileTypes: true });
  } catch {
    return;
  }
  for (const entry of entries) {
    if (results.length >= maxResults) {
      return;
    }
    const entryPath = join(root, entry.name);
    if (nameContains.length === 0 || entry.name.includes(nameContains)) {
      results.push({
        name: entry.name,
        path: entryPath,
        kind: entry.isDirectory() ? "directory" : entry.isFile() ? "file" : "other",
      });
    }
    if (entry.isDirectory()) {
      await collectFindResults(entryPath, nameContains, maxResults, results);
    }
  }
}

export async function coreGrep(request: ToolRequest): Promise<ToolOutcome> {
  const pattern = getStringArg(request, "pattern");
  if (pattern === undefined) {
    return argError(request.tool_id, "pattern", "required string `pattern` is missing");
  }
  const path = getStringArg(request, "path") ?? ".";
  const maxMatches = getNumberArg(request, "max_matches") ?? 200;
  const resolved = resolveScopedPath(path, request.files_root);
  if (typeof resolved !== "string") {
    return resolved;
  }
  const matches: Record<string, unknown>[] = [];
  await collectGrepMatches(resolved, pattern, maxMatches, matches);
  return {
    kind: "completed",
    tool_id: request.tool_id,
    payload: {
      path: resolved,
      pattern,
      matches,
      truncated: matches.length >= maxMatches,
    },
  };
}

async function collectGrepMatches(
  root: string,
  pattern: string,
  maxMatches: number,
  matches: Record<string, unknown>[],
): Promise<void> {
  if (matches.length >= maxMatches) {
    return;
  }

  let entries;
  try {
    entries = await readdir(root, { withFileTypes: true });
  } catch {
    try {
      const contents = await readFileStrictUtf8(root);
      contents.split(/\r?\n/).forEach((line, index) => {
        if (matches.length < maxMatches && line.includes(pattern)) {
          matches.push({
            path: root,
            line_number: index + 1,
            line,
          });
        }
      });
    } catch {
      return;
    }
    return;
  }

  for (const entry of entries) {
    if (matches.length >= maxMatches) {
      return;
    }
    await collectGrepMatches(join(root, entry.name), pattern, maxMatches, matches);
  }
}

async function readFileStrictUtf8(path: string): Promise<string> {
  return TEXT_DECODER.decode(await readFile(path));
}

function countMatches(input: string, pattern: string): number {
  let count = 0;
  let index = 0;
  while (true) {
    index = input.indexOf(pattern, index);
    if (index === -1) {
      return count;
    }
    count += 1;
    index += pattern.length;
  }
}
