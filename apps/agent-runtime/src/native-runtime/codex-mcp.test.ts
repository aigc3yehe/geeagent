import assert from "node:assert/strict";
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { once } from "node:events";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import readline from "node:readline";
import { describe, it } from "node:test";

import { handleNativeRuntimeCommand } from "./commands.js";

type JsonRpcResponse = {
  jsonrpc: "2.0";
  id: string | number;
  result?: Record<string, unknown>;
  error?: {
    code: number;
    message: string;
  };
};

async function writeGearManifest(
  root: string,
  gearID: string,
  manifest: Record<string, unknown>,
): Promise<void> {
  const gearRoot = join(root, gearID);
  await mkdir(gearRoot, { recursive: true });
  await writeFile(join(gearRoot, "gear.json"), JSON.stringify(manifest, null, 2), "utf8");
}

function exportedGearManifest(): Record<string, unknown> {
  return {
    schema: "gee.gear.v1",
    id: "codex.safe",
    name: "Codex Safe Gear",
    agent: {
      enabled: true,
      capabilities: [
        {
          id: "safe.query",
          title: "Safe query",
          description: "Read a safe value.",
          examples: ["Read safe value"],
          input_schema: {
            type: "object",
            properties: {
              key: { type: "string" },
            },
          },
          output_schema: {
            type: "object",
            properties: {
              value: { type: "string" },
            },
          },
          side_effect: "read_only",
          permissions: ["fixture.read"],
          exports: {
            codex: {
              enabled: true,
              risk: "low",
              requires_approval: false,
              skill_hint: "Use when Codex needs the safe fixture value.",
            },
          },
        },
      ],
    },
  };
}

function sendRpc(child: ChildProcessWithoutNullStreams, request: Record<string, unknown>): void {
  child.stdin.write(`${JSON.stringify(request)}\n`);
}

async function nextLine(
  iterator: AsyncIterator<string>,
  stderr: string[],
): Promise<string> {
  const result = await Promise.race([
    iterator.next(),
    new Promise<IteratorResult<string>>((_, reject) =>
      setTimeout(
        () => reject(new Error(`codex MCP server timed out: ${stderr.join("").trim()}`)),
        5_000,
      ),
    ),
  ]);
  assert.equal(result.done, false);
  return result.value;
}

function parseToolText(response: JsonRpcResponse): Record<string, unknown> {
  const result = response.result as
    | {
        isError?: boolean;
        content?: Array<{ type: string; text: string }>;
      }
    | undefined;
  assert.equal(result?.isError, false);
  assert.equal(result?.content?.[0]?.type, "text");
  return JSON.parse(result.content[0].text) as Record<string, unknown>;
}

async function withCodexMcpServer(
  run: (
    child: ChildProcessWithoutNullStreams,
    iterator: AsyncIterator<string>,
    stderr: string[],
  ) => Promise<void>,
): Promise<void> {
  const child = spawn(
    process.execPath,
    ["--import", "tsx", "src/native-runtime/index.ts", "codex-mcp"],
    {
      cwd: process.cwd(),
      stdio: ["pipe", "pipe", "pipe"],
    },
  );
  const stderr: string[] = [];
  child.stderr.setEncoding("utf8");
  child.stderr.on("data", (chunk: string) => stderr.push(chunk));
  const lines = readline.createInterface({ input: child.stdout, crlfDelay: Infinity });
  const iterator = lines[Symbol.asyncIterator]();

  try {
    await run(child, iterator, stderr);
  } finally {
    lines.close();
    child.stdin.end();
    child.kill();
  }
}

