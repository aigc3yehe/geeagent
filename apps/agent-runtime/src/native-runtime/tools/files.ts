import { mkdir, readFile, readdir, stat, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, join, normalize, relative } from "node:path";

import { argError, errorMessage, getBoolArg, getNumberArg, getStringArg } from "./args.js";
import type { ToolOutcome, ToolRequest } from "./types.js";

const TEXT_DECODER = new TextDecoder("utf-8", { fatal: true });
const FILES_READ_MAX_DEFAULT_BYTES = 1024 * 1024;

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
