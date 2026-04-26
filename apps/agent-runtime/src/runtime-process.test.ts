import assert from "node:assert/strict";
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { once } from "node:events";
import readline from "node:readline";
import { describe, it } from "node:test";

type RuntimeProcessEvent = {
  type?: string;
  protocolVersion?: string;
  defaultModel?: string;
  pid?: number;
};

async function withTimeout<T>(
  promise: Promise<T>,
  timeoutMs: number,
  label: string,
): Promise<T> {
  let timeout: ReturnType<typeof setTimeout> | undefined;
  const timeoutPromise = new Promise<T>((_, reject) => {
    timeout = setTimeout(() => {
      reject(new Error(`${label} timed out after ${timeoutMs}ms`));
    }, timeoutMs);
  });

  try {
    return await Promise.race([promise, timeoutPromise]);
  } finally {
    if (timeout) {
      clearTimeout(timeout);
    }
  }
}

function writeCommand(
  child: ChildProcessWithoutNullStreams,
  command: Record<string, unknown>,
): void {
  child.stdin.write(`${JSON.stringify(command)}\n`);
}

describe("runtime process protocol", () => {
  it("starts, initializes the local gateway, and shuts down cleanly", async () => {
    const child = spawn(process.execPath, ["--import", "tsx", "src/index.ts"], {
      cwd: process.cwd(),
      env: {
        ...process.env,
        GEEAGENT_XENODIA_API_KEY: "test-key",
      },
      stdio: ["pipe", "pipe", "pipe"],
    });
    const stderr: string[] = [];
    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk: string) => {
      stderr.push(chunk);
    });

    const lines = readline.createInterface({
      input: child.stdout,
      crlfDelay: Infinity,
    });
    const iterator = lines[Symbol.asyncIterator]();

    const nextEvent = async (): Promise<RuntimeProcessEvent> => {
      const line = await withTimeout(
        iterator.next(),
        5_000,
        `runtime output (${stderr.join("").trim() || "no stderr"})`,
      );
      assert.equal(line.done, false);
      return JSON.parse(line.value) as RuntimeProcessEvent;
    };

    try {
      const ready = await nextEvent();
      assert.equal(ready.type, "runtime.ready");
      assert.equal(ready.protocolVersion, "0.1.0");
      assert.equal(typeof ready.pid, "number");

      writeCommand(child, {
        type: "runtime.init",
        defaultModel: "sonnet",
      });

      const initialized = await nextEvent();
      assert.equal(initialized.type, "runtime.initialized");
      assert.equal(initialized.defaultModel, "sonnet");

      writeCommand(child, {
        type: "runtime.shutdown",
      });

      const [exitCode] = await withTimeout(
        once(child, "exit"),
        5_000,
        `runtime shutdown (${stderr.join("").trim() || "no stderr"})`,
      );
      assert.equal(exitCode, 0);
    } finally {
      lines.close();
      if (!child.killed && child.exitCode === null) {
        child.kill();
      }
    }
  });
});
