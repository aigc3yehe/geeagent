import assert from "node:assert/strict";
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { mkdir, mkdtemp, readFile, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import readline from "node:readline";
import { describe, it } from "node:test";

import { handleNativeRuntimeCommand } from "./native-runtime/commands.js";
import { __sdkTurnRunnerTestHooks } from "./native-runtime/sdk-turn-runner.js";
import {
  sdkRuntimeBashScope,
  terminalAccessDecisionForScope,
} from "./native-runtime/store/terminal-permissions.js";

type ServerEnvelope = {
  id: string;
  ok: boolean;
  output?: string;
  error?: string;
};

async function tempConfigDir(): Promise<string> {
  return mkdtemp(join(tmpdir(), "geeagent-native-runtime-"));
}

function send(
  child: ChildProcessWithoutNullStreams,
  request: Record<string, unknown>,
): void {
  child.stdin.write(`${JSON.stringify(request)}\n`);
}

describe("native runtime command modules", () => {
  it("creates, activates, and deletes conversations through a small TS store", async () => {
    const configDir = await tempConfigDir();
    const firstRaw = await handleNativeRuntimeCommand("snapshot", [], { configDir });
    const first = JSON.parse(firstRaw);
    assert.equal(first.active_conversation.conversation_id, "conv_01");
    assert.equal(first.active_agent_profile.id, "gee");

    const createdRaw = await handleNativeRuntimeCommand("create-conversation", [], {
      configDir,
    });
    const created = JSON.parse(createdRaw);
    assert.equal(created.active_conversation.conversation_id, "conv_02");
    assert.equal(created.conversations.length, 2);

    const activatedRaw = await handleNativeRuntimeCommand(
      "set-active-conversation",
      ["conv_01"],
      { configDir },
    );
    const activated = JSON.parse(activatedRaw);
    assert.equal(activated.active_conversation.conversation_id, "conv_01");

    const deletedRaw = await handleNativeRuntimeCommand(
      "delete-conversation",
      ["conv_01"],
      { configDir },
    );
    const deleted = JSON.parse(deletedRaw);
    assert.equal(deleted.active_conversation.conversation_id, "conv_02");
  });

  it("persists highest authorization in the same shape Swift already reads", async () => {
    const configDir = await tempConfigDir();
    const raw = await handleNativeRuntimeCommand(
      "set-highest-authorization",
      ["true"],
      { configDir },
    );
    const snapshot = JSON.parse(raw);
    assert.equal(snapshot.security_preferences.highest_authorization_enabled, true);

    const saved = JSON.parse(
      await readFile(join(configDir, "runtime-security.json"), "utf8"),
    );
    assert.equal(saved.highest_authorization_enabled, true);
  });

  it("keeps the first-party Gee persona on local Live2D when assets exist", async () => {
    const configDir = await tempConfigDir();
    const live2DRoot = join(configDir, "Personas", "gee", "live2d", "bundle");
    await mkdir(live2DRoot, { recursive: true });
    await writeFile(join(live2DRoot, "Gee.model3.json"), "{}", "utf8");

    const raw = await handleNativeRuntimeCommand("snapshot", [], { configDir });
    const snapshot = JSON.parse(raw);

    assert.equal(snapshot.active_agent_profile.id, "gee");
    assert.equal(snapshot.active_agent_profile.appearance.kind, "live2d");
    assert.equal(
      snapshot.active_agent_profile.appearance.bundle_path,
      join(live2DRoot, "Gee.model3.json"),
    );
  });

  it("projects and deletes historical terminal permission rule ids", async () => {
    const configDir = await tempConfigDir();
    await writeFile(
      join(configDir, "terminal-access.json"),
      JSON.stringify(
        {
          rules: [
            {
              scope: {
                kind: "sdk_bridge_bash",
                command: "top -l 1 -o cpu -n 10 | head -n 25",
              },
              decision: "allow",
              label: "top -l 1 -o cpu -n 10 | head -n 25",
              updated_at: "2026-04-24T13:34:15.411948+00:00",
            },
          ],
        },
        null,
        2,
      ),
    );

    const raw = await handleNativeRuntimeCommand("snapshot", [], { configDir });
    const snapshot = JSON.parse(raw);
    assert.equal(
      snapshot.terminal_access_rules[0].rule_id,
      "terminal_access_7fe746408996f0a7",
    );
    assert.equal(
      await terminalAccessDecisionForScope(
        configDir,
        sdkRuntimeBashScope("top -l 1 -o cpu -n 10 | head -n 25"),
      ),
      "allow",
    );

    const deletedRaw = await handleNativeRuntimeCommand(
      "delete-terminal-access-rule",
      ["terminal_access_7fe746408996f0a7"],
      { configDir },
    );
    const deleted = JSON.parse(deletedRaw);
    assert.deepEqual(deleted.terminal_access_rules, []);
  });

  it("installs, activates, reloads, and deletes agent definition workspaces", async () => {
    const configDir = await tempConfigDir();
    const packRoot = fileURLToPath(
      new URL("../../../examples/agent-packs/companion-sora", import.meta.url),
    );

    const installedRaw = await handleNativeRuntimeCommand(
      "install-agent-pack",
      [packRoot],
      { configDir },
    );
    const installed = JSON.parse(installedRaw);
    assert.ok(
      installed.agent_profiles.some(
        (profile: { id: string }) => profile.id === "companion-sora",
      ),
    );

    const activatedRaw = await handleNativeRuntimeCommand(
      "set-active-agent-profile",
      ["companion-sora"],
      { configDir },
    );
    const activated = JSON.parse(activatedRaw);
    assert.equal(activated.active_agent_profile.id, "companion-sora");

    await writeFile(
      join(configDir, "Personas", "companion-sora", "soul.md"),
      "Updated Sora soul.",
      "utf8",
    );
    await handleNativeRuntimeCommand("reload-agent-profile", ["companion-sora"], {
      configDir,
    });
    const runtimeProfile = JSON.parse(
      await readFile(join(configDir, "agents", "companion-sora.json"), "utf8"),
    );
    assert.match(runtimeProfile.personality_prompt, /Updated Sora soul/);

    const deletedRaw = await handleNativeRuntimeCommand(
      "delete-agent-profile",
      ["companion-sora"],
      { configDir },
    );
    const deleted = JSON.parse(deletedRaw);
    assert.equal(deleted.active_agent_profile.id, "gee");
    await assert.rejects(stat(join(configDir, "agents", "companion-sora.json")));
    await assert.rejects(stat(join(configDir, "Personas", "companion-sora")));
  });

  it("normalizes optional persona visuals with priority and global background", async () => {
    const configDir = await tempConfigDir();
    const packRoot = join(configDir, "visual-pack");
    await mkdir(join(packRoot, "appearance", "model"), { recursive: true });
    await writeFile(
      join(packRoot, "agent.json"),
      JSON.stringify(
        {
          definition_version: "2",
          id: "visual-priority",
          name: "Visual Priority",
          tagline: "Checks persona visual priority.",
          identity_prompt_path: "identity-prompt.md",
          soul_path: "soul.md",
          playbook_path: "playbook.md",
          appearance: {
            image: { asset_path: "appearance/hero.png" },
            video: { asset_path: "appearance/loop.mp4" },
            live2d: { bundle_path: "appearance/model/Character.model3.json" },
            global_background: {
              image_asset_path: "appearance/background.png",
              video_asset_path: "appearance/background.mp4",
            },
          },
          source: "module_pack",
          version: "1.0.0",
        },
        null,
        2,
      ),
      "utf8",
    );
    await writeFile(join(packRoot, "identity-prompt.md"), "Identity.", "utf8");
    await writeFile(join(packRoot, "soul.md"), "Soul.", "utf8");
    await writeFile(join(packRoot, "playbook.md"), "Playbook.", "utf8");
    await writeFile(join(packRoot, "appearance", "hero.png"), "", "utf8");
    await writeFile(join(packRoot, "appearance", "loop.mp4"), "", "utf8");
    await writeFile(join(packRoot, "appearance", "background.png"), "", "utf8");
    await writeFile(join(packRoot, "appearance", "background.mp4"), "", "utf8");
    await writeFile(join(packRoot, "appearance", "model", "Character.model3.json"), "{}", "utf8");

    await handleNativeRuntimeCommand("install-agent-pack", [packRoot], { configDir });
    const runtimeProfile = JSON.parse(
      await readFile(join(configDir, "agents", "visual-priority.json"), "utf8"),
    );

    assert.equal(runtimeProfile.appearance.kind, "live2d");
    assert.equal(
      runtimeProfile.appearance.bundle_path,
      join(configDir, "Personas", "visual-priority", "appearance", "model", "Character.model3.json"),
    );
    assert.equal(
      runtimeProfile.appearance.video_asset_path,
      join(configDir, "Personas", "visual-priority", "appearance", "loop.mp4"),
    );
    assert.equal(
      runtimeProfile.appearance.image_asset_path,
      join(configDir, "Personas", "visual-priority", "appearance", "hero.png"),
    );
    assert.equal(runtimeProfile.appearance.global_background.kind, "video");
    assert.equal(
      runtimeProfile.appearance.global_background.asset_path,
      join(configDir, "Personas", "visual-priority", "appearance", "background.mp4"),
    );
  });

  it("allows agent definition visuals to be omitted", async () => {
    const configDir = await tempConfigDir();
    const packRoot = join(configDir, "headless-pack");
    await mkdir(packRoot, { recursive: true });
    await writeFile(
      join(packRoot, "agent.json"),
      JSON.stringify(
        {
          definition_version: "2",
          id: "headless",
          name: "Headless",
          tagline: "No visual layer.",
          identity_prompt_path: "identity-prompt.md",
          soul_path: "soul.md",
          playbook_path: "playbook.md",
          source: "module_pack",
          version: "1.0.0",
        },
        null,
        2,
      ),
      "utf8",
    );
    await writeFile(join(packRoot, "identity-prompt.md"), "Identity.", "utf8");
    await writeFile(join(packRoot, "soul.md"), "Soul.", "utf8");
    await writeFile(join(packRoot, "playbook.md"), "Playbook.", "utf8");

    await handleNativeRuntimeCommand("install-agent-pack", [packRoot], { configDir });
    const runtimeProfile = JSON.parse(
      await readFile(join(configDir, "agents", "headless.json"), "utf8"),
    );

    assert.deepEqual(runtimeProfile.appearance, { kind: "abstract" });
  });

  it("uses the existing shared persona workspace for legacy installed profiles", async () => {
    const configDir = await tempConfigDir();
    const sharedPersonasRoot = join(configDir, "SharedPersonas");
    const workspaceRoot = join(sharedPersonasRoot, "legacy");
    await mkdir(workspaceRoot, { recursive: true });
    await writeFile(join(workspaceRoot, "agent.json"), "{}", "utf8");
    await writeFile(join(workspaceRoot, "identity-prompt.md"), "Identity.", "utf8");
    await mkdir(join(configDir, "agents"), { recursive: true });
    await writeFile(
      join(configDir, "agents", "legacy.json"),
      JSON.stringify(
        {
          id: "legacy",
          name: "Legacy",
          tagline: "Legacy shared workspace.",
          personality_prompt: "Legacy prompt.",
          appearance: { kind: "abstract" },
          skills: [],
          source: "module_pack",
          version: "1.0.0",
        },
        null,
        2,
      ),
      "utf8",
    );

    const previousRoot = process.env.GEEAGENT_PERSONAS_ROOT;
    process.env.GEEAGENT_PERSONAS_ROOT = sharedPersonasRoot;
    try {
      const snapshot = JSON.parse(
        await handleNativeRuntimeCommand("snapshot", [], { configDir }),
      );
      const profile = snapshot.agent_profiles.find(
        (item: { id: string }) => item.id === "legacy",
      );
      assert.equal(profile.file_state.workspace_root_path, workspaceRoot);
      assert.equal(
        profile.file_state.identity_prompt_path,
        join(workspaceRoot, "identity-prompt.md"),
      );
      assert.equal(profile.file_state.soul_path, undefined);
    } finally {
      if (previousRoot === undefined) {
        delete process.env.GEEAGENT_PERSONAS_ROOT;
      } else {
        process.env.GEEAGENT_PERSONAS_ROOT = previousRoot;
      }
    }
  });

  it("loads and saves chat routing settings through the shared TS chat runtime", async () => {
    const configDir = await tempConfigDir();
    const settingsRaw = await handleNativeRuntimeCommand(
      "get-chat-routing-settings",
      [],
      { configDir },
    );
    const settings = JSON.parse(settingsRaw);
    settings.routeClasses[0].model = "gpt-5.4";

    const snapshotRaw = await handleNativeRuntimeCommand(
      "save-chat-routing-settings",
      [JSON.stringify(settings)],
      { configDir },
    );
    const snapshot = JSON.parse(snapshotRaw);
    assert.equal(snapshot.active_agent_profile.id, "gee");

    const reloadedRaw = await handleNativeRuntimeCommand(
      "get-chat-routing-settings",
      [],
      { configDir },
    );
    const reloaded = JSON.parse(reloadedRaw);
    assert.equal(reloaded.routeClasses[0].model, "gpt-5.4");
  });

  it("does not replace an unreadable runtime store with defaults", async () => {
    const configDir = await tempConfigDir();
    const storePath = join(configDir, "runtime-store.json");
    const malformed = "{\"conversations\":[";
    await writeFile(storePath, malformed, "utf8");

    await assert.rejects(
      handleNativeRuntimeCommand("create-conversation", [], { configDir }),
      /failed to load runtime store/,
    );
    assert.equal(await readFile(storePath, "utf8"), malformed);
  });

  it("invokes navigation tools through the TS native runtime", async () => {
    const configDir = await tempConfigDir();
    const raw = await handleNativeRuntimeCommand(
      "invoke-tool",
      [
        JSON.stringify({
          tool_id: "navigate.openSection",
          arguments: { section: "tasks" },
        }),
      ],
      { configDir },
    );
    const outcome = JSON.parse(raw);
    assert.deepEqual(outcome, {
      kind: "completed",
      tool_id: "navigate.openSection",
      payload: {
        intent: "navigate.section",
        section: "tasks",
      },
    });
  });

  it("projects Gee host app and gear tools as intents for the native macOS host", async () => {
    const configDir = await tempConfigDir();

    const openSurfaceRaw = await handleNativeRuntimeCommand(
      "invoke-tool",
      [
        JSON.stringify({
          tool_id: "gee.app.openSurface",
          arguments: { gear_id: "media.library" },
        }),
      ],
      { configDir },
    );
    const openSurface = JSON.parse(openSurfaceRaw);
    assert.deepEqual(openSurface, {
      kind: "completed",
      tool_id: "gee.app.openSurface",
      payload: {
        intent: "navigate.module",
        module_id: "media.library",
      },
    });

    const listRaw = await handleNativeRuntimeCommand(
      "invoke-tool",
      [
        JSON.stringify({
          tool_id: "gee.gear.listCapabilities",
          arguments: { detail: "summary" },
        }),
      ],
      { configDir },
    );
    const list = JSON.parse(listRaw);
    assert.deepEqual(list, {
      kind: "completed",
      tool_id: "gee.gear.listCapabilities",
      payload: {
        intent: "gear.list_capabilities",
        detail: "summary",
      },
    });

    const invokeRaw = await handleNativeRuntimeCommand(
      "invoke-tool",
      [
        JSON.stringify({
          tool_id: "gee.gear.invoke",
          arguments: {
            gear_id: "media.library",
            capability_id: "media.filter",
            args: {
              kind: "video",
              extensions: ["mp4"],
              starred_only: true,
              minimum_duration_seconds: 180,
            },
          },
        }),
      ],
      { configDir },
    );
    const invoke = JSON.parse(invokeRaw);
    assert.deepEqual(invoke, {
      kind: "completed",
      tool_id: "gee.gear.invoke",
      payload: {
        intent: "gear.invoke",
        gear_id: "media.library",
        capability_id: "media.filter",
        args: {
          kind: "video",
          extensions: ["mp4"],
          starred_only: true,
          minimum_duration_seconds: 180,
        },
      },
    });
  });

  it("enforces active persona tool allow-lists in the TS native runtime", async () => {
    const configDir = await tempConfigDir();
    const snapshot = JSON.parse(
      await handleNativeRuntimeCommand("snapshot", [], { configDir }),
    );
    const storePath = join(configDir, "runtime-store.json");
    await writeFile(
      storePath,
      JSON.stringify(
        {
          ...snapshot,
          active_agent_profile_id: "limited",
          agent_profiles: [
            ...snapshot.agent_profiles,
            {
              id: "limited",
              name: "Limited",
              tagline: "Navigation only",
              personality_prompt: "",
              appearance: { kind: "abstract" },
              skills: [],
              allowed_tool_ids: ["navigate.*"],
              source: "test",
              version: "1.0.0",
            },
          ],
          active_conversation_id: snapshot.active_conversation.conversation_id,
          conversations: [
            {
              conversation_id: snapshot.active_conversation.conversation_id,
              title: snapshot.active_conversation.title,
              status: snapshot.active_conversation.status,
              messages: snapshot.active_conversation.messages,
            },
          ],
        },
        null,
        2,
      ),
      "utf8",
    );

    const raw = await handleNativeRuntimeCommand(
      "invoke-tool",
      [
        JSON.stringify({
          tool_id: "shell.run",
          arguments: { command: "pwd" },
          approval_token: "frontend-cannot-elevate",
        }),
      ],
      { configDir },
    );
    const outcome = JSON.parse(raw);
    assert.equal(outcome.kind, "denied");
    assert.equal(outcome.tool_id, "shell.run");
  });

  it("keeps shell approval semantics aligned with the native dispatcher", async () => {
    const configDir = await tempConfigDir();
    const needsApprovalRaw = await handleNativeRuntimeCommand(
      "invoke-tool",
      [
        JSON.stringify({
          tool_id: "shell.run",
          arguments: { command: "node", args: ["--version"] },
        }),
      ],
      { configDir },
    );
    const needsApproval = JSON.parse(needsApprovalRaw);
    assert.equal(needsApproval.kind, "needs_approval");
    assert.equal(needsApproval.blast_radius, "external");

    const readOnlyRaw = await handleNativeRuntimeCommand(
      "invoke-tool",
      [
        JSON.stringify({
          tool_id: "shell.run",
          arguments: { command: "echo", args: ["hello"] },
        }),
      ],
      { configDir },
    );
    const readOnly = JSON.parse(readOnlyRaw);
    assert.equal(readOnly.kind, "completed");
    assert.equal(readOnly.payload.stdout, "hello\n");
  });

  it("lets highest authorization satisfy tool approval without changing Swift payload shape", async () => {
    const configDir = await tempConfigDir();
    await handleNativeRuntimeCommand("set-highest-authorization", ["true"], {
      configDir,
    });

    const raw = await handleNativeRuntimeCommand(
      "invoke-tool",
      [
        JSON.stringify({
          tool_id: "files.writeText",
          arguments: {
            path: join(configDir, "tool-output.txt"),
            contents: "from highest auth",
          },
        }),
      ],
      { configDir },
    );
    const outcome = JSON.parse(raw);
    assert.equal(outcome.kind, "completed");
    assert.equal(await readFile(join(configDir, "tool-output.txt"), "utf8"), "from highest auth");
  });

  it("records SDK runtime setup failures as real failed chat turns", async () => {
    const configDir = await tempConfigDir();
    const previousKey = process.env.XENODIA_API_KEY;
    delete process.env.XENODIA_API_KEY;
    const raw = await handleNativeRuntimeCommand(
      "submit-workspace-message",
      ["hello from a missing provider"],
      { configDir },
    ).finally(() => {
      if (previousKey === undefined) {
        delete process.env.XENODIA_API_KEY;
      } else {
        process.env.XENODIA_API_KEY = previousKey;
      }
    });
    const snapshot = JSON.parse(raw);
    const messages = snapshot.active_conversation.messages;

    assert.equal(messages.at(-2).role, "user");
    assert.equal(messages.at(-2).content, "hello from a missing provider");
    assert.equal(messages.at(-1).role, "assistant");
    assert.match(messages.at(-1).content, /did not complete/i);
    assert.equal(snapshot.last_run_state.status, "failed");
    assert.equal(snapshot.last_run_state.stop_reason, "claude_sdk_failed");
    assert.equal(snapshot.last_request_outcome.kind, "chat_reply");
  });

  it("does not pin a completed failed turn as the global degraded runtime state", async () => {
    const configDir = await tempConfigDir();
    await writeFile(
      join(configDir, "chat-runtime-secrets.toml"),
      `
version = 1

[providers.xenodia]
api_key = "saved-xenodia-key"
`,
      "utf8",
    );
    await writeFile(
      join(configDir, "runtime-store.json"),
      JSON.stringify(
        {
          last_run_state: {
            conversation_id: "conv_01",
            status: "failed",
            stop_reason: "claude_sdk_failed",
            detail: "The previous SDK turn timed out.",
            resumable: false,
            task_id: null,
            module_run_id: null,
          },
          chat_runtime: {
            status: "degraded",
            active_provider: "sdk/xenodia",
            detail: "The previous SDK turn timed out.",
          },
        },
        null,
        2,
      ),
      "utf8",
    );

    const raw = await handleNativeRuntimeCommand("snapshot", [], { configDir });
    const snapshot = JSON.parse(raw);

    assert.equal(snapshot.last_run_state.status, "failed");
    assert.equal(snapshot.chat_runtime.status, "live");
    assert.equal(snapshot.chat_runtime.active_provider, "xenodia");
  });

  it("treats lsof listening-port no-match as a successful inspection result", () => {
    const normalized = __sdkTurnRunnerTestHooks.normalizeSdkToolResult(
      {
        type: "session.tool_result",
        sessionId: "session_test",
        toolUseId: "toolu_lsof",
        status: "failed",
        summary: "Exit code 1",
        error: "Exit code 1",
        raw: {},
      },
      {
        tool_name: "Bash",
        input: {
          command: "lsof -nP -iTCP:8088 -sTCP:LISTEN",
        },
      },
    );

    assert.equal(normalized.status, "succeeded");
    assert.match(normalized.summary ?? "", /No matching listening process/);
    assert.equal(normalized.error, undefined);
  });

  it("keeps unrelated non-zero Bash results marked as failed", () => {
    const normalized = __sdkTurnRunnerTestHooks.normalizeSdkToolResult(
      {
        type: "session.tool_result",
        sessionId: "session_test",
        toolUseId: "toolu_false",
        status: "failed",
        summary: "Exit code 1",
        error: "Exit code 1",
        raw: {},
      },
      {
        tool_name: "Bash",
        input: {
          command: "false",
        },
      },
    );

    assert.equal(normalized.status, "failed");
    assert.equal(normalized.error, "Exit code 1");
  });

  it("keeps SDK event waits below the native client timeout", () => {
    const previous = process.env.GEEAGENT_SDK_EVENT_IDLE_TIMEOUT_MS;
    process.env.GEEAGENT_SDK_EVENT_IDLE_TIMEOUT_MS = "6000";
    try {
      assert.equal(__sdkTurnRunnerTestHooks.sdkEventIdleTimeoutMs(), 6_000);
      assert.match(
        __sdkTurnRunnerTestHooks.sdkEventIdleTimeoutReason(6_000),
        /stopped this run instead of leaving the conversation loading forever/,
      );
    } finally {
      if (previous === undefined) {
        delete process.env.GEEAGENT_SDK_EVENT_IDLE_TIMEOUT_MS;
      } else {
        process.env.GEEAGENT_SDK_EVENT_IDLE_TIMEOUT_MS = previous;
      }
    }
  });

  it("closes unresolved tool invocations when an SDK run fails", () => {
    const turn = {
      assistant_chunks: [],
      auto_approved_tools: 0,
      failed_reason: "The SDK runtime produced no new event for 75 seconds.",
      tool_events: [
        {
          kind: "invocation" as const,
          invocation_id: "call_websearch",
          tool_name: "WebSearch",
          input_summary: "{\"query\":\"Coinbase COIN previous trading day\"}",
        },
      ],
    };

    __sdkTurnRunnerTestHooks.closeUnfinishedToolEventsOnFailure(turn);

    assert.deepEqual(turn.tool_events.at(-1), {
      kind: "result",
      invocation_id: "call_websearch",
      status: "failed",
      summary: "The tool did not return before the SDK run ended.",
      error: "The SDK runtime produced no new event for 75 seconds.",
    });
  });

  it("recycles the long-lived SDK gateway after failed non-approval turns", () => {
    assert.equal(
      __sdkTurnRunnerTestHooks.shouldRecycleGatewayAfterTurn({
        assistant_chunks: [],
        auto_approved_tools: 0,
        tool_events: [],
        failed_reason: "The SDK runtime produced no new event for 75 seconds.",
      }),
      true,
    );
    assert.equal(
      __sdkTurnRunnerTestHooks.shouldRecycleGatewayAfterTurn({
        assistant_chunks: [],
        auto_approved_tools: 0,
        tool_events: [],
        pending_terminal_approval: {
          runtime_session_id: "session_test",
          runtime_request_id: "request_test",
          scope: { kind: "sdk_bridge_bash", command: "echo ok" },
          command: "echo ok",
        },
      }),
      false,
    );
  });

  it("directs SDK web lookup requests to inspectable Bash network checks", () => {
    assert.match(
      __sdkTurnRunnerTestHooks.unsupportedToolDenialMessage("WebSearch"),
      /Use Bash with an inspectable command such as curl or python urllib/,
    );
  });

  it("expires approval resumes that no longer have a live TS SDK session", async () => {
    const configDir = await tempConfigDir();
    await writeFile(
      join(configDir, "runtime-store.json"),
      JSON.stringify(
        {
          tasks: [
            {
              task_id: "task_sdk_approval",
              conversation_id: "conv_01",
              title: "Terminal approval",
              summary: "Waiting on SDK callback.",
              current_stage: "approval_required",
              status: "waiting_review",
              importance_level: "normal",
              progress_percent: 68,
              artifact_count: 0,
              approval_request_id: "apr_sdk_approval",
            },
          ],
          approval_requests: [
            {
              approval_request_id: "apr_sdk_approval",
              task_id: "task_sdk_approval",
              action_title: "Authorization Needed",
              reason: "SDK callback.",
              risk_tags: ["terminal"],
              review_required: true,
              status: "open",
              parameters: [{ label: "Command", value: "echo stale" }],
              machine_context: {
                kind: "sdk_bridge_terminal",
                source: "workspace_chat",
                surface: "cli_workspace_chat",
                user_prompt: "Run a shell command.",
                bridge_session_id: "session_missing",
                bridge_request_id: "request_missing",
                scope: {
                  kind: "sdk_bridge_bash",
                  command: "echo stale",
                },
                command: "echo stale",
              },
            },
          ],
        },
        null,
        2,
      ),
      "utf8",
    );

    const raw = await handleNativeRuntimeCommand(
      "perform-task-action",
      ["task_sdk_approval", "allow_once"],
      { configDir },
    );
    const snapshot = JSON.parse(raw);
    assert.equal(snapshot.tasks[0].status, "failed");
    assert.equal(snapshot.tasks[0].approval_request_id, null);
    assert.equal(snapshot.approval_requests[0].status, "approved");
    assert.equal(snapshot.last_run_state.stop_reason, "claude_sdk_failed_after_approval");
  });
});

describe("native runtime JSON-lines server", () => {
  it("expires stale SDK approval cards once when the server starts", async () => {
    const configDir = await tempConfigDir();
    await writeFile(
      join(configDir, "runtime-store.json"),
      JSON.stringify(
        {
          tasks: [
            {
              task_id: "task_sdk_approval",
              title: "Terminal approval",
              summary: "Waiting on a previous SDK callback.",
              current_stage: "approval_required",
              status: "waiting_review",
              importance_level: "normal",
              progress_percent: 68,
              artifact_count: 0,
              approval_request_id: "apr_sdk_approval",
            },
          ],
          approval_requests: [
            {
              approval_request_id: "apr_sdk_approval",
              task_id: "task_sdk_approval",
              action_title: "Authorization Needed",
              reason: "Old SDK callback.",
              risk_tags: ["terminal"],
              review_required: true,
              status: "open",
              parameters: [],
              machine_context: {
                kind: "sdk_bridge_terminal",
                source: "workspace",
                surface: "chat",
                user_prompt: "Run a shell command.",
                bridge_session_id: "session_conv_01",
                bridge_request_id: "request_01",
                scope: {
                  kind: "sdk_bridge_bash",
                  command: "echo stale",
                },
                command: "echo stale",
              },
            },
          ],
        },
        null,
        2,
      ),
    );

    const envelope = await singleServerRequest(configDir, {
      id: "expire",
      command: "snapshot",
      args: [],
    });
    assert.equal(envelope.ok, true);
    const snapshot = JSON.parse(envelope.output ?? "{}");
    assert.equal(snapshot.approval_requests[0].status, "expired");
    assert.equal(snapshot.tasks[0].status, "failed");
    assert.equal(snapshot.tasks[0].approval_request_id, null);
    assert.equal(snapshot.last_run_state.stop_reason, "terminal_approval_resume_failed");
  });

  it("expires stale in-progress SDK resumes once when the server starts", async () => {
    const configDir = await tempConfigDir();
    await writeFile(
      join(configDir, "runtime-store.json"),
      JSON.stringify(
        {
          tasks: [
            {
              task_id: "task_sdk_resume",
              title: "Terminal approval",
              summary: "Approval is resuming.",
              current_stage: "approval_resuming",
              status: "running",
              importance_level: "normal",
              progress_percent: 76,
              artifact_count: 0,
              approval_request_id: null,
            },
          ],
          module_runs: [
            {
              module_run: {
                module_run_id: "run_sdk_resume",
                task_id: "task_sdk_resume",
                module_id: "geeagent.runtime.sdk",
                status: "running",
                stage: "approval_resuming",
                updated_at: "now",
              },
              recoverability: null,
            },
          ],
          approval_requests: [
            {
              approval_request_id: "apr_sdk_resume",
              task_id: "task_sdk_resume",
              action_title: "Authorization Needed",
              reason: "Already approved.",
              risk_tags: ["terminal"],
              review_required: true,
              status: "approved",
              parameters: [],
              machine_context: {
                kind: "sdk_runtime_terminal",
                runtime_session_id: "session_conv_01",
                runtime_request_id: "request_01",
                command: "echo stale",
              },
            },
          ],
          last_run_state: {
            conversation_id: "conv_01",
            status: "running",
            stop_reason: "terminal_approval_resume_in_progress",
            detail: "Approval resume in progress.",
            resumable: true,
            task_id: "task_sdk_resume",
            module_run_id: "run_sdk_resume",
          },
        },
        null,
        2,
      ),
    );

    const envelope = await singleServerRequest(configDir, {
      id: "expire-running",
      command: "snapshot",
      args: [],
    });
    assert.equal(envelope.ok, true);
    const snapshot = JSON.parse(envelope.output ?? "{}");
    assert.equal(snapshot.tasks[0].status, "failed");
    assert.equal(snapshot.tasks[0].current_stage, "stale_sdk_runtime_interrupted");
    assert.equal(snapshot.module_runs[0].module_run.status, "failed");
    assert.equal(snapshot.last_run_state.stop_reason, "sdk_runtime_interrupted");
  });

  it("uses the native runtime response envelope consumed by Swift", async () => {
    const configDir = await tempConfigDir();
    const child = spawn(
      process.execPath,
      ["--import", "tsx", "src/native-runtime/index.ts", "serve", "--config-dir", configDir],
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
      send(child, { id: "one", command: "snapshot", args: [] });
      const line = await nextLine(iterator, stderr);
      const envelope = JSON.parse(line) as ServerEnvelope;
      assert.equal(envelope.id, "one");
      assert.equal(envelope.ok, true);
      assert.equal(JSON.parse(envelope.output ?? "{}").active_agent_profile.id, "gee");

      send(child, { id: "two", command: "missing-command", args: [] });
      const errorLine = await nextLine(iterator, stderr);
      const errorEnvelope = JSON.parse(errorLine) as ServerEnvelope;
      assert.equal(errorEnvelope.id, "two");
      assert.equal(errorEnvelope.ok, false);
      assert.match(errorEnvelope.error ?? "", /unsupported command/);
    } finally {
      lines.close();
      child.kill();
  }
});

async function singleServerRequest(
  configDir: string,
  request: Record<string, unknown>,
): Promise<ServerEnvelope> {
  const child = spawn(
    process.execPath,
    ["--import", "tsx", "src/native-runtime/index.ts", "serve", "--config-dir", configDir],
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
    send(child, request);
    return JSON.parse(await nextLine(iterator, stderr)) as ServerEnvelope;
  } finally {
    lines.close();
    child.kill();
  }
}
});

async function nextLine(
  iterator: AsyncIterator<string>,
  stderr: string[],
): Promise<string> {
  const result = await Promise.race([
    iterator.next(),
    new Promise<IteratorResult<string>>((_, reject) =>
      setTimeout(
        () => reject(new Error(`server timed out: ${stderr.join("").trim()}`)),
        5_000,
      ),
    ),
  ]);
  assert.equal(result.done, false);
  return result.value;
}
