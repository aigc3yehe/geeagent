import { argError, errorMessage, getStringArg, hasValidApprovalToken } from "./args.js";
import { runProcess } from "./process.js";
import type { ShellCommandPolicy, ToolOutcome, ToolRequest } from "./types.js";

const SHELL_ALLOW_LIST = new Set([
  "ls",
  "pwd",
  "echo",
  "date",
  "uname",
  "whoami",
  "ps",
  "lsof",
  "docker",
  "git",
  "cat",
  "grep",
  "rg",
  "find",
  "head",
  "tail",
]);

export function shellRequestNeedsApproval(request: ToolRequest): boolean {
  const command = getStringArg(request, "command");
  if (command === undefined) {
    return true;
  }
  return shellCommandPolicy(command, shellArgs(request)) === "allowed_needs_approval";
}

export async function shellRun(request: ToolRequest): Promise<ToolOutcome> {
  const command = getStringArg(request, "command");
  if (command === undefined) {
    return argError(request.tool_id, "command", "required string `command` is missing");
  }
  const args = shellArgs(request);
  const policy = shellCommandPolicy(command, args);
  if (policy === "denied") {
    return {
      kind: "error",
      tool_id: request.tool_id,
      code: "shell.command_not_allowed",
      message: `command \`${command}\` with args ${JSON.stringify(args)} is not allowed in the guarded shell lane`,
    };
  }
  if (policy === "allowed_needs_approval" && !hasValidApprovalToken(request.approval_token)) {
    return {
      kind: "error",
      tool_id: request.tool_id,
      code: "shell.approval_missing",
      message: `command \`${command}\` with args ${JSON.stringify(args)} requires approval before execution`,
    };
  }

  const cwd = getStringArg(request, "cwd");
  try {
    const result = await runProcess(command, args, { cwd });
    return {
      kind: "completed",
      tool_id: request.tool_id,
      payload: {
        command,
        args,
        cwd: cwd ?? null,
        exit_code: result.exitCode,
        stdout: result.stdout,
        stderr: result.stderr,
      },
    };
  } catch (error) {
    return {
      kind: "error",
      tool_id: request.tool_id,
      code: "shell.spawn_failed",
      message: errorMessage(error),
    };
  }
}

function shellArgs(request: ToolRequest): string[] {
  const args = request.arguments?.args;
  if (!Array.isArray(args)) {
    return [];
  }
  return args.filter((value): value is string => typeof value === "string");
}

function shellCommandPolicy(command: string, args: string[]): ShellCommandPolicy {
  if (!commandIsSane(command) || !argsAreSane(args)) {
    return "denied";
  }
  if (!SHELL_ALLOW_LIST.has(command)) {
    return "allowed_needs_approval";
  }
  switch (command) {
    case "ls":
    case "pwd":
    case "echo":
    case "date":
    case "uname":
    case "whoami":
    case "ps":
    case "lsof":
    case "cat":
    case "grep":
    case "rg":
    case "find":
    case "head":
    case "tail":
      return "allowed_no_approval";
    case "docker":
      return dockerShellPolicy(args);
    case "git":
      return gitShellPolicy(args);
    default:
      return "denied";
  }
}

function commandIsSane(command: string): boolean {
  const trimmed = command.trim();
  return (
    trimmed.length > 0 &&
    !trimmed.includes("\n") &&
    !trimmed.includes("\r") &&
    !trimmed.includes("\0") &&
    trimmed.split(/\s+/).length === 1
  );
}

function argsAreSane(args: string[]): boolean {
  return args.every(
    (arg) => !arg.includes("\0") && !arg.includes("\n") && !arg.includes("\r"),
  );
}

function dockerShellPolicy(args: string[]): ShellCommandPolicy {
  switch (args[0]) {
    case "ps":
    case "images":
    case "info":
    case "version":
    case "inspect":
      return "allowed_no_approval";
    default:
      return "denied";
  }
}

function gitShellPolicy(args: string[]): ShellCommandPolicy {
  switch (args[0]) {
    case "status":
    case "branch":
    case "log":
    case "diff":
    case "rev-parse":
      return "allowed_no_approval";
    default:
      return "denied";
  }
}
