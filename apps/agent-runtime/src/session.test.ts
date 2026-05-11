import assert from "node:assert/strict";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";

import {
  unstable_v2_createSession,
  type SDKMessage,
  type SDKSession,
} from "@anthropic-ai/claude-agent-sdk";

import { runtimeProjectPath } from "./native-runtime/paths.js";
import { buildRuntimeRunPlan } from "./native-runtime/turns/planning.js";
import type { RuntimeEvent } from "./protocol.js";
import {
  CHAT_ONLY_SDK_AUTO_APPROVE_TOOLS,
  CHAT_ONLY_SDK_AVAILABLE_TOOLS,
  DEFAULT_SDK_AVAILABLE_TOOLS,
  DEFAULT_SDK_AUTO_APPROVE_TOOLS,
  DEFAULT_SDK_DISALLOWED_TOOLS,
} from "./sdk-tool-policy.js";
import { ClaudeRuntimeSession, __sessionTestHooks } from "./session.js";

function createFakeSdkSession(
  options: { failFirstSend?: boolean; failFirstStream?: boolean } = {},
): {
  capturedOptions: unknown[];
  sentPayloads: unknown[];
  sentMessages: string[];
  sdkSessionFactory: typeof unstable_v2_createSession;
} {
  const capturedOptions: unknown[] = [];
  const sentPayloads: unknown[] = [];
  const sentMessages: string[] = [];
  let sendCount = 0;
  let streamCount = 0;
  const sdkSession = {
    async send(message: unknown) {
      sendCount += 1;
      sentPayloads.push(message);
      sentMessages.push(typeof message === "string" ? message : JSON.stringify(message));
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
    sentPayloads,
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
    assert.doesNotMatch(prompt, /Gee host controls are available through the host bridge/);
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

  it("keeps attachments with the queued SDK user payload", async () => {
    const { sdkSessionFactory, sentPayloads } = createFakeSdkSession();
    const { events, session } = createRuntimeSession(sdkSessionFactory);

    session.send({
      text: "Compare the screenshot with this folder.",
      attachments: [
        {
          attachment_id: "att_dir_1",
          kind: "directory",
          source: "workspace_chat",
          display_name: "fixture",
          original_path: "/tmp/fixture",
          resolved_path: "/tmp/fixture",
          created_at: "2026-05-07T00:00:00.000Z",
          status: "ready",
          access: {
            scope: "run",
            mode: "read",
            root: "/tmp/fixture",
          },
          fallback_attempted: false,
        },
      ],
    });
    await waitForRuntimeEvent(events, "session.result");

    const payload = sentPayloads[0] as {
      text?: string;
      attachments?: Array<{ attachment_id?: string }>;
    };
    assert.match(payload.text ?? "", /\[GeeAgent Turn\]\nCompare the screenshot/);
    assert.equal(payload.attachments?.[0]?.attachment_id, "att_dir_1");
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

  it("mentions host bridge controls only when the bridge is actually enabled", () => {
    const prompt = __sessionTestHooks.buildSystemPrompt("", {
      capabilities: ["bash", "gee_host_bridge"],
    });

    assert.match(prompt, /Host capabilities: bash, gee_host_bridge/);
    assert.match(prompt, /Gee host controls are available through the host bridge/);
    assert.match(prompt, /For requests that match an installed Gear or built-in app/);
    assert.match(prompt, /Do not inspect GeeAgent source files/);
    assert.match(prompt, /mcp__gee__native_app_control/);
    assert.match(prompt, /opening Codex Desktop, creating a new Codex chat/);
    assert.match(prompt, /Do not add delegation notes/);
    assert.match(prompt, /browser\/plugin instructions/);
    assert.match(prompt, /WeChat article and album URLs/);
    assert.match(prompt, /WeSpy Reader Gear/);
    assert.match(prompt, /Use the Gear bridge first/);
    assert.match(prompt, /report the missing Gee host bridge as a runtime failure/);
    assert.match(prompt, /Known Gee Gear required args/);
    assert.match(prompt, /media\.library\/media\.import_files: args\.paths/);
    assert.match(prompt, /Never call `gee\.gear\.invoke` with guessed or empty required arguments/);
    assert.match(prompt, /directory input attachments/);
    assert.match(prompt, /mcp__gee__files_directory_snapshot/);
    assert.match(prompt, /Do not look for a dedicated screenshot-directory comparison tool/);
    assert.doesNotMatch(prompt, /<gee-host-actions>/);
  });

  it("builds SDK image content blocks for ready image attachments", async () => {
    const dir = await mkdtemp(join(tmpdir(), "geeagent-session-image-"));
    const imagePath = join(dir, "shot.png");
    const imageBytes = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a]);
    await writeFile(imagePath, imageBytes);

    const message = await __sessionTestHooks.sdkUserMessage({
      text: "Describe the screenshot.",
      attachments: [
        {
          attachment_id: "att_img_1",
          kind: "image",
          source: "workspace_chat",
          display_name: "shot.png",
          original_path: imagePath,
          resolved_path: imagePath,
          mime_type: "image/png",
          size_bytes: imageBytes.byteLength,
          created_at: "2026-05-07T00:00:00.000Z",
          status: "ready",
          access: {
            scope: "run",
            mode: "read",
            root: dir,
          },
          fallback_attempted: false,
        },
      ],
    });

    const content = message.message.content as Array<{
      type: string;
      text?: string;
      source?: { type?: string; media_type?: string; data?: string };
    }>;
    assert.equal(content[0]?.type, "text");
    assert.equal(content[0]?.text, "Describe the screenshot.");
    assert.equal(content[1]?.type, "image");
    assert.equal(content[1]?.source?.type, "base64");
    assert.equal(content[1]?.source?.media_type, "image/png");
    assert.equal(content[1]?.source?.data, imageBytes.toString("base64"));
  });

  it("rejects ready image attachments that escape their scoped root", async () => {
    const root = await mkdtemp(join(tmpdir(), "geeagent-session-image-root-"));
    const outside = await mkdtemp(join(tmpdir(), "geeagent-session-image-outside-"));
    const imagePath = join(outside, "shot.png");
    await writeFile(imagePath, Buffer.from([0x89, 0x50, 0x4e, 0x47]));

    await assert.rejects(
      () =>
        __sessionTestHooks.sdkUserMessage({
          text: "Describe the screenshot.",
          attachments: [
            {
              attachment_id: "att_img_escape",
              kind: "image",
              source: "workspace_chat",
              display_name: "shot.png",
              original_path: imagePath,
              resolved_path: imagePath,
              mime_type: "image/png",
              created_at: "2026-05-07T00:00:00.000Z",
              status: "ready",
              access: {
                scope: "run",
                mode: "read",
                root,
              },
              fallback_attempted: false,
            },
          ],
        }),
      /escapes scoped attachment root/,
    );
  });

  it("runs directory snapshots only against workspace or current directory attachments", async () => {
    const workspace = await mkdtemp(join(tmpdir(), "geeagent-session-workspace-"));
    const attachedDir = join(workspace, "attached");
    await mkdir(attachedDir);
    await writeFile(join(attachedDir, "alpha.txt"), "alpha");

    const result = await __sessionTestHooks.filesDirectorySnapshotToolResult(
      { attachment_id: "att_dir_1" },
      {
        cwd: workspace,
        attachments: [
          {
            attachment_id: "att_dir_1",
            kind: "directory",
            source: "workspace_chat",
            display_name: "attached",
            original_path: attachedDir,
            resolved_path: attachedDir,
            created_at: "2026-05-07T00:00:00.000Z",
            status: "ready",
            access: {
              scope: "run",
              mode: "read",
              root: attachedDir,
            },
            limits: {
              max_depth: 2,
              max_entries: 20,
            },
            fallback_attempted: false,
          },
        ],
      },
    );
    const payload = JSON.parse(result.content[0]?.text ?? "{}") as {
      status?: string;
      entries?: Array<{ relative_path?: string }>;
      fallback_attempted?: boolean;
    };
    assert.equal(result.isError, false);
    assert.equal(payload.status, "succeeded");
    assert.equal(payload.entries?.some((entry) => entry.relative_path === "alpha.txt"), true);
    assert.equal(payload.fallback_attempted, false);

    const outside = await mkdtemp(join(tmpdir(), "geeagent-session-outside-dir-"));
    const denied = await __sessionTestHooks.filesDirectorySnapshotToolResult(
      { path: outside },
      { cwd: workspace, attachments: [] },
    );
    const deniedPayload = JSON.parse(denied.content[0]?.text ?? "{}") as {
      status?: string;
      code?: string;
      fallback_attempted?: boolean;
    };
    assert.equal(denied.isError, true);
    assert.equal(deniedPayload.status, "failed");
    assert.equal(deniedPayload.code, "files.directory_snapshot_scope_missing");
    assert.equal(deniedPayload.fallback_attempted, false);
  });

  it("supports screenshot plus folder comparison without a dedicated compare tool", async () => {
    const workspace = await mkdtemp(join(tmpdir(), "geeagent-session-compare-"));
    const imagePath = join(workspace, "tree.png");
    const folderPath = join(workspace, "actual");
    const imageBytes = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a]);
    await mkdir(folderPath);
    await writeFile(imagePath, imageBytes);
    await writeFile(join(folderPath, "README.md"), "# Actual\n");

    const attachments = [
      {
        attachment_id: "att_screenshot_tree",
        kind: "image" as const,
        source: "workspace_chat" as const,
        display_name: "tree.png",
        original_path: imagePath,
        resolved_path: imagePath,
        mime_type: "image/png",
        created_at: "2026-05-07T00:00:00.000Z",
        status: "ready" as const,
        access: {
          scope: "run" as const,
          mode: "read" as const,
          root: workspace,
        },
        fallback_attempted: false as const,
      },
      {
        attachment_id: "att_actual_dir",
        kind: "directory" as const,
        source: "workspace_chat" as const,
        display_name: "actual",
        original_path: folderPath,
        resolved_path: folderPath,
        created_at: "2026-05-07T00:00:00.000Z",
        status: "ready" as const,
        access: {
          scope: "run" as const,
          mode: "read" as const,
          root: folderPath,
        },
        limits: {
          max_depth: 2,
          max_entries: 20,
        },
        fallback_attempted: false as const,
      },
    ];

    const message = await __sessionTestHooks.sdkUserMessage({
      text: "Compare the directory tree shown in the screenshot with the referenced folder.",
      attachments,
    });
    const content = message.message.content as Array<{
      type: string;
      source?: { media_type?: string };
    }>;
    assert.equal(content.filter((block) => block.type === "image").length, 1);
    assert.equal(content.find((block) => block.type === "image")?.source?.media_type, "image/png");
    assert.equal(
      DEFAULT_SDK_AVAILABLE_TOOLS.some((toolName) =>
        toolName.toLowerCase().includes("compare"),
      ),
      false,
    );

    const result = await __sessionTestHooks.filesDirectorySnapshotToolResult(
      { attachment_id: "att_actual_dir" },
      { cwd: workspace, attachments },
    );
    const payload = JSON.parse(result.content[0]?.text ?? "{}") as {
      entries?: Array<{ relative_path?: string }>;
    };
    assert.equal(result.isError, false);
    assert.equal(payload.entries?.some((entry) => entry.relative_path === "README.md"), true);
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

  it("normalizes direct MCP Gear invoke argument envelopes", () => {
    const url = "https://x.com/YaReYaRu30Life/status/2049545035176362120?s=20";

    assert.deepEqual(
      __sessionTestHooks.sanitizeToolInput("mcp__gee__gear_invoke", {
        gear_id: "twitter.capture",
        capability_id: "twitter.fetch_tweet",
        arguments: {
          args: { url },
        },
      }),
      {
        gear_id: "twitter.capture",
        capability_id: "twitter.fetch_tweet",
        args: { url },
      },
    );

    assert.deepEqual(
      __sessionTestHooks.sanitizeToolInput("mcp__gee__gear_invoke", {
        gear_id: "twitter.capture",
        capability_id: "twitter.fetch_tweet",
        args: { url },
      }),
      {
        gear_id: "twitter.capture",
        capability_id: "twitter.fetch_tweet",
        args: { url },
      },
    );
  });

  it("recovers deterministic current-stage Gear args from the runtime plan", () => {
    const url = "https://x.com/YaReYaRu30Life/status/2049545035176362120?s=20";
    const plan = buildRuntimeRunPlan(
      `save this tweet to bookmarks ${url} and download its media into the media library gear.`,
      "gear_first",
    );

    assert.ok(plan);
    assert.deepEqual(
      __sessionTestHooks.sanitizeToolInput(
        "mcp__gee__gear_invoke",
        {
          gear_id: "twitter.capture",
          capability_id: "twitter.fetch_tweet",
          args: {},
        },
        plan,
      ),
      {
        gear_id: "twitter.capture",
        capability_id: "twitter.fetch_tweet",
        args: { url },
      },
    );
  });

  it("injects a host-action idempotency key for Todo creates", () => {
    assert.deepEqual(
      __sessionTestHooks.withHostActionIdempotency(
        "host_action_todo_create_abc123",
        "gee.gear.invoke",
        {
          gear_id: "todo.manager",
          capability_id: "todo.create",
          args: {
            title: "Review Todo reminders",
          },
        },
      ),
      {
        gear_id: "todo.manager",
        capability_id: "todo.create",
        args: {
          title: "Review Todo reminders",
          idempotency_key: "host_action_todo_create_abc123",
        },
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
    assert.ok(DEFAULT_SDK_AVAILABLE_TOOLS.includes("mcp__gee__files_directory_snapshot"));
    assert.ok(DEFAULT_SDK_AVAILABLE_TOOLS.includes("mcp__gee__gear_invoke"));
    assert.ok(DEFAULT_SDK_AVAILABLE_TOOLS.includes("mcp__gee__native_app_control"));
    assert.equal(DEFAULT_SDK_AVAILABLE_TOOLS.includes("RemoteTrigger"), false);
  });

  it("keeps the chat-only SDK tool profile empty", () => {
    assert.deepEqual(CHAT_ONLY_SDK_AVAILABLE_TOOLS, []);
    assert.deepEqual(CHAT_ONLY_SDK_AUTO_APPROVE_TOOLS, []);
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
      file_path: "/tmp/geeagent-skills/info-capture/SKILL.md",
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
