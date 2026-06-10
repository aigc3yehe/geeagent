import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";

import { handleAgentGatewayMcpRequest } from "./agent-gateway-mcp-server.js";
import { handleNativeRuntimeCommand } from "./commands.js";

type JsonRpcResponse = {
  jsonrpc: "2.0";
  id: string | number | null;
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

function gatewayFixtureManifest(): Record<string, unknown> {
  return {
    schema: "gee.gear.v1",
    id: "gateway.safe",
    name: "Gateway Safe Gear",
    agent: {
      enabled: true,
      capabilities: [
        {
          id: "codex.query",
          title: "Codex query",
          description: "Read a value through the Codex compatibility policy.",
          examples: ["Read Codex value"],
          input_schema: {
            type: "object",
            required: ["key"],
            properties: {
              key: { type: "string" },
            },
          },
          side_effect: "read_only",
          permissions: ["fixture.read"],
          exports: {
            codex: {
              enabled: true,
              risk: "low",
              requires_approval: false,
              skill_hint: "Use for Codex compatibility checks.",
            },
          },
        },
        {
          id: "claude.query",
          title: "Claude Code query",
          description: "Read a value through the neutral agent gateway policy.",
          examples: ["Read Claude value"],
          input_schema: {
            type: "object",
            required: ["key"],
            properties: {
              key: { type: "string" },
            },
          },
          side_effect: "read_only",
          permissions: ["fixture.read"],
          exports: {
            agent_gateway: {
              enabled: true,
              clients: ["claude_code"],
              risk: "low",
              requires_approval: false,
              skill_hint: "Use for Claude Code checks.",
            },
          },
        },
        {
          id: "shared.status",
          title: "Shared status",
          description: "Read a value available to all personal-agent clients.",
          examples: ["Read shared status"],
          side_effect: "read_only",
          exports: {
            agent_gateway: {
              enabled: true,
              clients: ["*"],
              risk: "low",
              requires_approval: false,
            },
          },
        },
      ],
    },
  };
}

function claudeOnlyFixtureManifest(): Record<string, unknown> {
  return {
    schema: "gee.gear.v1",
    id: "gateway.claude.only",
    name: "Claude Only Gear",
    agent: {
      enabled: true,
      capabilities: [
        {
          id: "claude.only",
          title: "Claude only",
          description: "Only Claude Code can see this capability.",
          exports: {
            agent_gateway: {
              enabled: true,
              clients: ["claude_code"],
              risk: "low",
              requires_approval: false,
            },
          },
        },
      ],
    },
  };
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

describe("Gee Agent Gateway", () => {
  it("reports the neutral MCP tool surface", async () => {
    const raw = await handleNativeRuntimeCommand("agent-gateway-status");
    const result = JSON.parse(raw) as {
      status: string;
      standard: string;
      implemented_tools: string[];
      bridge_required_tools: string[];
      supported_clients: string[];
      transport_policy: Record<string, unknown>;
    };

    assert.equal(result.status, "success");
    assert.equal(result.standard, "gee.agent_gateway.v0.1");
    assert.deepEqual(result.implemented_tools, [
      "gee_status",
      "gee_search_capabilities",
      "gee_describe_capability",
      "gee_run_capability",
      "gee_get_run",
      "gee_prepare_gear",
      "gee_open_surface",
    ]);
    assert.deepEqual(result.bridge_required_tools, [
      "gee_run_capability",
      "gee_open_surface",
    ]);
    assert.deepEqual(result.supported_clients, [
      "codex",
      "claude_code",
      "workbuddy",
      "gee_internal",
    ]);
    assert.equal(result.transport_policy.http_local_only, true);
  });

  it("reports per-agent MCP configuration material without writing client settings", async () => {
    const configDir = await mkdtemp(join(tmpdir(), "geeagent-agent-gateway-config-"));
    const raw = await handleNativeRuntimeCommand(
      "agent-gateway-client-status",
      [
        JSON.stringify({
          runtime_command: "node",
          runtime_entrypoint: "/opt/geeagent/dist/native-runtime/index.mjs",
        }),
      ],
      { configDir },
    );
    const result = JSON.parse(raw) as {
      status: string;
      standard: string;
      client_count: number;
      default_priority: string[];
      supported_clients: string[];
      config_dir: string;
      clients: Array<{
        client_id: string;
        title: string;
        priority: number;
        integration_state: string;
        connection_state: string;
        install_policy: string;
        fallback_attempted: boolean;
        mcp_server: {
          command: string;
          args: string[];
        };
        config_snippets: Array<{
          label: string;
          format: string;
          body: string;
        }>;
      }>;
    };

    assert.equal(result.status, "success");
    assert.equal(result.standard, "gee.agent_gateway.v0.1");
    assert.equal(result.client_count, 3);
    assert.deepEqual(result.default_priority, ["codex", "claude_code", "workbuddy"]);
    assert.deepEqual(result.supported_clients, [
      "codex",
      "claude_code",
      "workbuddy",
      "gee_internal",
    ]);
    assert.equal(result.config_dir, configDir);

    const codex = result.clients[0];
    assert.equal(codex?.client_id, "codex");
    assert.equal(codex?.title, "Codex");
    assert.equal(codex?.priority, 1);
    assert.equal(codex?.integration_state, "configuration_available");
    assert.equal(codex?.connection_state, "not_verified");
    assert.equal(codex?.install_policy, "manual_user_action_required");
    assert.equal(codex?.fallback_attempted, false);
    assert.equal(codex?.mcp_server.command, "node");
    assert.deepEqual(codex?.mcp_server.args, [
      "/opt/geeagent/dist/native-runtime/index.mjs",
      "agent-gateway-mcp",
      "--client",
      "codex",
      "--config-dir",
      configDir,
    ]);
    assert.equal(codex?.mcp_server.args.includes("codex-mcp"), false);
    assert.match(codex?.config_snippets[0]?.body ?? "", /"--client",\n\s+"codex"/);

    const claude = result.clients[1];
    assert.equal(claude?.client_id, "claude_code");
    assert.match(
      claude?.config_snippets.find((snippet) => snippet.format === "shell")?.body ?? "",
      /^claude mcp add geeagent -- node \/opt\/geeagent\/dist\/native-runtime\/index\.mjs agent-gateway-mcp --client claude_code --config-dir /,
    );

    const workbuddy = result.clients[2];
    assert.equal(workbuddy?.client_id, "workbuddy");
    assert.match(workbuddy?.config_snippets[0]?.body ?? "", /"workbuddy"/);
  });

  it("applies per-client capability export policy with Codex compatibility", async () => {
    const root = await mkdtemp(join(tmpdir(), "geeagent-agent-gateway-"));
    await writeGearManifest(root, "gateway.safe", gatewayFixtureManifest());

    const codexRaw = await handleNativeRuntimeCommand("agent-gateway-search-capabilities", [
      JSON.stringify({ gear_roots: [root], client: "codex", detail: "schema" }),
    ]);
    const codex = JSON.parse(codexRaw) as {
      client: string;
      capabilities: Array<{
        capability_ref: string;
        export_policy_source: string;
        input_schema?: unknown;
      }>;
    };
    assert.equal(codex.client, "codex");
    assert.deepEqual(codex.capabilities.map((capability) => capability.capability_ref), [
      "gateway.safe/codex.query",
      "gateway.safe/shared.status",
    ]);
    assert.equal(codex.capabilities[0]?.export_policy_source, "codex_compat");
    assert.equal(codex.capabilities[1]?.export_policy_source, "agent_gateway");
    assert.deepEqual(codex.capabilities[0]?.input_schema, {
      type: "object",
      required: ["key"],
      properties: {
        key: { type: "string" },
      },
    });

    const claudeRaw = await handleNativeRuntimeCommand("agent-gateway-search-capabilities", [
      JSON.stringify({ gear_roots: [root], client: "claude_code" }),
    ]);
    const claude = JSON.parse(claudeRaw) as {
      client: string;
      capabilities: Array<{ capability_ref: string; export_policy_source: string }>;
    };
    assert.equal(claude.client, "claude_code");
    assert.deepEqual(claude.capabilities.map((capability) => capability.capability_ref), [
      "gateway.safe/claude.query",
      "gateway.safe/codex.query",
      "gateway.safe/shared.status",
    ]);
    assert.equal(
      claude.capabilities.find((capability) => capability.capability_ref === "gateway.safe/codex.query")
        ?.export_policy_source,
      "codex_compat",
    );
    assert.equal(
      claude.capabilities.find((capability) => capability.capability_ref === "gateway.safe/claude.query")
        ?.export_policy_source,
      "agent_gateway",
    );

    const describedRaw = await handleNativeRuntimeCommand("agent-gateway-describe-capability", [
      JSON.stringify({
        gear_roots: [root],
        client: "claude_code",
        capability_ref: "gateway.safe/claude.query",
      }),
    ]);
    const described = JSON.parse(describedRaw) as {
      status: string;
      capability: { capability_ref: string; permissions?: string[] };
    };
    assert.equal(described.status, "success");
    assert.equal(described.capability.capability_ref, "gateway.safe/claude.query");
    assert.deepEqual(described.capability.permissions, ["fixture.read"]);

    const workbuddyRaw = await handleNativeRuntimeCommand("agent-gateway-search-capabilities", [
      JSON.stringify({ gear_roots: [root], client: "workbuddy", query: "Codex" }),
    ]);
    const workbuddy = JSON.parse(workbuddyRaw) as {
      client: string;
      capabilities: Array<{ capability_ref: string; export_policy_source: string }>;
    };
    assert.equal(workbuddy.client, "workbuddy");
    assert.deepEqual(workbuddy.capabilities, [
      {
        capability_ref: "gateway.safe/codex.query",
        gear_id: "gateway.safe",
        gear_name: "Gateway Safe Gear",
        capability_id: "codex.query",
        title: "Codex query",
        description: "Read a value through the Codex compatibility policy.",
        examples: ["Read Codex value"],
        client: "workbuddy",
        export_policy_source: "codex_compat",
        risk: "low",
        requires_approval: false,
        side_effect: "read_only",
        skill_hint: "Use for Codex compatibility checks.",
      },
    ]);
  });

  it("serves the neutral MCP contract and queues runs through the existing host-drained store", async () => {
    const root = await mkdtemp(join(tmpdir(), "geeagent-agent-gateway-"));
    const configDir = await mkdtemp(join(tmpdir(), "geeagent-agent-gateway-config-"));
    await writeGearManifest(root, "gateway.safe", gatewayFixtureManifest());

    const initialized = (await handleAgentGatewayMcpRequest(
      {
        jsonrpc: "2.0",
        id: "init",
        method: "initialize",
        params: {},
      },
      { configDir, client: "claude_code" },
    )) as JsonRpcResponse;
    assert.equal(initialized.error, undefined);
    assert.equal(
      initialized.result?.serverInfo &&
        (initialized.result.serverInfo as { name: string }).name,
      "geeagent-gateway",
    );

    const tools = (await handleAgentGatewayMcpRequest(
      {
        jsonrpc: "2.0",
        id: "tools",
        method: "tools/list",
        params: {},
      },
      { configDir, client: "claude_code" },
    )) as JsonRpcResponse;
    const toolNames = ((tools.result?.tools ?? []) as Array<{ name: string }>).map(
      (tool) => tool.name,
    );
    assert.deepEqual(toolNames, [
      "gee_status",
      "gee_search_capabilities",
      "gee_describe_capability",
      "gee_run_capability",
      "gee_get_run",
      "gee_prepare_gear",
      "gee_open_surface",
    ]);

    const runResponse = (await handleAgentGatewayMcpRequest(
      {
        jsonrpc: "2.0",
        id: "run",
        method: "tools/call",
        params: {
          name: "gee_run_capability",
          arguments: {
            gear_roots: [root],
            capability_ref: " gateway.safe/claude.query ",
            args: { key: "fixture" },
            wait_ms: 0,
          },
        },
      },
      { configDir, client: "claude_code" },
    )) as JsonRpcResponse;
    const runPayload = parseToolText(runResponse);
    assert.equal(runPayload.status, "pending");
    assert.equal(runPayload.standard, "gee.agent_gateway.v0.1");
    assert.equal(typeof runPayload.run_id, "string");
    assert.equal(runPayload.fallback_attempted, false);

    const store = JSON.parse(
      await readFile(join(configDir, "runtime-store.json"), "utf8"),
    ) as {
      external_invocations?: Array<{
        external_invocation_id: string;
        capability_ref: string;
        tool: string;
        status: string;
        gear_id: string;
        capability_id: string;
        args: Record<string, unknown>;
        caller: Record<string, unknown>;
      }>;
    };
    assert.equal(store.external_invocations?.[0]?.external_invocation_id, runPayload.run_id);
    assert.equal(store.external_invocations?.[0]?.capability_ref, "gateway.safe/claude.query");
    assert.equal(store.external_invocations?.[0]?.tool, "gee_invoke_capability");
    assert.equal(store.external_invocations?.[0]?.status, "pending");
    assert.equal(store.external_invocations?.[0]?.gear_id, "gateway.safe");
    assert.equal(store.external_invocations?.[0]?.capability_id, "claude.query");
    assert.deepEqual(store.external_invocations?.[0]?.args, { key: "fixture" });
    assert.equal(store.external_invocations?.[0]?.caller.client, "claude_code");

    const prepareResponse = (await handleAgentGatewayMcpRequest(
      {
        jsonrpc: "2.0",
        id: "prepare",
        method: "tools/call",
        params: {
          name: "gee_prepare_gear",
          arguments: {
            gear_id: "gateway.safe",
            action: "prepare",
          },
        },
      },
      { configDir, client: "claude_code" },
    )) as JsonRpcResponse;
    const preparePayload = parseToolText(prepareResponse);
    assert.equal(preparePayload.status, "blocked");
    assert.equal(preparePayload.code, "gee.agent_gateway.prepare_requires_geeagentmac");
    assert.equal(preparePayload.fallback_attempted, false);

    const openResponse = (await handleAgentGatewayMcpRequest(
      {
        jsonrpc: "2.0",
        id: "open",
        method: "tools/call",
        params: {
          name: "gee_open_surface",
          arguments: {
            gear_roots: [root],
            gear_id: "gateway.safe",
            wait_ms: 0,
          },
        },
      },
      { configDir, client: "claude_code" },
    )) as JsonRpcResponse;
    const openPayload = parseToolText(openResponse);
    assert.equal(openPayload.status, "pending");
    assert.equal(openPayload.tool, "gee_open_surface");
  });

  it("uses the MCP server client identity instead of caller-supplied client claims", async () => {
    const root = await mkdtemp(join(tmpdir(), "geeagent-agent-gateway-"));
    const configDir = await mkdtemp(join(tmpdir(), "geeagent-agent-gateway-config-"));
    await writeGearManifest(root, "gateway.safe", gatewayFixtureManifest());

    const spoofedRunResponse = (await handleAgentGatewayMcpRequest(
      {
        jsonrpc: "2.0",
        id: "spoofed-run",
        method: "tools/call",
        params: {
          name: "gee_run_capability",
          arguments: {
            gear_roots: [root],
            capability_ref: "gateway.safe/claude.query",
            client: "claude_code",
            caller: {
              client: "claude_code",
            },
            args: { key: "fixture" },
            wait_ms: 0,
          },
        },
      },
      { configDir, client: "codex" },
    )) as JsonRpcResponse;
    const spoofedPayload = parseToolText(spoofedRunResponse);
    assert.equal(spoofedPayload.status, "failed");
    assert.equal(spoofedPayload.code, "gee.agent_gateway.capability_not_found");
    assert.equal(spoofedPayload.client, "codex");
    assert.equal(spoofedPayload.fallback_attempted, false);

    const officialRunResponse = (await handleAgentGatewayMcpRequest(
      {
        jsonrpc: "2.0",
        id: "official-run",
        method: "tools/call",
        params: {
          name: "gee_run_capability",
          arguments: {
            gear_roots: [root],
            capability_ref: "gateway.safe/claude.query",
            caller: {
              client: "codex",
              thread_id: "thread-1",
            },
            args: { key: "fixture" },
            wait_ms: 0,
          },
        },
      },
      { configDir, client: "claude_code" },
    )) as JsonRpcResponse;
    const officialPayload = parseToolText(officialRunResponse);
    assert.equal(officialPayload.status, "pending");

    const store = JSON.parse(
      await readFile(join(configDir, "runtime-store.json"), "utf8"),
    ) as {
      external_invocations?: Array<{
        caller: Record<string, unknown>;
      }>;
    };
    assert.equal(store.external_invocations?.[0]?.caller.client, "claude_code");
    assert.equal(store.external_invocations?.[0]?.caller.thread_id, "thread-1");
  });

  it("uses the MCP server config directory instead of caller-supplied config claims", async () => {
    const root = await mkdtemp(join(tmpdir(), "geeagent-agent-gateway-"));
    const configDir = await mkdtemp(join(tmpdir(), "geeagent-agent-gateway-config-"));
    const spoofedConfigDir = await mkdtemp(join(tmpdir(), "geeagent-agent-gateway-spoofed-config-"));
    await writeGearManifest(root, "gateway.safe", gatewayFixtureManifest());

    const response = (await handleAgentGatewayMcpRequest(
      {
        jsonrpc: "2.0",
        id: "config-dir-run",
        method: "tools/call",
        params: {
          name: "gee_run_capability",
          arguments: {
            gear_roots: [root],
            capability_ref: "gateway.safe/claude.query",
            config_dir: spoofedConfigDir,
            args: { key: "fixture" },
            wait_ms: 0,
          },
        },
      },
      { configDir, client: "claude_code" },
    )) as JsonRpcResponse;
    const payload = parseToolText(response);
    assert.equal(payload.status, "pending");

    const store = JSON.parse(
      await readFile(join(configDir, "runtime-store.json"), "utf8"),
    ) as {
      external_invocations?: Array<{
        external_invocation_id: string;
      }>;
    };
    assert.equal(store.external_invocations?.[0]?.external_invocation_id, payload.run_id);
    await assert.rejects(
      readFile(join(spoofedConfigDir, "runtime-store.json"), "utf8"),
      /ENOENT/,
    );
  });

  it("does not queue surface opens for gears hidden from the MCP client", async () => {
    const root = await mkdtemp(join(tmpdir(), "geeagent-agent-gateway-"));
    const configDir = await mkdtemp(join(tmpdir(), "geeagent-agent-gateway-config-"));
    await writeGearManifest(root, "gateway.claude.only", claudeOnlyFixtureManifest());

    const response = (await handleAgentGatewayMcpRequest(
      {
        jsonrpc: "2.0",
        id: "hidden-open",
        method: "tools/call",
        params: {
          name: "gee_open_surface",
          arguments: {
            gear_roots: [root],
            gear_id: "gateway.claude.only",
            wait_ms: 0,
          },
        },
      },
      { configDir, client: "codex" },
    )) as JsonRpcResponse;
    const payload = parseToolText(response);
    assert.equal(payload.status, "failed");
    assert.equal(payload.code, "gee.agent_gateway.surface_not_exported");
    assert.equal(payload.client, "codex");
    assert.equal(payload.fallback_attempted, false);
    await assert.rejects(
      readFile(join(configDir, "runtime-store.json"), "utf8"),
      /ENOENT/,
    );
  });
});
