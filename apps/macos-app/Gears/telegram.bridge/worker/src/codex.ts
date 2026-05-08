import { spawn } from "node:child_process";
import { createReadStream } from "node:fs";
import {
  mkdir,
  mkdtemp,
  opendir,
  readFile,
  rm,
  stat,
} from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import {
  join,
  relative,
} from "node:path";
import { createInterface } from "node:readline";

const DEFAULT_CODEX_BIN = "/Applications/Codex.app/Contents/Resources/codex";
const FILE_SCAN_RECENT_DIRECTORY_LIMIT = 14;
const FILE_SCAN_MAX_FILES_PER_DIRECTORY = 60;
const FILE_SCAN_MAX_DIRECTORY_ENTRY_READS = 240;
const FILE_SCAN_MAX_CANDIDATE_COUNT = 300;
const FILE_SCAN_THREAD_READ_LINE_LIMIT = 400;

export type CodexThreadSource = "file_scan" | "app_server";
export type CodexSendMode = "cli_resume" | "app_server";

export type CodexThread = {
  id: string;
  title: string;
  cwd?: string;
  updatedAt?: string | null;
  filePath?: string | null;
};

export type CodexThreadListResult = {
  status: "success" | "degraded" | "failed";
  fallback_attempted: false;
  source: CodexThreadSource;
  threads: CodexThread[];
  error: null | {
    code: string;
    message: string;
  };
};

export type CodexSendResult = {
  status: "success" | "partial" | "empty_result" | "blocked" | "degraded" | "failed";
  fallback_attempted: false;
  source: CodexSendMode;
  target: {
    sessionId: string;
  };
  result: null | {
    lastMessage?: string;
    stdout?: string;
    stderr?: string;
  };
  error: null | {
    code: string;
    message: string;
  };
};

export type CodexProcessResult = {
  code: number;
  signal: string | null;
  stdout: string;
  stderr: string;
};

export type CodexProcessRunner = (
  command: string,
  args: string[],
  input: string,
  options: {
    cwd?: string;
    timeoutMs: number;
  },
) => Promise<CodexProcessResult>;

export type CodexRemoteClientOptions = {
  codexHome?: string;
  codexBin?: string;
  tempRoot?: string;
  timeoutMs?: number;
  runner?: CodexProcessRunner;
  appServerList?: (input: { limit?: number }) => Promise<CodexThread[]>;
  appServerSend?: (input: { sessionId: string; prompt: string }) => Promise<{ lastMessage?: string }>;
};

export function createCodexRemoteClient(options: CodexRemoteClientOptions = {}) {
  const codexHome = options.codexHome ?? join(homedir(), ".codex");
  const codexBin = options.codexBin ?? DEFAULT_CODEX_BIN;
  const timeoutMs = options.timeoutMs ?? 20 * 60 * 1000;
  const runner = options.runner ?? runCodexProcess;

  return {
    async listThreads(input: { source: CodexThreadSource; limit?: number }): Promise<CodexThreadListResult> {
      if (input.source === "file_scan") {
        try {
          return {
            status: "success",
            fallback_attempted: false,
            source: "file_scan",
            threads: await listFileScanThreads(codexHome, input.limit ?? 100),
            error: null,
          };
        } catch (error) {
          return codexListFailure("file_scan", "file_scan_unavailable", errorMessage(error));
        }
      }
      if (!options.appServerList) {
        return codexListFailure("app_server", "app_server_unavailable", "Codex app-server thread listing is not configured.");
      }
      try {
        return {
          status: "success",
          fallback_attempted: false,
          source: "app_server",
          threads: await options.appServerList({ limit: input.limit }),
          error: null,
        };
      } catch (error) {
        return codexListFailure("app_server", "app_server_unavailable", errorMessage(error));
      }
    },

    async sendPrompt(input: {
      mode: CodexSendMode;
      sessionId: string;
      prompt: string;
    }): Promise<CodexSendResult> {
      if (!input.sessionId.trim()) {
        return codexSendFailure(input.mode, input.sessionId, "session_id_missing", "`sessionId` is required.");
      }
      if (!input.prompt.trim()) {
        return codexSendFailure(input.mode, input.sessionId, "prompt_missing", "`prompt` is required.");
      }
      if (input.mode === "app_server") {
        if (!options.appServerSend) {
          return codexSendFailure("app_server", input.sessionId, "app_server_unavailable", "Codex app-server send is not configured.");
        }
        try {
          const result = await options.appServerSend({
            sessionId: input.sessionId,
            prompt: input.prompt,
          });
          return {
            status: result.lastMessage?.trim() ? "success" : "empty_result",
            fallback_attempted: false,
            source: "app_server",
            target: { sessionId: input.sessionId },
            result: result.lastMessage ? { lastMessage: result.lastMessage } : {},
            error: null,
          };
        } catch (error) {
          return codexSendFailure("app_server", input.sessionId, "app_server_unavailable", errorMessage(error));
        }
      }
      return sendPromptViaCliResume({
        sessionId: input.sessionId,
        prompt: input.prompt,
        codexBin,
        timeoutMs,
        tempRoot: options.tempRoot,
        runner,
      });
    },
  };
}

