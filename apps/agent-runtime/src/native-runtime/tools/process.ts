import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";

const activeProcesses = new Set<ChildProcessWithoutNullStreams>();

export function runProcess(
  command: string,
  args: string[],
  options: { cwd?: string; input?: string } = {},
): Promise<{ exitCode: number | null; stdout: string; stderr: string }> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: options.cwd,
      stdio: ["pipe", "pipe", "pipe"],
    });
    activeProcesses.add(child);
    const stdout: Buffer[] = [];
    const stderr: Buffer[] = [];

    child.stdout.on("data", (chunk: Buffer) => stdout.push(chunk));
    child.stderr.on("data", (chunk: Buffer) => stderr.push(chunk));
    child.on("error", (error) => {
      activeProcesses.delete(child);
      reject(error);
    });
    child.on("close", (exitCode) => {
      activeProcesses.delete(child);
      resolve({
        exitCode,
        stdout: Buffer.concat(stdout).toString("utf8"),
        stderr: Buffer.concat(stderr).toString("utf8"),
      });
    });

    if (options.input !== undefined) {
      child.stdin.end(options.input);
    } else {
      child.stdin.end();
    }
  });
}

export function terminateActiveProcesses(): void {
  for (const child of activeProcesses) {
    if (child.killed) {
      continue;
    }
    child.kill("SIGTERM");
    setTimeout(() => {
      if (activeProcesses.has(child)) {
        child.kill("SIGKILL");
      }
    }, 250);
  }
}

export function applescriptStringLiteral(input: string): string {
  return `"${input.replaceAll('"', '""')}"`;
}