describe("Codex MCP export server", () => {
  it("lists Gee MCP tools and serves manifest-backed capability data over stdio", async () => {
    const root = await mkdtemp(join(tmpdir(), "geeagent-codex-mcp-"));
    await writeGearManifest(root, "codex.safe", exportedGearManifest());

    await withCodexMcpServer(async (child, iterator, stderr) => {
      sendRpc(child, {
        jsonrpc: "2.0",
        id: "init",
        method: "initialize",
        params: {
          protocolVersion: "2024-11-05",
          capabilities: {},
          clientInfo: { name: "codex-test", version: "0.0.0" },
        },
      });
      const initialized = JSON.parse(await nextLine(iterator, stderr)) as JsonRpcResponse;
      assert.equal(initialized.error, undefined);
      assert.equal(initialized.result?.serverInfo && (initialized.result.serverInfo as { name: string }).name, "geeagent-codex");

      sendRpc(child, {
        jsonrpc: "2.0",
        id: "tools",
        method: "tools/list",
        params: {},
      });
      const tools = JSON.parse(await nextLine(iterator, stderr)) as JsonRpcResponse;
      const toolNames = ((tools.result?.tools ?? []) as Array<{ name: string }>).map(
        (tool) => tool.name,
      );
      assert.deepEqual(toolNames, [
        "gee_status",
        "gee_list_capabilities",
        "gee_describe_capability",
        "gee_invoke_capability",
        "gee_open_surface",
        "gee_get_invocation",
      ]);

      sendRpc(child, {
        jsonrpc: "2.0",
        id: "list",
        method: "tools/call",
        params: {
          name: "gee_list_capabilities",
          arguments: {
            gear_roots: [root],
            detail: "schema",
          },
        },
      });
      const listed = JSON.parse(await nextLine(iterator, stderr)) as JsonRpcResponse;
      const payload = parseToolText(listed) as {
        status: string;
        capabilities: Array<{ capability_ref: string; input_schema?: unknown }>;
      };
      assert.equal(payload.status, "success");
      assert.equal(payload.capabilities[0]?.capability_ref, "codex.safe/safe.query");
      assert.deepEqual(payload.capabilities[0]?.input_schema, {
        type: "object",
        properties: {
          key: { type: "string" },
        },
      });
    });
  });

  it("refuses to queue invocation for capabilities that are not explicitly exported", async () => {
    await withCodexMcpServer(async (child, iterator, stderr) => {
      sendRpc(child, {
        jsonrpc: "2.0",
        id: "invoke",
        method: "tools/call",
        params: {
          name: "gee_invoke_capability",
          arguments: {
            capability_ref: "codex.safe/safe.query",
            args: { key: "fixture" },
            caller: { client: "codex", thread_id: "thread_123" },
          },
        },
      });
      const invoked = JSON.parse(await nextLine(iterator, stderr)) as JsonRpcResponse;
      const payload = parseToolText(invoked);

      assert.equal(payload.status, "failed");
      assert.equal(payload.code, "gee.codex_export.capability_not_found");
      assert.equal(payload.tool, "gee_invoke_capability");
      assert.equal(payload.fallback_attempted, false);
      assert.match(String(payload.message), /not found/i);
    });
  });

  it("queues an exported Gear invocation for the live GeeAgent host bridge", async () => {
    const configDir = await mkdtemp(join(tmpdir(), "geeagent-codex-config-"));
    const root = await mkdtemp(join(tmpdir(), "geeagent-codex-mcp-"));
    await writeGearManifest(root, "codex.safe", exportedGearManifest());

    const child = spawn(
      process.execPath,
      [
        "--import",
        "tsx",
        "src/native-runtime/index.ts",
        "codex-mcp",
        "--config-dir",
        configDir,
      ],
      {
        cwd: process.cwd(),
        stdio: ["pipe", "pipe", "pipe"],
      },
    );
    const stderr: string[] = [];
    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk: string) => stderr.push(chunk));
    const lines = readline.createInterface({ input: child.stdout, crlfDelay: Infinity });
    const iterator = lines[Symbol.asyncIterator]();

    try {
      sendRpc(child, {
        jsonrpc: "2.0",
        id: "invoke",
        method: "tools/call",
        params: {
          name: "gee_invoke_capability",
          arguments: {
            capability_ref: "codex.safe/safe.query",
            gear_roots: [root],
            args: { key: "fixture" },
            caller: { client: "codex", thread_id: "thread_123", cwd: "/tmp/project" },
            wait_ms: 0,
          },
        },
      });
      const invoked = JSON.parse(await nextLine(iterator, stderr)) as JsonRpcResponse;
      const payload = parseToolText(invoked);
      assert.equal(payload.status, "pending");
      assert.equal(payload.tool, "gee_invoke_capability");
      assert.equal(payload.fallback_attempted, false);
      assert.equal(typeof payload.external_invocation_id, "string");

      const store = JSON.parse(
        await readFile(join(configDir, "runtime-store.json"), "utf8"),
      ) as {
        external_invocations?: Array<{
          external_invocation_id: string;
          tool: string;
          status: string;
          gear_id: string;
          capability_id: string;
          args: Record<string, unknown>;
          caller: Record<string, unknown>;
        }>;
      };
      assert.deepEqual(store.external_invocations?.map((record) => record.status), ["pending"]);
      assert.equal(store.external_invocations?.[0]?.external_invocation_id, payload.external_invocation_id);
      assert.equal(store.external_invocations?.[0]?.tool, "gee_invoke_capability");
      assert.equal(store.external_invocations?.[0]?.gear_id, "codex.safe");
      assert.equal(store.external_invocations?.[0]?.capability_id, "safe.query");
      assert.deepEqual(store.external_invocations?.[0]?.args, { key: "fixture" });
      assert.equal(store.external_invocations?.[0]?.caller.thread_id, "thread_123");
    } finally {
      lines.close();
      child.stdin.end();
      child.kill();
    }
  });

  it("returns completed external invocation results through gee_get_invocation", async () => {
    const configDir = await mkdtemp(join(tmpdir(), "geeagent-codex-config-"));
    const root = await mkdtemp(join(tmpdir(), "geeagent-codex-mcp-"));
    await writeGearManifest(root, "codex.safe", exportedGearManifest());

    await withCodexMcpServer(async (child, iterator, stderr) => {
      sendRpc(child, {
        jsonrpc: "2.0",
        id: "invoke",
        method: "tools/call",
        params: {
          name: "gee_invoke_capability",
          arguments: {
            capability_ref: "codex.safe/safe.query",
            gear_roots: [root],
            args: { key: "fixture" },
            wait_ms: 0,
            config_dir: configDir,
          },
        },
      });
      const invoked = JSON.parse(await nextLine(iterator, stderr)) as JsonRpcResponse;
      const pending = parseToolText(invoked);
      const invocationID = String(pending.external_invocation_id);

      await handleNativeRuntimeCommand("codex-external-invocation-complete", [
        JSON.stringify({
          external_invocation_id: invocationID,
          status: "running",
        }),
      ], { configDir });

      sendRpc(child, {
        jsonrpc: "2.0",
        id: "running",
        method: "tools/call",
        params: {
          name: "gee_get_invocation",
          arguments: {
            invocation_id: invocationID,
            config_dir: configDir,
          },
        },
      });
      const runningResponse = JSON.parse(await nextLine(iterator, stderr)) as JsonRpcResponse;
      const running = parseToolText(runningResponse);
      assert.equal(running.status, "running");

      await handleNativeRuntimeCommand("codex-external-invocation-complete", [
        JSON.stringify({
          external_invocation_id: invocationID,
          status: "success",
          result: {
            value: "from-gear-host",
          },
        }),
      ], { configDir });

      sendRpc(child, {
        jsonrpc: "2.0",
        id: "get",
        method: "tools/call",
        params: {
          name: "gee_get_invocation",
          arguments: {
            invocation_id: invocationID,
            config_dir: configDir,
          },
        },
      });
      const received = JSON.parse(await nextLine(iterator, stderr)) as JsonRpcResponse;
      const completed = parseToolText(received);
      assert.equal(completed.status, "success");
      assert.equal(completed.external_invocation_id, invocationID);
      assert.deepEqual(completed.result, { value: "from-gear-host" });
    });
  });
});

