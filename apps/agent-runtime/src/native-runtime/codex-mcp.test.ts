import assert from "node:assert/strict";
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { once } from "node:events";
import { mkdir, mkdtemp, readdir, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
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

function exportedGearManifest(
  gearID = "codex.safe",
  gearName = "Codex Safe Gear",
): Record<string, unknown> {
  return {
    schema: "gee.gear.v1",
    id: gearID,
    name: gearName,
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

  it("queues Codex Media Library file imports for the live GearHost bridge", async () => {
    const configDir = await mkdtemp(join(tmpdir(), "geeagent-codex-config-"));

    await withCodexMcpServer(async (child, iterator, stderr) => {
      sendRpc(child, {
        jsonrpc: "2.0",
        id: "invoke-media-import",
        method: "tools/call",
        params: {
          name: "gee_invoke_capability",
          arguments: {
            capability_ref: "media.library/media.import_files",
            args: { paths: ["/tmp/geeagent-demo/sample.png"] },
            caller: { client: "codex", thread_id: "thread_media_import" },
            wait_ms: 0,
            config_dir: configDir,
          },
        },
      });
      const invoked = JSON.parse(await nextLine(iterator, stderr)) as JsonRpcResponse;
      const payload = parseToolText(invoked);
      assert.equal(payload.status, "pending");
      assert.equal(payload.tool, "gee_invoke_capability");

      const store = JSON.parse(
        await readFile(join(configDir, "runtime-store.json"), "utf8"),
      ) as {
        external_invocations?: Array<{
          gear_id: string;
          capability_id: string;
          args: Record<string, unknown>;
          caller: Record<string, unknown>;
        }>;
      };
      assert.equal(store.external_invocations?.[0]?.gear_id, "media.library");
      assert.equal(store.external_invocations?.[0]?.capability_id, "media.import_files");
      assert.deepEqual(store.external_invocations?.[0]?.args, {
        paths: ["/tmp/geeagent-demo/sample.png"],
      });
      assert.equal(store.external_invocations?.[0]?.caller.thread_id, "thread_media_import");
    });
  });

  it("queues Codex App Icon Forge generation for the live GearHost bridge", async () => {
    const configDir = await mkdtemp(join(tmpdir(), "geeagent-codex-config-"));

    await withCodexMcpServer(async (child, iterator, stderr) => {
      sendRpc(child, {
        jsonrpc: "2.0",
        id: "invoke-app-icon",
        method: "tools/call",
        params: {
          name: "gee_invoke_capability",
          arguments: {
            capability_ref: "app.icon.forge/app_icon.generate",
            args: {
              source_path: "/tmp/geeagent-demo/logo.png",
              output_dir: "/tmp/geeagent-demo/icons",
              name: "AppIcon",
            },
            caller: { client: "codex", thread_id: "thread_app_icon" },
            wait_ms: 0,
            config_dir: configDir,
          },
        },
      });
      const invoked = JSON.parse(await nextLine(iterator, stderr)) as JsonRpcResponse;
      const payload = parseToolText(invoked);
      assert.equal(payload.status, "pending");
      assert.equal(payload.tool, "gee_invoke_capability");

      const store = JSON.parse(
        await readFile(join(configDir, "runtime-store.json"), "utf8"),
      ) as {
        external_invocations?: Array<{
          gear_id: string;
          capability_id: string;
          args: Record<string, unknown>;
          caller: Record<string, unknown>;
        }>;
      };
      assert.equal(store.external_invocations?.[0]?.gear_id, "app.icon.forge");
      assert.equal(store.external_invocations?.[0]?.capability_id, "app_icon.generate");
      assert.deepEqual(store.external_invocations?.[0]?.args, {
        source_path: "/tmp/geeagent-demo/logo.png",
        output_dir: "/tmp/geeagent-demo/icons",
        name: "AppIcon",
      });
      assert.equal(store.external_invocations?.[0]?.caller.thread_id, "thread_app_icon");
    });
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

  it("can wait briefly for a prior external invocation through gee_get_invocation", async () => {
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

      setTimeout(() => {
        void handleNativeRuntimeCommand("codex-external-invocation-complete", [
          JSON.stringify({
            external_invocation_id: invocationID,
            status: "success",
            result: {
              value: "waited-for-gear-host",
            },
          }),
        ], { configDir });
      }, 100);

      sendRpc(child, {
        jsonrpc: "2.0",
        id: "wait",
        method: "tools/call",
        params: {
          name: "gee_get_invocation",
          arguments: {
            invocation_id: invocationID,
            wait_ms: 2_000,
            config_dir: configDir,
          },
        },
      });
      const received = JSON.parse(await nextLine(iterator, stderr)) as JsonRpcResponse;
      const completed = parseToolText(received);
      assert.equal(completed.status, "success");
      assert.deepEqual(completed.result, { value: "waited-for-gear-host" });
    });
  });

  it("degrades stale running invocations instead of leaving Codex waiting forever", async () => {
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

      const storePath = join(configDir, "runtime-store.json");
      const store = JSON.parse(await readFile(storePath, "utf8")) as {
        external_invocations: Array<{ external_invocation_id: string; updated_at: string }>;
      };
      store.external_invocations = store.external_invocations.map((record) =>
        record.external_invocation_id === invocationID
          ? { ...record, updated_at: "2026-01-01T00:00:00.000Z" }
          : record,
      );
      await writeFile(storePath, `${JSON.stringify(store, null, 2)}\n`, "utf8");

      sendRpc(child, {
        jsonrpc: "2.0",
        id: "stale",
        method: "tools/call",
        params: {
          name: "gee_get_invocation",
          arguments: {
            invocation_id: invocationID,
            config_dir: configDir,
          },
        },
      });
      const staleResponse = JSON.parse(await nextLine(iterator, stderr)) as JsonRpcResponse;
      const stale = parseToolText(staleResponse);
      assert.equal(stale.status, "degraded");
      assert.equal((stale.error as { code?: string }).code, "gee.external_invocation.running_stale");
      assert.equal(stale.fallback_attempted, false);
      assert.match(
        String((stale.recovery as { message?: string }).message),
        /not be retried automatically/i,
      );
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
    assert.equal(result.files.includes(".codex-plugin/plugin.json"), true);
    assert.equal(result.files.includes(".mcp.json"), true);
    assert.equal(result.files.includes("skills/gee-capabilities/SKILL.md"), true);
    assert.equal(
      result.files.includes("skills/gee-capabilities/references/capability-index.md"),
      true,
    );
    assert.equal(
      result.files.includes("skills/gee-capabilities/references/telegram.bridge.md"),
      true,
    );
    assert.equal(result.files.includes("gears/telegram.bridge/gear.json"), true);

    const plugin = JSON.parse(
      await readFile(join(pluginRoot, ".codex-plugin", "plugin.json"), "utf8"),
    ) as {
      name: string;
      version: string;
      skills: string;
      mcpServers: string;
      interface: {
        displayName: string;
        capabilities: string[];
      };
    };
    assert.equal(plugin.name, "geeagent-codex");
    assert.equal(plugin.version, "0.1.3");
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
    assert.match(skill, /first entry point/i);
    assert.match(skill, /references\/capability-index\.md/);
    assert.match(skill, /telegram\.bridge/);
    assert.match(skill, /Do not run fallback scripts/);

    const index = await readFile(
      join(pluginRoot, "skills", "gee-capabilities", "references", "capability-index.md"),
      "utf8",
    );
    assert.match(index, /telegram\.bridge\/telegram_push\.send_message/);
    assert.match(index, /media\.generator\/media_generator\.create_task/);

    const telegram = await readFile(
      join(pluginRoot, "skills", "gee-capabilities", "references", "telegram.bridge.md"),
      "utf8",
    );
    assert.match(telegram, /telegram\.bridge\/telegram_push\.send_message/);
    assert.match(telegram, /idempotency_key/);
    assert.match(telegram, /configured push-only Telegram channels/i);

    const bundledTelegramManifest = JSON.parse(
      await readFile(join(pluginRoot, "gears", "telegram.bridge", "gear.json"), "utf8"),
    ) as {
      schema: string;
      id: string;
      agent: { capabilities: Array<{ id: string }> };
    };
    assert.equal(bundledTelegramManifest.schema, "gee.gear.v1");
    assert.equal(bundledTelegramManifest.id, "telegram.bridge");
    assert.deepEqual(
      bundledTelegramManifest.agent.capabilities.map((capability) => capability.id),
      [
        "telegram_bridge.status",
        "telegram_push.list_channels",
        "telegram_push.send_message",
      ],
    );

    const bundledRaw = await handleNativeRuntimeCommand("codex-export-list-capabilities", [
      JSON.stringify({ gear_roots: [join(pluginRoot, "gears")], gear_id: "telegram.bridge" }),
    ]);
    const bundled = JSON.parse(bundledRaw) as {
      status: string;
      capabilities: Array<{ capability_ref: string }>;
    };
    assert.equal(bundled.status, "success");
    assert.deepEqual(
      bundled.capabilities.map((capability) => capability.capability_ref),
      [
        "telegram.bridge/telegram_bridge.status",
        "telegram.bridge/telegram_push.list_channels",
        "telegram.bridge/telegram_push.send_message",
      ],
    );
  });

  it("removes stale generated capability references when refreshing a plugin package", async () => {
    const pluginRoot = await mkdtemp(join(tmpdir(), "geeagent-codex-plugin-refresh-"));
    const firstGearRoot = await mkdtemp(join(tmpdir(), "geeagent-codex-gears-a-"));
    const secondGearRoot = await mkdtemp(join(tmpdir(), "geeagent-codex-gears-b-"));
    await writeGearManifest(firstGearRoot, "codex.safe", exportedGearManifest());
    await writeGearManifest(
      secondGearRoot,
      "codex.next",
      exportedGearManifest("codex.next", "Codex Next Gear"),
    );

    const firstRaw = await handleNativeRuntimeCommand("codex-export-generate-plugin", [
      JSON.stringify({
        output_dir: pluginRoot,
        runtime_command: "node",
        runtime_args: ["/opt/geeagent/dist/native-runtime/index.mjs", "codex-mcp"],
        gear_roots: [firstGearRoot],
      }),
    ]);
    const first = JSON.parse(firstRaw) as { status: string };
    assert.equal(first.status, "success");
    let references = await readdir(join(pluginRoot, "skills", "gee-capabilities", "references"));
    assert.equal(references.includes("codex.safe.md"), true);
    let gearProjections = await readdir(join(pluginRoot, "gears"));
    assert.equal(gearProjections.includes("codex.safe"), true);

    const secondRaw = await handleNativeRuntimeCommand("codex-export-generate-plugin", [
      JSON.stringify({
        output_dir: pluginRoot,
        runtime_command: "node",
        runtime_args: ["/opt/geeagent/dist/native-runtime/index.mjs", "codex-mcp"],
        gear_roots: [secondGearRoot],
      }),
    ]);
    const second = JSON.parse(secondRaw) as {
      status: string;
      capability_index: { capability_count: number };
    };

    assert.equal(second.status, "success");
    assert.equal(second.capability_index.capability_count, 1);
    references = await readdir(join(pluginRoot, "skills", "gee-capabilities", "references"));
    assert.equal(references.includes("codex.safe.md"), false);
    assert.equal(references.includes("codex.next.md"), true);
    assert.equal(references.includes("capability-index.md"), true);
    gearProjections = await readdir(join(pluginRoot, "gears"));
    assert.equal(gearProjections.includes("codex.safe"), false);
    assert.equal(gearProjections.includes("codex.next"), true);
  });

  it("refreshes from plugin-local runtime and manifest projections without wiping sources", async () => {
    const pluginRoot = await mkdtemp(join(tmpdir(), "geeagent-codex-plugin-self-refresh-"));
    const gearRoot = await mkdtemp(join(tmpdir(), "geeagent-codex-gears-"));
    const runtimeBundlePath = join(tmpdir(), "geeagent-codex-self-refresh-runtime-bundle.mjs");
    await writeFile(runtimeBundlePath, "console.log('self refresh runtime fixture');\n", "utf8");
    await writeGearManifest(gearRoot, "codex.safe", exportedGearManifest());

    const firstRaw = await handleNativeRuntimeCommand("codex-export-generate-plugin", [
      JSON.stringify({
        output_dir: pluginRoot,
        runtime_bundle_path: runtimeBundlePath,
        gear_roots: [gearRoot],
      }),
    ]);
    const first = JSON.parse(firstRaw) as { status: string };
    assert.equal(first.status, "success");

    const pluginRuntimePath = join(
      pluginRoot,
      "runtime",
      "native-runtime",
      "0.1.3",
      "index.mjs",
    );
    const secondRaw = await handleNativeRuntimeCommand("codex-export-generate-plugin", [
      JSON.stringify({
        output_dir: pluginRoot,
        runtime_bundle_path: pluginRuntimePath,
        gear_roots: [join(pluginRoot, "gears")],
      }),
    ]);
    const second = JSON.parse(secondRaw) as {
      status: string;
      capability_index: { capability_count: number };
      runtime_bundle?: { path: string };
    };

    assert.equal(second.status, "success");
    assert.equal(second.capability_index.capability_count, 1);
    assert.equal(second.runtime_bundle?.path, pluginRuntimePath);
    assert.equal(
      await readFile(pluginRuntimePath, "utf8"),
      "console.log('self refresh runtime fixture');\n",
    );
    assert.deepEqual(await readdir(join(pluginRoot, "gears")), ["codex.safe"]);
  });

  it("defaults source-launched plugin generation to the stable built native-runtime entrypoint", async () => {
    const pluginRoot = await mkdtemp(join(tmpdir(), "geeagent-codex-plugin-"));
    const runtimeBundlePath = join(tmpdir(), "geeagent-codex-runtime-bundle.mjs");
    await writeFile(runtimeBundlePath, "console.log('runtime bundle fixture');\n", "utf8");
    const child = spawn(
      process.execPath,
      [
        "--import",
        "tsx",
        "src/native-runtime/index.ts",
        "codex-export-generate-plugin",
        JSON.stringify({ output_dir: pluginRoot, runtime_bundle_path: runtimeBundlePath }),
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
      runtime_bundle: {
        path: string;
        version: string;
      };
    };
    assert.equal(generated.status, "success");
    assert.equal(generated.mcp_server.command, process.execPath);
    assert.equal(generated.runtime_bundle.version, "0.1.3");
    assert.equal(
      generated.runtime_bundle.path,
      join(pluginRoot, "runtime", "native-runtime", "0.1.3", "index.mjs"),
    );

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
      join(pluginRoot, "runtime", "native-runtime", "0.1.3", "index.mjs"),
      "codex-mcp",
    ]);
    assert.equal(mcp.mcpServers.geeagent.args.includes("tsx"), false);
    assert.equal(mcp.mcpServers.geeagent.args[0]?.includes("/private/example/geeagent"), false);
    assert.equal(
      await readFile(join(pluginRoot, "runtime", "native-runtime", "0.1.3", "index.mjs"), "utf8"),
      "console.log('runtime bundle fixture');\n",
    );
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

  it("installs a home-local GeeAgent Codex plugin with marketplace defaults", async () => {
    const homeDir = await mkdtemp(join(tmpdir(), "geeagent-codex-home-"));
    const runtimeBundlePath = join(tmpdir(), "geeagent-codex-install-runtime-bundle.mjs");
    await writeFile(runtimeBundlePath, "console.log('install runtime bundle fixture');\n", "utf8");
    const raw = await handleNativeRuntimeCommand("codex-export-install-plugin", [
      JSON.stringify({
        home_dir: homeDir,
        runtime_bundle_path: runtimeBundlePath,
      }),
    ]);
    const result = JSON.parse(raw) as {
      status: string;
      plugin_root: string;
      marketplace_file?: string;
      install_hint?: string;
      runtime_bundle?: {
        path: string;
        version: string;
      };
      codex_cache: {
        plugin_root: string;
        runtime_bundle?: {
          path: string;
          version: string;
        };
      };
    };

    assert.equal(result.status, "success");
    assert.equal(result.plugin_root, join(homeDir, "plugins", "geeagent-codex"));
    assert.equal(
      result.codex_cache.plugin_root,
      join(homeDir, ".codex", "plugins", "cache", "geeagent-local", "geeagent-codex", "0.1.3"),
    );
    assert.equal(result.marketplace_file, join(homeDir, ".agents", "plugins", "marketplace.json"));
    assert.match(String(result.install_hint), /cache was refreshed/i);
    assert.equal(result.runtime_bundle?.version, "0.1.3");
    assert.equal(
      result.runtime_bundle?.path,
      join(homeDir, "plugins", "geeagent-codex", "runtime", "native-runtime", "0.1.3", "index.mjs"),
    );
    assert.equal(result.codex_cache.runtime_bundle?.version, "0.1.3");
    assert.equal(
      result.codex_cache.runtime_bundle?.path,
      join(
        homeDir,
        ".codex",
        "plugins",
        "cache",
        "geeagent-local",
        "geeagent-codex",
        "0.1.3",
        "runtime",
        "native-runtime",
        "0.1.3",
        "index.mjs",
      ),
    );

    const mcp = JSON.parse(
      await readFile(join(homeDir, "plugins", "geeagent-codex", ".mcp.json"), "utf8"),
    ) as {
      mcpServers: {
        geeagent: {
          command: string;
          args: string[];
        };
      };
    };
    assert.equal(mcp.mcpServers.geeagent.command, process.execPath);
    assert.deepEqual(mcp.mcpServers.geeagent.args, [
      join(homeDir, "plugins", "geeagent-codex", "runtime", "native-runtime", "0.1.3", "index.mjs"),
      "codex-mcp",
    ]);
    assert.equal(mcp.mcpServers.geeagent.args[0]?.includes("/private/example/geeagent"), false);

    const cachedMcp = JSON.parse(
      await readFile(
        join(
          homeDir,
          ".codex",
          "plugins",
          "cache",
          "geeagent-local",
          "geeagent-codex",
          "0.1.3",
          ".mcp.json",
        ),
        "utf8",
      ),
    ) as {
      mcpServers: {
        geeagent: {
          command: string;
          args: string[];
        };
      };
    };
    assert.equal(cachedMcp.mcpServers.geeagent.command, process.execPath);
    assert.deepEqual(cachedMcp.mcpServers.geeagent.args, [
      join(
        homeDir,
        ".codex",
        "plugins",
        "cache",
        "geeagent-local",
        "geeagent-codex",
        "0.1.3",
        "runtime",
        "native-runtime",
        "0.1.3",
        "index.mjs",
      ),
      "codex-mcp",
    ]);
    assert.equal(cachedMcp.mcpServers.geeagent.args.includes("tsx"), false);
    assert.equal(cachedMcp.mcpServers.geeagent.args[0]?.includes("/private/example/geeagent"), false);
    assert.equal(
      await readFile(
        join(
          homeDir,
          ".codex",
          "plugins",
          "cache",
          "geeagent-local",
          "geeagent-codex",
          "0.1.3",
          "runtime",
          "native-runtime",
          "0.1.3",
          "index.mjs",
        ),
        "utf8",
      ),
      "console.log('install runtime bundle fixture');\n",
    );
    assert.equal(
      (await readdir(
        join(
          homeDir,
          ".codex",
          "plugins",
          "cache",
          "geeagent-local",
          "geeagent-codex",
          "0.1.3",
          "gears",
        ),
      )).includes("telegram.bridge"),
      true,
    );

    const marketplace = JSON.parse(
      await readFile(join(homeDir, ".agents", "plugins", "marketplace.json"), "utf8"),
    ) as {
      name: string;
      interface: { displayName: string };
      plugins: Array<{ name: string; source: { source: string; path: string } }>;
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