export function buildCodexExecResumeArgs({
  sessionId,
  outputFile,
  extraArgs = [],
}: {
  sessionId: string;
  outputFile: string;
  extraArgs?: string[];
}): string[] {
  if (!sessionId.trim()) {
    throw new Error("sessionId is required");
  }
  if (!outputFile.trim()) {
    throw new Error("outputFile is required");
  }
  return [
    "exec",
    "resume",
    ...extraArgs,
    "-o",
    outputFile,
    sessionId,
    "-",
  ];
}

async function listFileScanThreads(codexHome: string, limit: number): Promise<CodexThread[]> {
  const candidateLimit = Math.min(Math.max(limit * 3, 80), FILE_SCAN_MAX_CANDIDATE_COUNT);
  const files = await findRecentJsonlFiles(join(codexHome, "sessions"), candidateLimit);
  const threads: CodexThread[] = [];
  for (const file of files) {
    const thread = await readCodexThread(file.filePath, codexHome, file.mtimeMs);
    if (thread) {
      threads.push(thread);
    }
    if (threads.length >= limit) {
      break;
    }
  }
  return threads;
}

async function readCodexThread(
  filePath: string,
  codexHome: string,
  mtimeMs: number,
): Promise<CodexThread | null> {
  let id = "";
  let title = "";
  let cwd = "";
  let updatedAt: string | null = new Date(mtimeMs).toISOString();
  for await (const line of readJsonlLines(filePath, FILE_SCAN_THREAD_READ_LINE_LIMIT)) {
    let event: Record<string, unknown>;
    try {
      event = JSON.parse(line) as Record<string, unknown>;
    } catch {
      continue;
    }
    if (typeof event.timestamp === "string") {
      updatedAt = event.timestamp;
    }
    if (event.type === "session_meta" && isRecord(event.payload)) {
      id = stringField(event.payload, "id") ?? id;
      cwd = stringField(event.payload, "cwd") ?? cwd;
    }
    if (event.type === "event_msg" && isRecord(event.payload)) {
      if (event.payload.type === "thread_name_updated") {
        title = stringField(event.payload, "thread_name") ?? title;
      }
      if (!title && event.payload.type === "user_message") {
        title = stringField(event.payload, "message") ?? title;
      }
    }
  }
  if (!id) {
    return null;
  }
  return {
    id,
    title: truncateOneLine(title || relative(codexHome, filePath) || id, 80),
    cwd,
    updatedAt,
    filePath,
  };
}