describe("Codex plugin package generation", () => {
  it("writes a local GeeAgent Codex plugin package wired to the Gee MCP export server", async () => {
    const pluginRoot = await mkdtemp(join(tmpdir(), "geeagent-codex-plugin-"));
    const raw = await handleNativeRuntimeCommand("codex-export-generate-plugin", [
      JSON.stringify({
        output_dir: pluginRoot,
        runtime_command: "node",
        runtime_args: ["/opt/geeagent/dist/native-runtime/index.mjs", "codex-mcp"],
      }),
    ]);
    const result = JSON.parse(raw) as {
      status: string;
      plugin_root: string;
      files: string[];
    };

    assert.equal(result.status, "success");
    assert.equal(result.plugin_root, pluginRoot);
    assert.deepEqual(
      result.files.sort(),
      [
        ".codex-plugin/plugin.json",
        ".mcp.json",
        "skills/gee-capabilities/SKILL.md",
      ].sort(),
    );

    const plugin = JSON.parse(
      await readFile(join(pluginRoot, ".codex-plugin", "plugin.json"), "utf8"),
    ) as {
      name: string;
      skills: string;
      mcpServers: string;
      interface: {
        displayName: string;
        capabilities: string[];
      };
    };
    assert.equal(plugin.name, "geeagent-codex");
    assert.equal(plugin.skills, "./skills/");
    assert.equal(plugin.mcpServers, "./.mcp.json");
    assert.deepEqual(plugin.interface.capabilities, ["MCP", "Skills"]);

    const mcp = JSON.parse(await readFile(join(pluginRoot, ".mcp.json"), "utf8")) as {
      mcpServers: {
        geeagent: {
          command: string;
          args: string[];
        };
      };
    };
    assert.equal(mcp.mcpServers.geeagent.command, "node");
    assert.deepEqual(mcp.mcpServers.geeagent.args, [
      "/opt/geeagent/dist/native-runtime/index.mjs",
      "codex-mcp",
    ]);

    const skill = await readFile(
      join(pluginRoot, "skills", "gee-capabilities", "SKILL.md"),
      "utf8",
    );
    assert.match(skill, /gee_status/);
    assert.match(skill, /gee_list_capabilities/);
    assert.match(skill, /Do not run fallback scripts/);
  });

  it("defaults the generated MCP config to the current native-runtime entrypoint", async () => {
    const pluginRoot = await mkdtemp(join(tmpdir(), "geeagent-codex-plugin-"));
    const child = spawn(
      process.execPath,
      [
        "--import",
        "tsx",
        "src/native-runtime/index.ts",
        "codex-export-generate-plugin",
        JSON.stringify({ output_dir: pluginRoot }),
      ],
      {
        cwd: process.cwd(),
        stdio: ["ignore", "pipe", "pipe"],
      },
    );
    const stdout: string[] = [];
    const stderr: string[] = [];
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk: string) => stdout.push(chunk));
    child.stderr.on("data", (chunk: string) => stderr.push(chunk));
    const [code] = (await once(child, "exit")) as [number | null, NodeJS.Signals | null];
    assert.equal(code, 0, stderr.join(""));

    const generated = JSON.parse(stdout.join("")) as {
      status: string;
      mcp_server: {
        command: string;
        args: string[];
      };
    };
    assert.equal(generated.status, "success");
    assert.equal(generated.mcp_server.command, process.execPath);

    const mcp = JSON.parse(await readFile(join(pluginRoot, ".mcp.json"), "utf8")) as {
      mcpServers: {
        geeagent: {
          command: string;
          args: string[];
        };
      };
    };
    assert.equal(mcp.mcpServers.geeagent.command, process.execPath);
    assert.deepEqual(mcp.mcpServers.geeagent.args, [
      "--import",
      "tsx",
      resolve(process.cwd(), "src/native-runtime/index.ts"),
      "codex-mcp",
    ]);
  });

  it("refreshes an explicit Codex marketplace entry when requested", async () => {
    const root = await mkdtemp(join(tmpdir(), "geeagent-codex-marketplace-"));
    const pluginRoot = join(root, "plugins", "geeagent-codex");
    const marketplacePath = join(root, ".agents", "plugins", "marketplace.json");

    const raw = await handleNativeRuntimeCommand("codex-export-generate-plugin", [
      JSON.stringify({
        output_dir: pluginRoot,
        runtime_command: "node",
        runtime_args: ["/opt/geeagent/dist/native-runtime/index.mjs", "codex-mcp"],
        marketplace_path: marketplacePath,
        marketplace_name: "geeagent-local",
        marketplace_display_name: "GeeAgent Local",
        marketplace_plugin_path: "./plugins/geeagent-codex",
      }),
    ]);
    const result = JSON.parse(raw) as {
      status: string;
      marketplace_file?: string;
    };
    assert.equal(result.status, "success");
    assert.equal(result.marketplace_file, marketplacePath);

    const marketplace = JSON.parse(await readFile(marketplacePath, "utf8")) as {
      name: string;
      interface: { displayName: string };
      plugins: Array<{
        name: string;
        source: { source: string; path: string };
        policy: { installation: string; authentication: string };
        category: string;
      }>;
    };
    assert.equal(marketplace.name, "geeagent-local");
    assert.equal(marketplace.interface.displayName, "GeeAgent Local");
    assert.deepEqual(marketplace.plugins, [
      {
        name: "geeagent-codex",
        source: {
          source: "local",
          path: "./plugins/geeagent-codex",
        },
        policy: {
          installation: "AVAILABLE",
          authentication: "ON_INSTALL",
        },
        category: "Productivity",
      },
    ]);
  });
});
