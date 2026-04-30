import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  unstable_v2_createSession,
  type SDKMessage,
  type SDKSession,
} from "@anthropic-ai/claude-agent-sdk";

import { runtimeProjectPath } from "./native-runtime/paths.js";
import type { RuntimeEvent } from "./protocol.js";
import {
  DEFAULT_SDK_AVAILABLE_TOOLS,
  DEFAULT_SDK_AUTO_APPROVE_TOOLS,
  DEFAULT_SDK_DISALLOWED_TOOLS,
} from "./sdk-tool-policy.js";
import { ClaudeRuntimeSession, __sessionTestHooks } from "./session.js";

function createFakeSdkSession(
  options: { failFirstSend?: boolean; failFirstStream?: boolean } = {},
): {
  capturedOptions: unknown[];
  sentMessages: string[];
  sdkSessionFactory: typeof unstable_v2_createSession;
} {
  const capturedOptions: unknown[] = [];
  const sentMessages: string[] = [];
  let sendCount = 0;
  let streamCount = 0;
  const sdkSession = {
    async send(message: string) {
      sendCount += 1;
      sentMessages.push(message);
      if (options.failFirstSend && sendCount === 1) {
        throw new Error("synthetic SDK send failure");
      }
    },
    async *stream() {
      streamCount += 1;
      if (options.failFirstStream && streamCount === 1) {
        throw new Error("synthetic SDK stream failure");
      }
      yield {
        type: "result",
        subtype: "success",
        result: "ok",
        duration_ms: 1,
        total_cost_usd: 0,
      } as SDKMessage;
    },
    close() {},
  } as SDKSession;

  return {
    capturedOptions,
    sentMessages,
    sdkSessionFactory: ((sessionOptions: unknown) => {
      capturedOptions.push(sessionOptions);
      return sdkSession;
    }) as typeof unstable_v2_createSession,
  };
}

function createRuntimeSession(
  sdkSessionFactory: typeof unstable_v2_createSession,
  overrides: Partial<ConstructorParameters<typeof ClaudeRuntimeSession>[0]> = {},
): {
  events: RuntimeEvent[];
  session: ClaudeRuntimeSession;
} {
  const events: RuntimeEvent[] = [];
  const session = new ClaudeRuntimeSession(
    {
      sessionId: "session_test",
      cwd: "/tmp/workspace",
      model: "sonnet",
      maxTurns: 8,
      systemPrompt: "persona rules",
      runtimeContext: {
        localTime: "2026-04-28 09:00",
        timezone: "Asia/Singapore",
        surface: "desktop_live",
        cwd: "/tmp/workspace",
        approvalPosture: "host_review",
        capabilities: ["bash", "gee_host_bridge"],
      },
      autoApproveTools: [],
      disallowedTools: [],
      artifactRoot: "/tmp/geeagent-session-test-artifacts",
      gatewayBaseUrl: "http://127.0.0.1:1",
      gatewayApiKey: "test-key",
      sdkSessionFactory,
      ...overrides,
    },
    (event) => events.push(event),
  );
  return { events, session };
}

function restoreEnv(key: string, value: string | undefined): void {
  if (value === undefined) {
    delete process.env[key];
    return;
  }
  process.env[key] = value;
}

async function waitForRuntimeEvent(
  events: RuntimeEvent[],
  type: RuntimeEvent["type"],
  count = 1,
): Promise<RuntimeEvent> {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const matches = events.filter((candidate) => candidate.type === type);
    if (matches.length >= count) {
      return matches[count - 1];
    }
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  throw new Error(`Timed out waiting for runtime event ${type}`);
}