async function sendPromptViaCliResume(input: {
  sessionId: string;
  prompt: string;
  codexBin: string;
  timeoutMs: number;
  tempRoot?: string;
  runner: CodexProcessRunner;
}): Promise<CodexSendResult> {
  const tempDir = await mkdtemp(join(input.tempRoot ?? tmpdir(), "geeagent-telegram-codex-"));
  const outputFile = join(tempDir, "last-message.txt");
  const args = buildCodexExecResumeArgs({
    sessionId: input.sessionId,
    outputFile,
  });
  try {
    const result = await input.runner(input.codexBin, args, input.prompt, {
      timeoutMs: input.timeoutMs,
    });
    const lastMessage = await readOutputOrStdout(outputFile, result.stdout);
    return {
      status: lastMessage ? "success" : "empty_result",
      fallback_attempted: false,
      source: "cli_resume",
      target: { sessionId: input.sessionId },
      result: {
        lastMessage,
        stdout: result.stdout,
        stderr: result.stderr,
      },
      error: null,
    };
  } catch (error) {
    return codexSendFailure("cli_resume", input.sessionId, "cli_resume_failed", errorMessage(error));
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
}

async function readOutputOrStdout(outputFile: string, stdout: string): Promise<string> {
  try {
    return (await readFile(outputFile, "utf8")).trim();
  } catch {
    return stdout.trim();
  }
}

async function findRecentJsonlFiles(rootDir: string, limit: number): Promise<Array<{ filePath: string; mtimeMs: number }>> {
  if (!(await directoryExists(rootDir)) || limit <= 0) {
    return [];
  }
  const files: Array<{ filePath: string; mtimeMs: number }> = [];
  const directories = await recentSessionDirectories(rootDir);
  for (const directory of directories) {
    files.push(
      ...(await directJsonlFiles(
        directory,
        Math.min(FILE_SCAN_MAX_FILES_PER_DIRECTORY, Math.max(limit - files.length, 0)),
      )),
    );
    trimRecentFileCandidates(files, limit);
    if (files.length >= limit) {
      break;
    }
  }
  return files;
}

async function recentSessionDirectories(rootDir: string): Promise<string[]> {
  const candidates: string[] = [];
  if ((await directJsonlFiles(rootDir, 1)).length > 0) {
    candidates.push(rootDir);
  }

  for (const yearDir of await childDirectories(rootDir, 6)) {
    if ((await directJsonlFiles(yearDir, 1)).length > 0) {
      candidates.push(yearDir);
    }
    for (const monthDir of await childDirectories(yearDir, 12)) {
      if ((await directJsonlFiles(monthDir, 1)).length > 0) {
        candidates.push(monthDir);
      }
      candidates.push(...(await childDirectories(monthDir, 31)));
    }
  }

  return candidates
    .sort((left, right) => sessionDirectorySortKey(right, rootDir).localeCompare(sessionDirectorySortKey(left, rootDir)))
    .slice(0, FILE_SCAN_RECENT_DIRECTORY_LIMIT);
}

async function childDirectories(directory: string, limit: number): Promise<string[]> {
  if (limit <= 0) {
    return [];
  }
  let dir;
  try {
    dir = await opendir(directory);
  } catch {
    return [];
  }
  const directories: string[] = [];
  const entryReadLimit = Math.max(FILE_SCAN_MAX_DIRECTORY_ENTRY_READS, limit);
  let readCount = 0;
  try {
    while (directories.length < limit && readCount < entryReadLimit) {
      const entry = await dir.read();
      if (!entry) {
        break;
      }
      readCount += 1;
      if (entry.name.startsWith(".")) {
        continue;
      }
      const childPath = join(directory, entry.name);
      let childStat;
      try {
        childStat = await stat(childPath);
      } catch {
        continue;
      }
      if (!childStat.isDirectory()) {
        continue;
      }
      directories.push(childPath);
    }
  } finally {
    await dir.close().catch(() => {});
  }
  return directories.sort((left, right) => right.localeCompare(left)).slice(0, limit);
}

async function directJsonlFiles(directory: string, limit: number): Promise<Array<{ filePath: string; mtimeMs: number }>> {
  if (limit <= 0) {
    return [];
  }
  let dir;
  try {
    dir = await opendir(directory);
  } catch {
    return [];
  }
  const files: Array<{ filePath: string; mtimeMs: number }> = [];
  const entryReadLimit = Math.max(FILE_SCAN_MAX_DIRECTORY_ENTRY_READS, limit);
  let readCount = 0;
  try {
    while (files.length < limit && readCount < entryReadLimit) {
      const entry = await dir.read();
      if (!entry) {
        break;
      }
      readCount += 1;
      if (entry.name.startsWith(".") || !entry.name.endsWith(".jsonl")) {
        continue;
      }
      const filePath = join(directory, entry.name);
      let fileStat;
      try {
        fileStat = await stat(filePath);
      } catch {
        continue;
      }
      if (!fileStat.isFile()) {
        continue;
      }
      files.push({ filePath, mtimeMs: fileStat.mtimeMs });
    }
  } finally {
    await dir.close().catch(() => {});
  }
  trimRecentFileCandidates(files, limit);
  return files;
}

async function directoryExists(rootDir: string): Promise<boolean> {
  let rootStat;
  try {
    rootStat = await stat(rootDir);
  } catch {
    return false;
  }
  return rootStat.isDirectory();
}

function trimRecentFileCandidates(files: Array<{ filePath: string; mtimeMs: number }>, limit: number): void {
  files.sort((left, right) => right.mtimeMs - left.mtimeMs);
  if (files.length > limit) {
    files.splice(limit);
  }
}

function sessionDirectorySortKey(directory: string, rootDir: string): string {
  return relative(rootDir, directory) || "";
}

async function* readJsonlLines(filePath: string, maxLines?: number): AsyncGenerator<string> {
  const stream = createReadStream(filePath, { encoding: "utf8" });
  const lines = createInterface({ input: stream, crlfDelay: Infinity });
  let lineCount = 0;
  for await (const line of lines) {
    const trimmed = line.trim();
    if (trimmed) {
      lineCount += 1;
      if (maxLines !== undefined && lineCount > maxLines) {
        break;
      }
      yield trimmed;
    }
  }
}

function runCodexProcess(
  command: string,
  args: string[],
  input: string,
  options: { cwd?: string; timeoutMs: number },
): Promise<CodexProcessResult> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: options.cwd,
      env: process.env,
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    let settled = false;
    const timer = setTimeout(() => {
      if (settled) {
        return;
      }
      settled = true;
      child.kill("SIGTERM");
      reject(new Error(`Codex timed out after ${options.timeoutMs}ms`));
    }, options.timeoutMs);
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.on("error", (error) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      reject(error);
    });
    child.on("close", (code, signal) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      if (code === 0) {
        resolve({ code, signal, stdout, stderr });
      } else {
        reject(new Error(stderr.trim() || stdout.trim() || `Codex exited with code ${code}`));
      }
    });
    child.stdin.end(input);
  });
}

function codexListFailure(
  source: CodexThreadSource,
  code: string,
  message: string,
): CodexThreadListResult {
  return {
    status: "failed",
    fallback_attempted: false,
    source,
    threads: [],
    error: {
      code,
      message,
    },
  };
}

function codexSendFailure(
  source: CodexSendMode,
  sessionId: string,
  code: string,
  message: string,
): CodexSendResult {
  return {
    status: "failed",
    fallback_attempted: false,
    source,
    target: { sessionId },
    result: null,
    error: {
      code,
      message,
    },
  };
}

function truncateOneLine(value: string, maxLength: number): string {
  const text = value.replace(/\s+/g, " ").trim();
  return text.length <= maxLength ? text : `${text.slice(0, maxLength - 1)}...`;
}

function stringField(record: Record<string, unknown>, key: string): string | undefined {
  const value = record[key];
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