describe("session prompt and tool-result helpers", () => {
  it("builds a GeeAgent runtime prompt with host context and no fake continuation request", () => {
    const prompt = __sessionTestHooks.buildSystemPrompt("persona rules", {
      localTime: "2026-04-25 14:20",
      timezone: "Asia/Singapore",
      surface: "desktop_live",
      cwd: "/tmp/workspace",
      approvalPosture: "host_review",
      capabilities: ["terminal", "files"],
    });

    assert.match(prompt, /GeeAgent/);
    assert.match(prompt, /Local time: 2026-04-25 14:20/);
    assert.match(prompt, /Timezone: Asia\/Singapore/);
    assert.match(prompt, /Surface: desktop_live/);
    assert.match(prompt, /Workspace cwd: \/tmp\/workspace/);
    assert.match(prompt, /Approval posture: host_review/);
    assert.match(prompt, /Host capabilities: terminal, files/);
    assert.doesNotMatch(prompt, /Gee Gear controls are available through the host bridge/);
    assert.match(prompt, /\[GeeAgent Session Prompt\]\npersona rules/);
    assert.match(
      prompt,
      /Do not ask the user to type 'continue' for ordinary operator work\./,
    );
    assert.match(
      prompt,
      /use GeeAgent's Bash tool for read-only checks instead of telling the user to run a terminal command/,
    );
    assert.match(prompt, /Local machine state includes ports, processes, files/);
    assert.match(prompt, /you MUST call an appropriate tool before answering/);
    assert.match(prompt, /Do not use SDK WebSearch or WebFetch/);
    assert.match(prompt, /use Bash with an inspectable command such as curl/);
    assert.match(prompt, /Do not use TodoWrite/);
    assert.match(prompt, /Gee's default specialty and preset task domain are not code development/);
    assert.match(
      prompt,
      /Unless the user explicitly asks you to develop, fix, refactor, or edit code, do not modify local project source code or configuration/,
    );
    assert.match(
      prompt,
      /If a task needs scripting, data processing, inspection helpers, or a temporary automation program, you may write and run that code as an implementation detail/,
    );
  });

  it("injects GeeAgent runtime instructions only for the SDK session bootstrap message", () => {
    const runtimePrompt = __sessionTestHooks.sdkSessionBootstrapPrompt({
      systemPrompt: "persona rules",
      runtimeContext: {
        localTime: "2026-04-28 09:00",
        timezone: "Asia/Singapore",
        surface: "desktop_live",
        cwd: "/tmp/workspace",
        approvalPosture: "host_review",
        capabilities: ["bash", "gee_host_bridge"],
      },
    });
    const firstUserMessage = __sessionTestHooks.runtimeUserMessage(
      "Please continue checking port 8088",
      runtimePrompt,
    );
    const continuationMessage = __sessionTestHooks.runtimeUserMessage(
      "Native host action completed.",
    );

    assert.match(firstUserMessage, /GeeAgent/);
    assert.match(firstUserMessage, /\[GeeAgent Session Prompt\]\npersona rules/);
    assert.match(firstUserMessage, /\[GeeAgent Turn\]\nPlease continue checking port 8088/);
    assert.equal(continuationMessage, "Native host action completed.");
    assert.doesNotMatch(continuationMessage, /GeeAgent/);
    assert.doesNotMatch(continuationMessage, /\[Runtime Context\]/);
    assert.doesNotMatch(continuationMessage, /\[GeeAgent Turn\]/);
  });

  it("sends the runtime bootstrap only once through the SDK session", async () => {
    const { sdkSessionFactory, sentMessages } = createFakeSdkSession();
    const { events, session } = createRuntimeSession(sdkSessionFactory);

    session.send("first turn");
    await waitForRuntimeEvent(events, "session.result");
    session.send("Native host action completed.");
    await waitForRuntimeEvent(events, "session.result", 2);

    assert.equal(sentMessages.length, 2);
    assert.match(sentMessages[0] ?? "", /GeeAgent/);
    assert.match(sentMessages[0] ?? "", /\[GeeAgent Turn\]\nfirst turn/);
    assert.equal(sentMessages[1], "Native host action completed.");
    session.close();
  });

  it("re-promotes queued messages for bootstrap if the first SDK send fails", async () => {
    const { sdkSessionFactory, sentMessages } = createFakeSdkSession({
      failFirstSend: true,
    });
    const { events, session } = createRuntimeSession(sdkSessionFactory);

    session.send("first turn");
    session.send("second turn");
    await waitForRuntimeEvent(events, "session.error");
    await waitForRuntimeEvent(events, "session.result");

    assert.equal(sentMessages.length, 2);
    assert.match(sentMessages[0] ?? "", /\[GeeAgent Turn\]\nfirst turn/);
    assert.match(sentMessages[1] ?? "", /GeeAgent/);
    assert.match(sentMessages[1] ?? "", /\[GeeAgent Turn\]\nsecond turn/);
    session.close();
  });

  it("re-promotes queued messages for bootstrap if the first SDK stream fails before initialization", async () => {
    const { sdkSessionFactory, sentMessages } = createFakeSdkSession({
      failFirstStream: true,
    });
    const { events, session } = createRuntimeSession(sdkSessionFactory);

    session.send("first turn");
    session.send("second turn");
    await waitForRuntimeEvent(events, "session.error");
    await waitForRuntimeEvent(events, "session.result");

    assert.equal(sentMessages.length, 2);
    assert.match(sentMessages[0] ?? "", /\[GeeAgent Turn\]\nfirst turn/);
    assert.match(sentMessages[1] ?? "", /GeeAgent/);
    assert.match(sentMessages[1] ?? "", /\[GeeAgent Turn\]\nsecond turn/);
    session.close();
  });

  it("mentions Gear host bridge controls only when the bridge is actually enabled", () => {
    const prompt = __sessionTestHooks.buildSystemPrompt("", {
      capabilities: ["bash", "gee_host_bridge"],
    });

    assert.match(prompt, /Host capabilities: bash, gee_host_bridge/);
    assert.match(prompt, /Gee Gear controls are available through the host bridge/);
    assert.match(prompt, /For requests that match an installed Gear or built-in app/);
    assert.match(prompt, /Do not inspect GeeAgent source files/);
    assert.match(prompt, /WeChat article and album URLs/);
    assert.match(prompt, /WeSpy Reader Gear/);
    assert.match(prompt, /Use the Gear bridge first/);
    assert.match(prompt, /report the missing Gee host bridge as a runtime failure/);
    assert.match(prompt, /Known Gee Gear required args/);
    assert.match(prompt, /media\.library\/media\.import_files: args\.paths/);
    assert.match(prompt, /Never call `gee\.gear\.invoke` with guessed or empty required arguments/);
    assert.doesNotMatch(prompt, /<gee-host-actions>/);
  });

  it("normalizes non-object tool input into an empty object", () => {
    assert.deepEqual(__sessionTestHooks.normalizeToolInput("pwd"), {});
    assert.deepEqual(__sessionTestHooks.normalizeToolInput(["pwd"]), {});
    assert.deepEqual(__sessionTestHooks.normalizeToolInput({ command: "pwd" }), {
      command: "pwd",
    });
  });

  it("normalizes empty Read page selectors through the shared tool boundary", () => {
    assert.deepEqual(
      __sessionTestHooks.sanitizeToolInput("Read", {
        file_path: "/tmp/example.md",
        limit: 120,
        offset: 1,
        pages: "",
      }),
      {
        file_path: "/tmp/example.md",
        limit: 120,
        offset: 1,
      },
    );
    assert.deepEqual(
      __sessionTestHooks.sanitizeToolInput("Read", {
        file_path: "/tmp/example.pdf",
        pages: "1-3",
      }),
      {
        file_path: "/tmp/example.pdf",
        pages: "1-3",
      },
    );
  });

  it("returns a PreToolUse updatedInput before SDK native tools execute", () => {
    assert.deepEqual(
      __sessionTestHooks.preToolUseBoundaryOutput({
        hook_event_name: "PreToolUse",
        session_id: "session_test",
        transcript_path: "/tmp/transcript.jsonl",
        cwd: "/tmp",
        tool_name: "Read",
        tool_input: {
          file_path: "/tmp/SKILL.md",
          limit: 2500,
          offset: 0,
          pages: "",
        },
        tool_use_id: "call_read",
      }),
      {
        continue: true,
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          updatedInput: {
            file_path: "/tmp/SKILL.md",
            limit: 2500,
            offset: 0,
          },
        },
      },
    );
    assert.equal(
      __sessionTestHooks.preToolUseBoundaryOutput({
        hook_event_name: "PreToolUse",
        session_id: "session_test",
        transcript_path: "/tmp/transcript.jsonl",
        cwd: "/tmp",
        tool_name: "Read",
        tool_input: {
          file_path: "/tmp/doc.pdf",
          pages: "1-3",
        },
        tool_use_id: "call_read_valid",
      }),
      undefined,
    );
  });

  it("summarizes SDK tool result text blocks without losing multi-line output", () => {
    const summary = __sessionTestHooks.summarizeToolResultContent([
      { type: "text", text: "line one" },
      { type: "text", text: "line two" },
    ]);

    assert.equal(summary, "line one\nline two");
  });

  it("removes SDK TodoWrite from GeeAgent's main runtime tool context", () => {
    assert.ok(DEFAULT_SDK_DISALLOWED_TOOLS.includes("TodoWrite"));
    assert.ok(DEFAULT_SDK_DISALLOWED_TOOLS.includes("Skill"));
    assert.ok(DEFAULT_SDK_DISALLOWED_TOOLS.includes("Agent"));
    assert.ok(DEFAULT_SDK_DISALLOWED_TOOLS.includes("Task"));
    assert.ok(DEFAULT_SDK_DISALLOWED_TOOLS.includes("RemoteTrigger"));
    assert.equal(DEFAULT_SDK_DISALLOWED_TOOLS.includes("Bash"), false);
    assert.ok(DEFAULT_SDK_AVAILABLE_TOOLS.includes("Bash"));
    assert.ok(DEFAULT_SDK_AVAILABLE_TOOLS.includes("Read"));
    assert.ok(DEFAULT_SDK_AVAILABLE_TOOLS.includes("mcp__gee__gear_invoke"));
    assert.equal(DEFAULT_SDK_AVAILABLE_TOOLS.includes("RemoteTrigger"), false);
  });

  it("isolates SDK auth state from any local Claude account configuration", () => {
    const originalClaudeOauth = process.env.CLAUDE_CODE_OAUTH_TOKEN;
    const originalClaudeConfigDir = process.env.CLAUDE_CONFIG_DIR;
    const originalAnthropicApiKey = process.env.ANTHROPIC_API_KEY;
    process.env.CLAUDE_CODE_OAUTH_TOKEN = "local-claude-oauth";
    process.env.CLAUDE_CONFIG_DIR = "/tmp/local-claude-config";
    process.env.ANTHROPIC_API_KEY = "local-anthropic-key";

    try {
      const { capturedOptions, sdkSessionFactory } = createFakeSdkSession();
      const { session } = createRuntimeSession(sdkSessionFactory);
      const options = capturedOptions[0] as {
        tools?: string[];
        env?: Record<string, string | undefined>;
      };

      assert.deepEqual(options.tools, DEFAULT_SDK_AVAILABLE_TOOLS);
      assert.equal(options.env?.ANTHROPIC_BASE_URL, "http://127.0.0.1:1");
      assert.equal(options.env?.ANTHROPIC_API_KEY, "test-key");
      assert.equal(options.env?.CLAUDE_AGENT_SDK_CLIENT_APP, "geeagent/agent-runtime");
      assert.match(options.env?.CLAUDE_CONFIG_DIR ?? "", /ClaudeConfig$/);
      assert.equal(options.env?.CLAUDE_CODE_OAUTH_TOKEN, undefined);
      assert.notEqual(options.env?.CLAUDE_CONFIG_DIR, "/tmp/local-claude-config");
      session.close();
    } finally {
      restoreEnv("CLAUDE_CODE_OAUTH_TOKEN", originalClaudeOauth);
      restoreEnv("CLAUDE_CONFIG_DIR", originalClaudeConfigDir);
      restoreEnv("ANTHROPIC_API_KEY", originalAnthropicApiKey);
    }
  });

  it("blocks non-Gee tools before the Gear bridge on Gear-first turns", async () => {
    const { capturedOptions, sdkSessionFactory } = createFakeSdkSession();
    const { session } = createRuntimeSession(sdkSessionFactory, {
      autoApproveTools: [
        "Read",
        "mcp__gee__gear_list_capabilities",
      ],
      toolBoundaryMode: "gear_first",
    });
    const options = capturedOptions[0] as {
      canUseTool: (
        toolName: string,
        input: unknown,
      ) => Promise<{ behavior: "allow" | "deny"; message?: string }>;
    };

    const blocked = await options.canUseTool("Read", {
      file_path: "/Users/davidzhang/Documents/geeskills/info-capture/SKILL.md",
    });
    assert.equal(blocked.behavior, "deny");
    assert.match(blocked.message ?? "", /Gee MCP Gear bridge/);
    assert.match(blocked.message ?? "", /fallback probing/);

    const allowed = await options.canUseTool("mcp__gee__gear_list_capabilities", {
      detail: "summary",
    });
    assert.equal(allowed.behavior, "allow");
    session.close();
  });

  it("validates Gear capability args before a host action has to run", () => {
    const contracts = __sessionTestHooks.gearCapabilityContracts();
    const wespyContract = contracts.find(
      (contract) =>
        contract.gear_id === "wespy.reader" &&
        contract.capability_id === "wespy.fetch_article",
    );
    assert.equal(wespyContract?.provider, "gear");
    assert.equal(wespyContract?.resumability, "same_run");
    assert.equal(wespyContract?.permission_policy, "gear_host");
    assert.deepEqual(wespyContract?.required_args[0]?.aliases, ["url", "article_url"]);
    assert.equal(JSON.stringify(contracts).includes("function"), false);
    assert.deepEqual(
      __sessionTestHooks.validateGearCapabilityArgs(
        "wespy.reader",
        "wespy.fetch_article",
        {},
      ),
      {
        ok: false,
        code: "gear.args.url",
        field: "url",
        expected: "required string `url` is missing",
        message:
          "required string `url` is missing for wespy.reader wespy.fetch_article.",
      },
    );
    assert.deepEqual(
      __sessionTestHooks.validateGearCapabilityArgs(
        "wespy.reader",
        "wespy.fetch_article",
        { url: "https://mp.weixin.qq.com/s/demo" },
      ),
      { ok: true },
    );
  });

  it("routes web lookup away from SDK web tools and through inspectable host paths", () => {
    assert.equal(DEFAULT_SDK_AUTO_APPROVE_TOOLS.includes("WebSearch"), false);
    assert.equal(DEFAULT_SDK_AUTO_APPROVE_TOOLS.includes("WebFetch"), false);
    assert.ok(DEFAULT_SDK_DISALLOWED_TOOLS.includes("WebSearch"));
    assert.ok(DEFAULT_SDK_DISALLOWED_TOOLS.includes("WebFetch"));
    assert.equal(DEFAULT_SDK_AUTO_APPROVE_TOOLS.includes("Bash"), false);
  });

  it("resolves the runtime project path from explicit host context without reading cwd", () => {
    const originalProjectPath = process.env.GEEAGENT_RUNTIME_PROJECT_PATH;
    const originalCwd = process.cwd;
    process.env.GEEAGENT_RUNTIME_PROJECT_PATH = "/tmp/geeagent-project";
    Object.defineProperty(process, "cwd", {
      configurable: true,
      value: () => {
        throw new Error("process.cwd should not be read when the host project path is explicit");
      },
    });
    try {
      assert.equal(runtimeProjectPath(), "/tmp/geeagent-project");
    } finally {
      Object.defineProperty(process, "cwd", {
        configurable: true,
        value: originalCwd,
      });
      if (originalProjectPath === undefined) {
        delete process.env.GEEAGENT_RUNTIME_PROJECT_PATH;
      } else {
        process.env.GEEAGENT_RUNTIME_PROJECT_PATH = originalProjectPath;
      }
    }
  });
});
