import assert from "node:assert/strict";
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { mkdir, mkdtemp, readFile, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import readline from "node:readline";
import { describe, it } from "node:test";

import { handleNativeRuntimeCommand } from "./native-runtime/commands.js";
import { buildContextProjection } from "./native-runtime/context/projector.js";
import { prepareHostActionCompletionsForModel } from "./native-runtime/context/host-action-results.js";
import { estimateTextTokens } from "./native-runtime/context/token-estimator.js";
import {
  __sdkTurnRunnerTestHooks,
  type SdkTurnResult,
} from "./native-runtime/sdk-turn-runner.js";
import { QUICK_CONVERSATION_TAG } from "./native-runtime/store/conversations.js";
import { defaultRuntimeStore } from "./native-runtime/store/defaults.js";
import {
  appendAssistantDeltaForActiveConversation,
  appendAssistantMessageForActiveConversation,
  appendCapabilityFocusForSession,
  appendRunPlanForSession,
  appendStageConclusionForSession,
  appendStageStartedForSession,
  appendToolEvents,
  appendToolResultForExistingInvocation,
  appendToolResultForHostBridgeCompletion,
  beginTurnReplay,
  executionSessionIdForConversation,
  finalizeTurnReplay,
  latestRunIdForSession,
} from "./native-runtime/turns/events.js";
import {
  sdkRuntimeBashScope,
  terminalAccessDecisionForScope,
} from "./native-runtime/store/terminal-permissions.js";
import { __turnTestHooks } from "./native-runtime/turns.js";
import {
  requiresGeeGearBridgeFirst,
  routeLocalGearIntent,
} from "./native-runtime/turns/gear-intents.js";
import {
  buildRuntimeRunPlan,
  capabilityFocusArgsForPlan,
  capabilityFocusForStage,
  nextRuntimeRunPlan,
  selectRuntimePlanningMode,
} from "./native-runtime/turns/planning.js";
import {
  advanceRunPlanAfterHostCompletions,
  terminalRunPlanBlocker,
} from "./native-runtime/turns/stage-advancer.js";

type ServerEnvelope = {
  id: string;
  ok: boolean;
  output?: string;
  error?: string;
};

async function tempConfigDir(): Promise<string> {
  return mkdtemp(join(tmpdir(), "geeagent-native-runtime-"));
}

async function writeSkill(
  sourceRoot: string,
  skillDirName: string,
  metadata: { name: string; description?: string },
  body: string,
): Promise<string> {
  const skillRoot = join(sourceRoot, skillDirName);
  await mkdir(skillRoot, { recursive: true });
  const frontmatter = [
    "---",
    `name: ${metadata.name}`,
    metadata.description ? `description: ${metadata.description}` : "",
    "---",
  ]
    .filter(Boolean)
    .join("\n");
  await writeFile(join(skillRoot, "SKILL.md"), `${frontmatter}\n\n${body}\n`, "utf8");
  return skillRoot;
}

async function writeAgentPack(root: string, id: string): Promise<void> {
  await mkdir(root, { recursive: true });
  await writeFile(
    join(root, "agent.json"),
    JSON.stringify(
      {
        definition_version: "2",
        id,
        name: "Skill Test Persona",
        tagline: "Persona with explicit local skills",
        identity_prompt_path: "identity-prompt.md",
        soul_path: "soul.md",
        playbook_path: "playbook.md",
        appearance: { kind: "abstract" },
        source: "module_pack",
        version: "1.0.0",
      },
      null,
      2,
    ),
    "utf8",
  );
  await writeFile(join(root, "identity-prompt.md"), "Identity layer.", "utf8");
  await writeFile(join(root, "soul.md"), "Soul layer.", "utf8");
  await writeFile(join(root, "playbook.md"), "Playbook layer.", "utf8");
}

function send(
  child: ChildProcessWithoutNullStreams,
  request: Record<string, unknown>,
): void {
  child.stdin.write(`${JSON.stringify(request)}\n`);
}

describe("native runtime command modules", () => {
  it("estimates compact text with a conservative token budget", () => {
    assert.equal(estimateTextTokens("continue context compression"), 7);
    assert.ok(estimateTextTokens("plain ascii words") >= 4);
  });

  it("projects long conversation history into a compact model-facing context", () => {
    const history = [
      {
        role: "user",
        content: `oldest-marker ${"old background ".repeat(2500)}`,
      },
      ...Array.from({ length: 40 }, (_, index) => ({
        role: index % 2 === 0 ? "assistant" : "user",
        content: `middle turn ${index} ${"tool output ".repeat(700)}`,
      })),
      {
        role: "assistant",
        content: "recent-keep-marker final observed result",
      },
    ];

    const projection = buildContextProjection(history, {
      latestUserRequest: "Please continue the next phase and keep this complete question",
      compactTriggerTokens: 1_000,
      recentTokenBudget: 2_500,
    });

    const projectedText = projection.messages.map((message) => message.content).join("\n");
    assert.equal(projection.mode, "compacted");
    assert.ok(projection.compactedMessagesCount > 0);
    assert.ok(projection.rawHistoryTokens > projection.projectedHistoryTokens);
    assert.doesNotMatch(projectedText, /oldest-marker/);
    assert.match(projectedText, /recent-keep-marker/);
    assert.equal(projection.latestRequestTokens, estimateTextTokens("Please continue the next phase and keep this complete question"));
  });

  it("does not increase model-facing tokens when compacting an oversized tail", () => {
    const history = [
      {
        role: "user",
        content: "short old context",
      },
      {
        role: "assistant",
        content: "oversized-tail ".repeat(10_000),
      },
    ];

    const projection = buildContextProjection(history, {
      latestUserRequest: "continue",
      compactTriggerTokens: 100,
      recentTokenBudget: 10,
    });

    assert.equal(projection.mode, "compacted");
    assert.ok(projection.projectedHistoryTokens <= projection.rawHistoryTokens);
    assert.equal(projection.summaryTokens, 0);
    assert.doesNotMatch(
      projection.messages.map((message) => message.content).join("\n"),
      /short old context/,
    );
  });

  it("keeps a single oversized history message honest instead of claiming compaction", () => {
    const history = [
      {
        role: "assistant",
        content: "single huge message ".repeat(10_000),
      },
    ];

    const projection = buildContextProjection(history, {
      latestUserRequest: "continue",
      compactTriggerTokens: 100,
      recentTokenBudget: 10,
    });

    assert.equal(projection.mode, "full_recent");
    assert.equal(projection.projectedHistoryTokens, projection.rawHistoryTokens);
    assert.equal(projection.compactedMessagesCount, 0);
  });

  it("renders workspace prompts from the projected context and updates budget telemetry", () => {
    const now = "2026-04-27T12:00:00.000Z";
    const store = defaultRuntimeStore(now);
    store.conversations[0].messages = [
      {
        message_id: "msg_user_01",
        role: "user",
        content: `oldest-secret ${"very old terminal output ".repeat(4000)}`,
        timestamp: now,
      },
      ...Array.from({ length: 40 }, (_, index) => ({
        message_id: `msg_${String(index + 2).padStart(2, "0")}`,
        role: index % 2 === 0 ? "assistant" : "user",
        content: `middle ${index} ${"large result ".repeat(900)}`,
        timestamp: now,
      })),
      {
        message_id: "msg_assistant_recent",
        role: "assistant",
        content: "recent-stage-result should stay visible",
        timestamp: now,
      },
    ];
    store.transcript_events.push({
      event_id: "event_stage_capsule",
      session_id: `session_${store.active_conversation_id}`,
      parent_event_id: null,
      created_at: now,
      payload: {
        kind: "session_state_changed",
        summary: "Context capsule updated.",
        stage_capsule: "[GEEAGENT STAGE SUMMARY CAPSULE]\nRecent deterministic stage capsule.\n[/GEEAGENT STAGE SUMMARY CAPSULE]",
      },
    });

    const route = {
      mode: "workspace_message" as const,
      source: "workspace_chat" as const,
      surface: "cli_workspace_chat" as const,
    };
    const latest = "Please continue the next phase and preserve this sentence fully";
    const prepared = __turnTestHooks.prepareTurnContext(store, route, latest);
    const prompt = __turnTestHooks.composeClaudeSdkTurnPrompt(route, prepared, latest);

    assert.equal(prepared.contextProjection.mode, "compacted");
    assert.equal(prepared.stageCapsuleMessages.length, 1);
    assert.match(prompt, /Context projection mode: compacted/);
    assert.doesNotMatch(prompt, /oldest-secret/);
    assert.match(prompt, /recent-stage-result should stay visible/);
    assert.match(prompt, /Recent deterministic stage capsule/);
    assert.match(prompt, /Latest user request:\nPlease continue the next phase and preserve this sentence fully/);
    assert.equal(store.context_budget.projection_mode, "compacted");
    assert.ok(Number(store.context_budget.raw_history_tokens) > Number(store.context_budget.projected_history_tokens));
    assert.ok(Number(store.context_budget.compacted_messages_count) > 0);
  });

  it("does not inject stage capsules into small unprojected histories", () => {
    const now = "2026-04-27T12:00:00.000Z";
    const store = defaultRuntimeStore(now);
    store.conversations[0].messages = [
      {
        message_id: "msg_user_01",
        role: "user",
        content: "small context",
        timestamp: now,
      },
    ];
    store.transcript_events.push({
      event_id: "event_stage_capsule",
      session_id: `session_${store.active_conversation_id}`,
      parent_event_id: null,
      created_at: now,
      payload: {
        kind: "session_state_changed",
        summary: "Context capsule updated.",
        stage_capsule: "[GEEAGENT STAGE SUMMARY CAPSULE]\nDo not include me yet.\n[/GEEAGENT STAGE SUMMARY CAPSULE]",
      },
    });

    const route = {
      mode: "workspace_message" as const,
      source: "workspace_chat" as const,
      surface: "cli_workspace_chat" as const,
    };
    const prepared = __turnTestHooks.prepareTurnContext(store, route, "next");
    const prompt = __turnTestHooks.composeClaudeSdkTurnPrompt(route, prepared, "next");

    assert.equal(prepared.contextProjection.mode, "full_recent");
    assert.equal(prepared.stageCapsuleMessages.length, 1);
    assert.doesNotMatch(prompt, /Do not include me yet/);
  });

  it("keeps direct and light turns from inheriting stage capsules", () => {
    const now = "2026-04-27T12:00:00.000Z";
    const store = defaultRuntimeStore(now);
    store.conversations[0].messages = [
      {
        message_id: "msg_user_old",
        role: "user",
        content: `old direct context ${"large history ".repeat(5000)}`,
        timestamp: now,
      },
      {
        message_id: "msg_assistant_recent",
        role: "assistant",
        content: "recent answer should remain available",
        timestamp: now,
      },
    ];
    store.transcript_events.push({
      event_id: "event_stage_capsule",
      session_id: `session_${store.active_conversation_id}`,
      parent_event_id: null,
      created_at: now,
      payload: {
        kind: "session_state_changed",
        summary: "Context capsule updated.",
        stage_capsule: "[GEEAGENT STAGE SUMMARY CAPSULE]\nStructured-only capsule.\n[/GEEAGENT STAGE SUMMARY CAPSULE]",
      },
    });

    const route = {
      mode: "workspace_message" as const,
      source: "workspace_chat" as const,
      surface: "cli_workspace_chat" as const,
    };

    for (const mode of ["direct", "light"] as const) {
      const prepared = __turnTestHooks.prepareTurnContext(store, route, "continue", mode);
      const prompt = __turnTestHooks.composeClaudeSdkTurnPrompt(route, prepared, "continue");

      assert.equal(prepared.stageCapsuleMessages.length, 0);
      assert.doesNotMatch(prompt, /Structured-only capsule/);
      assert.match(prompt, /recent answer should remain available/);
    }
  });

  it("excludes quick-tagged conversations from automatic routing candidates", () => {
    const now = "2026-04-27T12:00:00.000Z";
    const store = defaultRuntimeStore(now);
    store.conversations = [
      {
        conversation_id: "conv_quick",
        title: "OpenAI article",
        status: "idle",
        tags: [QUICK_CONVERSATION_TAG],
        messages: [
          {
            message_id: "msg_quick",
            role: "assistant",
            content: "OpenAI article research notes",
            timestamp: now,
          },
        ],
      },
      {
        conversation_id: "conv_regular",
        title: "OpenAI article",
        status: "idle",
        messages: [
          {
            message_id: "msg_regular",
            role: "assistant",
            content: "OpenAI article research notes",
            timestamp: now,
          },
        ],
      },
    ];
    store.active_conversation_id = "conv_quick";

    const routed = __turnTestHooks.routeQuickPromptToBestConversation(
      store,
      "find the openai article notes",
    );

    assert.equal(routed, "conv_regular");
    assert.equal(store.active_conversation_id, "conv_regular");
  });

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
    const createdConversationId = created.active_conversation.conversation_id;
    assert.match(createdConversationId, /^conv_02_[a-f0-9]{8}$/);
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
    assert.equal(deleted.active_conversation.conversation_id, createdConversationId);
  });

  it("does not reuse a deleted conversation id or its transcript history", async () => {
    const configDir = await tempConfigDir();
    const created = JSON.parse(
      await handleNativeRuntimeCommand("create-conversation", [], { configDir }),
    );
    const deletedConversationId = created.active_conversation.conversation_id;
    const deletedSessionId = `session_${deletedConversationId}`;

    const storePath = join(configDir, "runtime-store.json");
    const store = JSON.parse(await readFile(storePath, "utf8"));
    const deletedConversation = store.conversations.find(
      (conversation: { conversation_id?: string }) =>
        conversation.conversation_id === deletedConversationId,
    );
    deletedConversation.messages.push({
      message_id: "msg_user_deleted",
      role: "user",
      content: "deleted content should not come back",
      timestamp: "2026-04-26T00:00:00.000Z",
    });
    store.execution_sessions.push({
      session_id: deletedSessionId,
      conversation_id: deletedConversationId,
      surface: "cli_workspace_chat",
      mode: "interactive",
      project_path: "/tmp/project",
      parent_session_id: null,
      persistence_policy: "persisted",
      created_at: "now",
      updated_at: "now",
    });
    store.transcript_events.push({
      event_id: `event_${deletedSessionId}_01`,
      session_id: deletedSessionId,
      parent_event_id: null,
      created_at: "now",
      payload: {
        kind: "user_message",
        message_id: "msg_user_deleted",
        content: "deleted content should not come back",
      },
    });
    await writeFile(storePath, `${JSON.stringify(store, null, 2)}\n`, "utf8");

    await handleNativeRuntimeCommand("delete-conversation", [deletedConversationId], {
      configDir,
    });

    const afterDelete = JSON.parse(await readFile(storePath, "utf8"));
    assert.equal(
      afterDelete.conversations.some(
        (conversation: { conversation_id?: string }) =>
          conversation.conversation_id === deletedConversationId,
      ),
      false,
    );
    assert.equal(
      afterDelete.execution_sessions.some(
        (session: { conversation_id?: string; session_id?: string }) =>
          session.conversation_id === deletedConversationId ||
          session.session_id === deletedSessionId,
      ),
      false,
    );
    assert.equal(
      afterDelete.transcript_events.some(
        (event: { session_id?: string }) => event.session_id === deletedSessionId,
      ),
      false,
    );

    const recreated = JSON.parse(
      await handleNativeRuntimeCommand("create-conversation", [], { configDir }),
    );
    assert.notEqual(recreated.active_conversation.conversation_id, deletedConversationId);
    assert.equal(
      recreated.active_conversation.messages.some(
        (message: { content?: string }) =>
          message.content === "deleted content should not come back",
      ),
      false,
    );
  });

  it("drops orphaned conversation sessions when loading persisted runtime state", async () => {
    const configDir = await tempConfigDir();
    await handleNativeRuntimeCommand("create-conversation", [], { configDir });

    const storePath = join(configDir, "runtime-store.json");
    const store = JSON.parse(await readFile(storePath, "utf8"));
    store.execution_sessions.push({
      session_id: "session_conv_deleted",
      conversation_id: "conv_deleted",
      surface: "cli_workspace_chat",
      mode: "interactive",
      project_path: "/tmp/project",
      parent_session_id: null,
      persistence_policy: "persisted",
      created_at: "now",
      updated_at: "now",
    });
    store.transcript_events.push({
      event_id: "event_session_conv_deleted_01",
      session_id: "session_conv_deleted",
      parent_event_id: null,
      created_at: "now",
      payload: {
        kind: "user_message",
        message_id: "msg_user_deleted",
        content: "orphaned content should not be projected",
      },
    });
    await writeFile(storePath, `${JSON.stringify(store, null, 2)}\n`, "utf8");

    const snapshot = JSON.parse(
      await handleNativeRuntimeCommand("snapshot", [], { configDir }),
    );
    assert.equal(
      snapshot.execution_sessions.some(
        (session: { session_id?: string }) =>
          session.session_id === "session_conv_deleted",
      ),
      false,
    );
    assert.equal(
      snapshot.transcript_events.some(
        (event: { session_id?: string }) =>
          event.session_id === "session_conv_deleted",
      ),
      false,
    );
  });

  it("drops orphaned host-action lineage when persisted conversations are pruned", async () => {
    const configDir = await tempConfigDir();
    await handleNativeRuntimeCommand("create-conversation", [], { configDir });

    const storePath = join(configDir, "runtime-store.json");
    const store = JSON.parse(await readFile(storePath, "utf8"));
    store.host_action_intents = [
      {
        host_action_id: "host_action_orphaned",
        tool_id: "gee.gear.invoke",
        arguments: {
          gear_id: "wespy.reader",
          capability_id: "wespy.fetch_article",
          args: { url: "https://mp.weixin.qq.com/s/orphaned" },
        },
      },
    ];
    store.host_action_runs = [
      {
        host_action_id: "host_action_orphaned",
        run_id: "run_session_conv_deleted_0001",
        tool_id: "gee.gear.invoke",
        session_id: "session_conv_deleted",
        conversation_id: "conv_deleted",
        user_message_id: "msg_user_deleted",
        source: "sdk_same_run",
        status: "pending",
        created_at: "now",
        updated_at: "now",
      },
    ];
    await writeFile(storePath, `${JSON.stringify(store, null, 2)}\n`, "utf8");

    await handleNativeRuntimeCommand("create-conversation", [], { configDir });
    const normalized = JSON.parse(await readFile(storePath, "utf8"));

    assert.deepEqual(normalized.host_action_runs, []);
    assert.deepEqual(normalized.host_action_intents, []);
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

  it("adds explicit system skill sources and hot-refreshes metadata without scanning unrelated folders", async () => {
    const configDir = await tempConfigDir();
    const systemSourceRoot = join(configDir, "skills", "global");
    await writeSkill(
      systemSourceRoot,
      "draft-helper",
      {
        name: "draft-helper",
        description: "Helps Gee draft concise local replies",
      },
      "SECRET SYSTEM SKILL BODY SHOULD NOT BE INJECTED",
    );
    await writeSkill(
      join(configDir, "unregistered-skills"),
      "unlisted-helper",
      {
        name: "unlisted-helper",
        description: "This folder was never added as a source",
      },
      "UNREGISTERED BODY",
    );

    const added = JSON.parse(
      await handleNativeRuntimeCommand("add-system-skill-source", [systemSourceRoot], {
        configDir,
      }),
    );
    assert.deepEqual(
      added.skill_sources.system_sources.flatMap(
        (source: { skills?: Array<{ id: string }> }) =>
          (source.skills ?? []).map((skill) => skill.id),
      ),
      ["draft-helper"],
    );
    assert.equal(
      added.active_agent_profile.skills.some(
        (skill: { id?: string }) => skill.id === "unlisted-helper",
      ),
      false,
    );

    await writeSkill(
      systemSourceRoot,
      "image-helper",
      {
        name: "image-helper",
        description: "Summarizes image editing requests",
      },
      "HOT UPDATED BODY SHOULD NOT BE INJECTED",
    );

    const hot = JSON.parse(
      await handleNativeRuntimeCommand("snapshot", [], { configDir }),
    );
    assert.deepEqual(
      hot.active_agent_profile.skills
        .filter((skill: { source_scope?: string }) => skill.source_scope === "system")
        .map((skill: { id: string }) => skill.id)
        .sort(),
      ["draft-helper", "image-helper"],
    );
  });

  it("injects skill metadata into the SDK prompt without injecting SKILL.md bodies", async () => {
    const configDir = await tempConfigDir();
    const systemSourceRoot = join(configDir, "skills", "global");
    await writeSkill(
      systemSourceRoot,
      "metadata-only",
      {
        name: "metadata-only",
        description: "Visible description only",
      },
      "FULL BODY SENTINEL: never expose this instruction text to the agent prompt.",
    );
    const snapshot = JSON.parse(
      await handleNativeRuntimeCommand("add-system-skill-source", [systemSourceRoot], {
        configDir,
      }),
    );
    const hooks = __sdkTurnRunnerTestHooks as typeof __sdkTurnRunnerTestHooks & {
      activeAgentSystemPrompt: (
        configDir: string,
        profile: typeof snapshot.active_agent_profile,
      ) => Promise<string>;
    };

    const prompt = await hooks.activeAgentSystemPrompt(
      configDir,
      snapshot.active_agent_profile,
    );

    assert.match(prompt, /metadata-only/);
    assert.match(prompt, /Visible description only/);
    assert.match(prompt, /Do not invoke any SDK Skill tool/);
    assert.doesNotMatch(prompt, /FULL BODY SENTINEL/);
    assert.doesNotMatch(prompt, /never expose this instruction text/);
  });

  it("refreshes persona skill sources only when the persona is reloaded", async () => {
    const configDir = await tempConfigDir();
    const packRoot = join(configDir, "packs", "skill-test-persona");
    await writeAgentPack(packRoot, "skill-test-persona");
    await handleNativeRuntimeCommand("install-agent-pack", [packRoot], { configDir });

    const personaSourceRoot = join(configDir, "skills", "persona");
    await writeSkill(
      personaSourceRoot,
      "persona-alpha",
      {
        name: "persona-alpha",
        description: "First persona-level skill",
      },
      "ALPHA BODY",
    );

    const afterAdd = JSON.parse(
      await handleNativeRuntimeCommand(
        "add-persona-skill-source",
        ["skill-test-persona", personaSourceRoot],
        { configDir },
      ),
    );
    assert.deepEqual(
      afterAdd.agent_profiles
        .find((profile: { id: string }) => profile.id === "skill-test-persona")
        .skills.filter(
          (skill: { source_scope?: string }) => skill.source_scope === "persona",
        )
        .map((skill: { id: string }) => skill.id),
      ["persona-alpha"],
    );

    await writeSkill(
      personaSourceRoot,
      "persona-beta",
      {
        name: "persona-beta",
        description: "Second persona-level skill",
      },
      "BETA BODY",
    );

    const beforeReload = JSON.parse(
      await handleNativeRuntimeCommand("snapshot", [], { configDir }),
    );
    assert.equal(
      beforeReload.agent_profiles
        .find((profile: { id: string }) => profile.id === "skill-test-persona")
        .skills.some((skill: { id: string }) => skill.id === "persona-beta"),
      false,
    );

    const afterReload = JSON.parse(
      await handleNativeRuntimeCommand("reload-agent-profile", ["skill-test-persona"], {
        configDir,
      }),
    );
    assert.deepEqual(
      afterReload.agent_profiles
        .find((profile: { id: string }) => profile.id === "skill-test-persona")
        .skills.filter(
          (skill: { source_scope?: string }) => skill.source_scope === "persona",
        )
        .map((skill: { id: string }) => skill.id)
        .sort(),
      ["persona-alpha", "persona-beta"],
    );
  });

  it("removes persona skill source bindings when deleting the persona", async () => {
    const configDir = await tempConfigDir();
    const packRoot = join(configDir, "packs", "skill-delete-persona");
    await writeAgentPack(packRoot, "skill-delete-persona");
    await handleNativeRuntimeCommand("install-agent-pack", [packRoot], { configDir });

    const personaSourceRoot = join(configDir, "skills", "delete-persona");
    await writeSkill(
      personaSourceRoot,
      "delete-me",
      {
        name: "delete-me",
        description: "Persona source that should be removed with the persona",
      },
      "DELETE BODY",
    );
    await handleNativeRuntimeCommand(
      "add-persona-skill-source",
      ["skill-delete-persona", personaSourceRoot],
      { configDir },
    );

    const afterDelete = JSON.parse(
      await handleNativeRuntimeCommand("delete-agent-profile", ["skill-delete-persona"], {
        configDir,
      }),
    );

    assert.equal(afterDelete.skill_sources.persona_sources["skill-delete-persona"], undefined);
    assert.equal(
      afterDelete.agent_profiles.some(
        (profile: { id: string }) => profile.id === "skill-delete-persona",
      ),
      false,
    );
    const persistedSkillSources = JSON.parse(
      await readFile(join(configDir, "runtime-skill-sources.json"), "utf8"),
    );
    assert.equal(
      persistedSkillSources.persona_sources["skill-delete-persona"],
      undefined,
    );
  });

  it("removes persona skill sources without leaving empty registry buckets", async () => {
    const configDir = await tempConfigDir();
    const packRoot = join(configDir, "packs", "skill-remove-persona");
    await writeAgentPack(packRoot, "skill-remove-persona");
    await handleNativeRuntimeCommand("install-agent-pack", [packRoot], { configDir });

    const personaSourceRoot = join(configDir, "skills", "remove-persona");
    await writeSkill(
      personaSourceRoot,
      "remove-me",
      {
        name: "remove-me",
        description: "Persona source that should be removed cleanly",
      },
      "REMOVE BODY",
    );
    const afterAdd = JSON.parse(
      await handleNativeRuntimeCommand(
        "add-persona-skill-source",
        ["skill-remove-persona", personaSourceRoot],
        { configDir },
      ),
    );
    const sourceId =
      afterAdd.skill_sources.persona_sources["skill-remove-persona"][0].id;

    const afterRemove = JSON.parse(
      await handleNativeRuntimeCommand(
        "remove-persona-skill-source",
        ["skill-remove-persona", sourceId],
        { configDir },
      ),
    );

    assert.deepEqual(
      afterRemove.skill_sources.persona_sources["skill-remove-persona"],
      [],
    );
    const persistedSkillSources = JSON.parse(
      await readFile(join(configDir, "runtime-skill-sources.json"), "utf8"),
    );
    assert.equal(
      persistedSkillSources.persona_sources["skill-remove-persona"],
      undefined,
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

    const focusedListRaw = await handleNativeRuntimeCommand(
      "invoke-tool",
      [
        JSON.stringify({
          tool_id: "gee.gear.listCapabilities",
          arguments: {
            detail: "summary",
            run_plan_id: "run_plan_demo",
            stage_id: "stage_fetch_tweet",
            focus_gear_ids: ["twitter.capture", "bookmark.vault"],
            focus_capability_ids: ["twitter.fetch_tweet", "bookmark.save"],
          },
        }),
      ],
      { configDir },
    );
    const focusedList = JSON.parse(focusedListRaw);
    assert.deepEqual(focusedList, {
      kind: "completed",
      tool_id: "gee.gear.listCapabilities",
      payload: {
        intent: "gear.list_capabilities",
        detail: "summary",
        run_plan_id: "run_plan_demo",
        stage_id: "stage_fetch_tweet",
        focus_gear_ids: ["twitter.capture", "bookmark.vault"],
        focus_capability_ids: ["twitter.fetch_tweet", "bookmark.save"],
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

    const missingArgsRaw = await handleNativeRuntimeCommand(
      "invoke-tool",
      [
        JSON.stringify({
          tool_id: "gee.gear.invoke",
          arguments: {
            gear_id: "wespy.reader",
            capability_id: "wespy.fetch_article",
            args: {},
          },
        }),
      ],
      { configDir },
    );
    const missingArgs = JSON.parse(missingArgsRaw);
    assert.equal(missingArgs.kind, "error");
    assert.equal(missingArgs.tool_id, "gee.gear.invoke");
    assert.equal(missingArgs.code, "gear.args.url");
    assert.match(missingArgs.message, /required string `url` is missing/);
  });

  it("does not run native Gear fallback when the SDK runtime is not live", async () => {
    const configDir = await tempConfigDir();
    const previousKey = process.env.XENODIA_API_KEY;
    delete process.env.XENODIA_API_KEY;
    try {
      const raw = await handleNativeRuntimeCommand(
        "submit-workspace-message",
        ["show video files in the media library"],
        { configDir },
      );
      const snapshot = JSON.parse(raw);
      assert.equal(snapshot.last_request_outcome.kind, "chat_reply");
      assert.equal(snapshot.host_action_intents.length, 0);
      assert.equal(snapshot.chat_runtime.status, "needs_setup");
      assert.equal(snapshot.last_run_state.stop_reason, "sdk_runtime_not_live");
      assert.match(snapshot.last_run_state.detail, /stopped before executing tools or Gear actions/);
      assert.equal(
        snapshot.transcript_events.some(
          (event: { payload?: { kind?: string } }) =>
            event.payload?.kind === "tool_invocation",
        ),
        false,
      );
      const latest = snapshot.active_conversation.messages.at(-1);
      assert.equal(latest.role, "assistant");
      assert.match(latest.content, /SDK runtime is not live/);
    } finally {
      if (previousKey === undefined) {
        delete process.env.XENODIA_API_KEY;
      } else {
        process.env.XENODIA_API_KEY = previousKey;
      }
    }
  });

  it("marks legacy static fallback completions failed instead of presenting them as complete", async () => {
    const configDir = await tempConfigDir();
    const store = defaultRuntimeStore("2026-04-27T00:00:00.000Z");
    const cursor = beginTurnReplay(store, "cli_workspace_chat", "show video files in media library");
    store.host_action_runs = [
      {
        host_action_id: "legacy_static_action",
        run_id: cursor.runId,
        tool_id: "gee.gear.invoke",
        source: "static_fallback",
        session_id: cursor.sessionId,
        conversation_id: store.active_conversation_id,
        user_message_id: cursor.userMessageId,
        status: "pending",
        created_at: "2026-04-27T00:00:00.000Z",
        updated_at: "2026-04-27T00:00:00.000Z",
      },
    ];
    store.host_action_intents = [
      {
        host_action_id: "legacy_static_action",
        tool_id: "gee.gear.invoke",
        arguments: {
          gear_id: "media.library",
          capability_id: "media.filter",
          args: { kind: "video" },
        },
      },
    ];
    await mkdir(configDir, { recursive: true });
    await writeFile(join(configDir, "runtime-store.json"), JSON.stringify(store, null, 2), "utf8");

    const completedRaw = await handleNativeRuntimeCommand(
      "complete-host-action-turn",
      [
        JSON.stringify([
          {
            host_action_id: "legacy_static_action",
            tool_id: "gee.gear.invoke",
            status: "succeeded",
            summary: "gee.gear.invoke completed",
          },
        ]),
      ],
      { configDir },
    );
    const completed = JSON.parse(completedRaw);

    assert.equal(completed.last_run_state.status, "failed");
    assert.equal(
      completed.last_run_state.stop_reason,
      "legacy_static_gear_fallback_prohibited",
    );
    assert.match(
      completed.active_conversation.messages.at(-1).content,
      /fallback execution is now prohibited/i,
    );
  });

  it("marks live SDK host-action completions failed when the same run is gone", async () => {
    const configDir = await tempConfigDir();
    const previousKey = process.env.XENODIA_API_KEY;
    process.env.XENODIA_API_KEY = "test-live-key";
    const store = defaultRuntimeStore("2026-04-27T00:00:00.000Z");
    const cursor = beginTurnReplay(store, "cli_workspace_chat", "show video files");
    appendToolEvents(store, cursor.sessionId, cursor.userMessageId, [
      {
        kind: "invocation",
        invocation_id: "host_action_lost_session",
        tool_name: "gear_invoke",
        input_summary: "{\"gear_id\":\"media.library\"}",
      },
    ]);
    store.chat_runtime = {
      status: "live",
      active_provider: "sdk/xenodia",
      detail: "The SDK is driving the agent loop through the local Xenodia model gateway.",
    };
    store.last_run_state = {
      conversation_id: store.active_conversation_id,
      status: "running",
      stop_reason: "gear_host_action_running",
      detail: "Waiting on host action.",
      resumable: false,
      task_id: null,
      module_run_id: null,
    };
    store.host_action_intents = [
      {
        host_action_id: "host_action_lost_session",
        tool_id: "gee.gear.invoke",
        arguments: {
          gear_id: "media.library",
          capability_id: "media.filter",
          args: { kind: "video" },
        },
      },
    ];
    await writeFile(join(configDir, "runtime-store.json"), JSON.stringify(store, null, 2), "utf8");

    try {
      const completedRaw = await handleNativeRuntimeCommand(
        "complete-host-action-turn",
        [
          JSON.stringify([
            {
              host_action_id: "host_action_lost_session",
              tool_id: "gee.gear.invoke",
              status: "succeeded",
              summary: "Applied video filter",
            },
          ]),
        ],
        { configDir },
      );
      const completed = JSON.parse(completedRaw);
      const persisted = JSON.parse(await readFile(join(configDir, "runtime-store.json"), "utf8"));

      assert.equal(completed.last_run_state.status, "failed");
      assert.equal(completed.last_run_state.stop_reason, "sdk_host_action_session_lost");
      assert.equal(persisted.chat_runtime.status, "degraded");
      assert.match(
        completed.active_conversation.messages.at(-1).content,
        /same SDK run could not be resumed/i,
      );
      assert.doesNotMatch(
        completed.active_conversation.messages.at(-1).content,
        /gear-completion|Xenodia did not complete/i,
      );
    } finally {
      if (previousKey === undefined) {
        delete process.env.XENODIA_API_KEY;
      } else {
        process.env.XENODIA_API_KEY = previousKey;
      }
    }
  });

  it("uses SDK host-action lineage when last run state looks like static fallback", async () => {
    const configDir = await tempConfigDir();
    const previousKey = process.env.XENODIA_API_KEY;
    process.env.XENODIA_API_KEY = "test-live-key";
    const store = defaultRuntimeStore("2026-04-27T00:00:00.000Z");
    const cursor = beginTurnReplay(store, "cli_workspace_chat", "show video files");
    appendToolEvents(store, cursor.sessionId, cursor.userMessageId, [
      {
        kind: "invocation",
        invocation_id: "host_action_sdk_lineage",
        tool_name: "gear_invoke",
        input_summary: "{\"gear_id\":\"media.library\"}",
      },
    ]);
    store.chat_runtime = {
      status: "live",
      active_provider: "sdk/xenodia",
      detail: "The SDK is driving the agent loop through the local Xenodia model gateway.",
    };
    store.last_run_state = {
      conversation_id: store.active_conversation_id,
      status: "running",
      stop_reason: "static_gear_fallback_running",
      detail: "A stale fallback state should not override the host-action run source.",
      resumable: false,
      task_id: null,
      module_run_id: null,
    };
    store.host_action_intents = [
      {
        host_action_id: "host_action_sdk_lineage",
        tool_id: "gee.gear.invoke",
        arguments: {
          gear_id: "media.library",
          capability_id: "media.filter",
          args: { kind: "video" },
        },
      },
    ];
    store.host_action_runs = [
      {
        host_action_id: "host_action_sdk_lineage",
        run_id: cursor.runId,
        tool_id: "gee.gear.invoke",
        session_id: cursor.sessionId,
        conversation_id: store.active_conversation_id,
        user_message_id: cursor.userMessageId,
        source: "sdk_same_run",
        status: "pending",
        created_at: "2026-04-27T00:00:00.000Z",
        updated_at: "2026-04-27T00:00:00.000Z",
      },
    ];
    await writeFile(join(configDir, "runtime-store.json"), JSON.stringify(store, null, 2), "utf8");

    try {
      const completedRaw = await handleNativeRuntimeCommand(
        "complete-host-action-turn",
        [
          JSON.stringify([
            {
              host_action_id: "host_action_sdk_lineage",
              tool_id: "gee.gear.invoke",
              status: "succeeded",
              summary: "Applied video filter",
            },
          ]),
        ],
        { configDir },
      );
      const completed = JSON.parse(completedRaw);
      const persisted = JSON.parse(await readFile(join(configDir, "runtime-store.json"), "utf8"));

      assert.equal(completed.last_run_state.stop_reason, "sdk_host_action_session_lost");
      assert.equal(persisted.chat_runtime.status, "degraded");
      assert.match(
        completed.active_conversation.messages.at(-1).content,
        /same SDK run could not be resumed/i,
      );
    } finally {
      if (previousKey === undefined) {
        delete process.env.XENODIA_API_KEY;
      } else {
        process.env.XENODIA_API_KEY = previousKey;
      }
    }
  });

  it("parses media-library kind filters into candidate host actions", () => {
    const routed = routeLocalGearIntent("media library only show video files");
    assert.ok(routed);
    assert.equal(routed.hostActions.length, 2);
    assert.deepEqual(routed.hostActions[0].arguments, { gear_id: "media.library" });
    assert.deepEqual(routed.hostActions[1].arguments, {
      gear_id: "media.library",
      capability_id: "media.filter",
      args: { kind: "video" },
    });
  });

  it("parses media-browser extension filters to the media library candidate action", () => {
    const routed = routeLocalGearIntent("show png image files in the media browser");
    assert.ok(routed);
    assert.equal(routed.hostActions.length, 2);
    assert.deepEqual(routed.hostActions[0].arguments, { gear_id: "media.library" });
    assert.equal(routed.hostActions[1].tool_id, "gee.gear.invoke");
    assert.deepEqual(routed.hostActions[1].arguments, {
      gear_id: "media.library",
      capability_id: "media.filter",
      args: { kind: "image", extensions: ["png"] },
    });
  });

  it("routes media-library local file imports into the import capability", () => {
    const routed = routeLocalGearIntent(
      "import /tmp/geeagent-demo/sample.png and /tmp/geeagent-demo/clip.mp4 into the media browser",
    );
    assert.ok(routed);
    assert.equal(routed.hostActions.length, 2);
    assert.deepEqual(routed.hostActions[0].arguments, { gear_id: "media.library" });
    assert.deepEqual(routed.hostActions[1].arguments, {
      gear_id: "media.library",
      capability_id: "media.import_files",
      args: { paths: ["/tmp/geeagent-demo/sample.png", "/tmp/geeagent-demo/clip.mp4"] },
    });
  });

  it("does not treat media-library import prompts without paths as filters", () => {
    assert.equal(routeLocalGearIntent("import png image files into the media library"), null);
    assert.equal(requiresGeeGearBridgeFirst("import files into the media browser"), true);
  });

  it("parses simple Twitter capture requests into candidate Gear host actions", () => {
    const routed = routeLocalGearIntent("fetch the first 12 tweets from @openai on twitter");
    assert.ok(routed);
    assert.equal(routed.hostActions.length, 2);
    assert.deepEqual(routed.hostActions[0].arguments, { gear_id: "twitter.capture" });
    assert.deepEqual(routed.hostActions[1].arguments, {
      gear_id: "twitter.capture",
      capability_id: "twitter.fetch_user",
      args: { username: "openai", limit: 12 },
    });
  });

  it("parses WeChat album capture requests into WeSpy candidate actions", () => {
    const url = "https://mp.weixin.qq.com/mp/appmsgalbum?__biz=MzU4MTQ4ODgyNg==&action=getalbum&album_id=2851824524055543812&scene=126#wechat_redirect";
    const routed = routeLocalGearIntent(`${url} fetch the first 3 articles and save them as desktop markdown`);
    assert.ok(routed);
    assert.equal(routed.hostActions.length, 2);
    assert.deepEqual(routed.hostActions[0].arguments, { gear_id: "wespy.reader" });
    const invokeArgs = routed.hostActions[1].arguments as {
      gear_id: string;
      capability_id: string;
      args: Record<string, unknown>;
    };
    assert.equal(invokeArgs.gear_id, "wespy.reader");
    assert.equal(invokeArgs.capability_id, "wespy.fetch_album");
    assert.equal(invokeArgs.args.url, url);
    assert.equal(invokeArgs.args.max_articles, 3);
    assert.equal(invokeArgs.args.export_markdown, true);
    assert.equal(invokeArgs.args.export_markdown_path, undefined);
  });

  it("routes WeChat album list requests into the WeSpy list capability", () => {
    const url = "https://mp.weixin.qq.com/mp/appmsgalbum?album_id=123";
    const routed = routeLocalGearIntent(`list this album links ${url}`);
    assert.ok(routed);
    assert.deepEqual(routed.hostActions[1].arguments, {
      gear_id: "wespy.reader",
      capability_id: "wespy.list_album",
      args: { url, max_articles: 10 },
    });
  });

  it("routes WeChat article requests into the WeSpy article capability", () => {
    const url = "https://mp.weixin.qq.com/s/Yf6yrOEILghuYGgioulNVA";
    const routed = routeLocalGearIntent(`fetch the full article and summarize the main points ${url}`);
    assert.ok(routed);
    assert.deepEqual(routed.hostActions[1].arguments, {
      gear_id: "wespy.reader",
      capability_id: "wespy.fetch_article",
      args: { url },
    });
  });

  it("routes query-style WeChat article URLs into the WeSpy article capability", () => {
    const url = "https://mp.weixin.qq.com/s?__biz=MzU4MTQ4ODgyNg==&mid=2247493744&idx=1";
    const routed = routeLocalGearIntent(`read this WeChat article ${url}`);
    assert.ok(routed);
    assert.deepEqual(routed.hostActions[1].arguments, {
      gear_id: "wespy.reader",
      capability_id: "wespy.fetch_article",
      args: { url },
    });
  });

  it("routes WeChat save/capture prompts to WeSpy instead of Bookmark Vault", () => {
    const url = "https://mp.weixin.qq.com/mp/appmsgalbum?album_id=123";
    const routed = routeLocalGearIntent(`save this WeChat album to desktop markdown ${url}`);
    assert.ok(routed);
    assert.deepEqual(routed.hostActions[1].arguments, {
      gear_id: "wespy.reader",
      capability_id: "wespy.fetch_album",
      args: { url, max_articles: 10, export_markdown: true },
    });
  });

  it("parses bookmark save requests into Bookmark Vault candidate actions", () => {
    const routed = routeLocalGearIntent("bookmark this video https://example.com/watch?v=demo");
    assert.ok(routed);
    assert.equal(routed.hostActions.length, 2);
    assert.deepEqual(routed.hostActions[0].arguments, { gear_id: "bookmark.vault" });
    assert.deepEqual(routed.hostActions[1].arguments, {
      gear_id: "bookmark.vault",
      capability_id: "bookmark.save",
      args: { content: "video https://example.com/watch?v=demo" },
    });
  });

  it("does not statically route composable info-capture requests for Twitter status URLs", () => {
    const prompts = [
      "use info capture skill to save https://x.com/ai_artworkgen/status/2048471354773549393?s=20",
      "save this tweet https://x.com/ai_artworkgen/status/2048471354773549393?s=20",
      "bookmark this X post https://twitter.com/openai/status/2048471354773549393",
    ];

    for (const prompt of prompts) {
      assert.equal(routeLocalGearIntent(prompt), null);
    }
  });

  it("does not parse composable Twitter bookmark requests into partial local actions", () => {
    const routed = routeLocalGearIntent(
      "save this tweet as a bookmark https://x.com/ai_artworkgen/status/2048471354773549393?s=20",
    );

    assert.equal(routed, null);
  });

  it("marks composable Twitter bookmark media requests as Gear-bridge-first", () => {
    assert.equal(
      requiresGeeGearBridgeFirst(
        "save this tweet to bookmarks and import its media into the media browser https://x.com/0xbisc/status/2049100073481716076?s=20",
      ),
      true,
    );
    assert.equal(
      requiresGeeGearBridgeFirst(
        "save this tweet to bookmarks https://x.com/YaReYaRu30Life/status/2049545035176362120?s=20 and download its media into the media manager gear.",
      ),
      true,
    );
    assert.equal(
      routeLocalGearIntent(
        "save this tweet to bookmarks https://x.com/YaReYaRu30Life/status/2049545035176362120?s=20 and download its media into the media manager gear.",
      ),
      null,
    );
    assert.equal(
      requiresGeeGearBridgeFirst("use the generator with image-2, 3:4, 2k, prompt: macaron toy house style"),
      true,
    );
    assert.equal(requiresGeeGearBridgeFirst("explain image-2 parameters and limits"), false);
    assert.equal(requiresGeeGearBridgeFirst("how do I use image-2 to generate images?"), false);
    assert.equal(requiresGeeGearBridgeFirst("open the media generator"), true);
    assert.equal(
      routeLocalGearIntent("use the generator with image-2, 3:4, 2k, prompt: macaron toy house style"),
      null,
    );
    assert.equal(requiresGeeGearBridgeFirst("check whether local port 8080 is listening"), false);
  });

  it("selects adaptive planning modes without forcing every turn into a stage plan", () => {
    assert.deepEqual(
      selectRuntimePlanningMode("check whether local port 8080 is listening", "default"),
      {
        mode: "direct",
        boundary_mode: "default",
        reason: "ordinary SDK turn; no Gear-first runtime boundary was selected",
        should_create_run_plan: false,
      },
    );

    const light = selectRuntimePlanningMode("open the media library", "gear_first");
    assert.equal(light.mode, "light");
    assert.equal(light.should_create_run_plan, false);

    const generatorSurface = selectRuntimePlanningMode("open the media generator", "gear_first");
    assert.equal(generatorSurface.mode, "light");
    assert.equal(generatorSurface.should_create_run_plan, false);

    const modelInfo = selectRuntimePlanningMode("explain image-2 parameters and limits", "gear_first");
    assert.equal(modelInfo.mode, "light");
    assert.equal(modelInfo.should_create_run_plan, false);

    const usageQuestion = selectRuntimePlanningMode("how do I use image-2 to generate images?", "gear_first");
    assert.equal(usageQuestion.mode, "light");
    assert.equal(usageQuestion.should_create_run_plan, false);

    const bookmarkOnly = selectRuntimePlanningMode(
      "save this tweet to bookmarks https://x.com/demo/status/123",
      "gear_first",
    );
    assert.equal(bookmarkOnly.mode, "structured");
    assert.equal(bookmarkOnly.should_create_run_plan, true);

    const structured = selectRuntimePlanningMode(
      "save this tweet to bookmarks https://x.com/YaReYaRu30Life/status/2049545035176362120?s=20, download its media into the media manager gear, then search related information and explain the technology.",
      "gear_first",
    );
    assert.equal(structured.mode, "structured");
    assert.equal(structured.should_create_run_plan, true);
    assert.ok(
      buildRuntimeRunPlan(
        "save this tweet to bookmarks https://x.com/YaReYaRu30Life/status/2049545035176362120?s=20, download its media into the media manager gear, then search related information and explain the technology.",
        "gear_first",
      ),
    );

    const generation = selectRuntimePlanningMode(
      "use the generator with image-2, 3:4, 2k, prompt: macaron toy house style",
      "gear_first",
    );
    assert.equal(generation.mode, "structured");
    assert.equal(generation.should_create_run_plan, true);
  });

  it("prepends a strict first Gear MCP call boundary for Gear-first turns", () => {
    const prompt = __sdkTurnRunnerTestHooks.gearFirstTurnPrompt(
      "Previous transcript said the bridge was missing.\n\n[GeeAgent Turn]\nsave this tweet as a bookmark https://x.com/demo/status/123",
    );

    assert.match(prompt, /Your first assistant action.*mcp__gee__gear_list_capabilities/s);
    assert.match(prompt, /Do not write prose before that first Gee MCP tool call/);
    assert.match(prompt, /Do not infer Gee bridge availability from previous transcript/);
    assert.match(prompt, /\[Original Turn Prompt\]/);
  });

  it("builds a focused Phase 3.6 plan for Twitter bookmark media requests", () => {
    const plan = buildRuntimeRunPlan(
      "save this tweet to bookmarks and import the tweet media into the media browser https://x.com/0xbisc/status/2049100073481716076?s=20",
      "gear_first",
    );

    assert.ok(plan);
    assert.equal(plan.phase, "phase3.6");
    assert.equal(plan.planning_mode, "structured");
    assert.equal(plan.current_stage_id, "stage_fetch_tweet");
    assert.deepEqual(plan.focus.focus_gear_ids, ["twitter.capture"]);
    assert.deepEqual(plan.focus.focus_capability_ids, ["twitter.fetch_tweet"]);
    assert.deepEqual(
      plan.stages[0]?.capability_args?.["twitter.capture/twitter.fetch_tweet"],
      { url: "https://x.com/0xbisc/status/2049100073481716076?s=20" },
    );
    assert.deepEqual(capabilityFocusForStage(plan, "stage_download_media"), {
      stage_id: "stage_download_media",
      focus_gear_ids: ["smartyt.media"],
      focus_capability_ids: ["smartyt.download_now"],
      disclosure_level: "summary",
    });
    assert.deepEqual(capabilityFocusForStage(plan, "stage_import_media"), {
      stage_id: "stage_import_media",
      focus_gear_ids: ["media.library"],
      focus_capability_ids: ["media.import_files"],
      disclosure_level: "summary",
    });
    assert.ok(plan.stages.some((stage) => stage.stage_id === "stage_import_media"));
    assert.ok(plan.success_criteria.some((item) => /Bookmark Vault/.test(item)));
  });

  it("builds a focused Phase 3.6 plan for Media Generator image requests", () => {
    const plan = buildRuntimeRunPlan(
      [
        "use the generator with image-2, 3:4, 2k, prompt:",
        "Overall visual tone: macaron toy house and soft candy picture-book style.",
      ].join("\n"),
      "gear_first",
    );

    assert.ok(plan);
    assert.equal(plan.phase, "phase3.6");
    assert.equal(plan.current_stage_id, "stage_create_media_generation_task");
    assert.deepEqual(plan.focus.focus_gear_ids, ["media.generator"]);
    assert.deepEqual(plan.focus.focus_capability_ids, ["media_generator.create_task"]);
    assert.deepEqual(
      plan.stages[0]?.capability_args?.["media.generator/media_generator.create_task"],
      {
        category: "image",
        model: "gpt-image-2",
        prompt: "Overall visual tone: macaron toy house and soft candy picture-book style.",
        aspect_ratio: "3:4",
        resolution: "2K",
        response_format: "url",
        n: 1,
        async: true,
      },
    );
    assert.deepEqual(capabilityFocusArgsForPlan(plan), {
      detail: "summary",
      run_plan_id: plan?.plan_id,
      stage_id: "stage_create_media_generation_task",
      focus_gear_ids: ["media.generator"],
      focus_capability_ids: ["media_generator.create_task"],
    });

    const modelInfoPlan = buildRuntimeRunPlan("explain image-2 parameters and limits", "gear_first");
    assert.notEqual(modelInfoPlan?.current_stage_id, "stage_create_media_generation_task");

    const usageQuestionPlan = buildRuntimeRunPlan("how do I use image-2 to generate images?", "gear_first");
    assert.notEqual(usageQuestionPlan?.current_stage_id, "stage_create_media_generation_task");

    const batchPlan = buildRuntimeRunPlan("use the generator to generate 4 images, prompt: neon study room", "gear_first");
    assert.equal(
      batchPlan?.stages[0]?.capability_args?.["media.generator/media_generator.create_task"]
        ?.batch_count,
      4,
    );
  });

  it("adds research and synthesis stages for cross-domain Twitter requests", () => {
    const plan = buildRuntimeRunPlan(
      "save this tweet to bookmarks https://x.com/YaReYaRu30Life/status/2049545035176362120?s=20, download its media into the media library gear, then search related information and explain the technologies involved.",
      "gear_first",
    );

    assert.ok(plan);
    assert.deepEqual(
      plan.stages.map((stage) => stage.stage_id),
      [
        "stage_fetch_tweet",
        "stage_download_media",
        "stage_import_media",
        "stage_save_bookmark",
        "stage_research_technologies",
        "stage_synthesize_explanation",
        "stage_verify",
      ],
    );
    assert.ok(plan.success_criteria.some((item) => /current public information/.test(item)));
    assert.equal(
      capabilityFocusForStage(plan, "stage_research_technologies").focus_capability_ids.length,
      0,
    );
    assert.deepEqual(
      __sdkTurnRunnerTestHooks.normalizeSdkGearInvokeInput(
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
        args: {
          url: "https://x.com/YaReYaRu30Life/status/2049545035176362120?s=20",
        },
      },
    );
  });

  it("renders Gear-first prompts with a locked capability focus set", () => {
    const plan = buildRuntimeRunPlan(
      "save this tweet to bookmarks and import its media into the media browser https://x.com/0xbisc/status/2049100073481716076?s=20",
      "gear_first",
    );
    const prompt = __sdkTurnRunnerTestHooks.gearFirstTurnPrompt("original prompt", plan);

    assert.match(prompt, /focus_gear_ids/);
    assert.match(prompt, /twitter\.fetch_tweet/);
    assert.match(prompt, /smartyt\.download_now/);
    assert.match(prompt, /capability_args/);
    assert.match(prompt, /pass those fields inside the direct Gear `args` object/);
    assert.match(prompt, /Do not request an unscoped full capability summary/);
    assert.deepEqual(capabilityFocusArgsForPlan(plan), {
      detail: "summary",
      run_plan_id: plan?.plan_id,
      stage_id: "stage_fetch_tweet",
      focus_gear_ids: ["twitter.capture"],
      focus_capability_ids: ["twitter.fetch_tweet"],
    });
    assert.deepEqual(capabilityFocusArgsForPlan(plan, "stage_save_bookmark"), {
      detail: "summary",
      run_plan_id: plan?.plan_id,
      stage_id: "stage_save_bookmark",
      focus_gear_ids: ["bookmark.vault"],
      focus_capability_ids: ["bookmark.save"],
    });
  });

  it("rejects unscoped Gear capability summary calls when a focus set is locked", () => {
    const plan = buildRuntimeRunPlan(
      "save this tweet to bookmarks and import its media into the media browser https://x.com/0xbisc/status/2049100073481716076?s=20",
      "gear_first",
    );
    assert.ok(plan);

    assert.match(
      __sdkTurnRunnerTestHooks.gearFirstCapabilityFocusViolationReason(
        "gear_first",
        "mcp__gee__gear_list_capabilities",
        { detail: "summary" },
        plan,
        true,
      ) ?? "",
      /must include the runtime plan focus/,
    );
    assert.equal(
      __sdkTurnRunnerTestHooks.gearFirstCapabilityFocusViolationReason(
        "gear_first",
        "mcp__gee__gear_list_capabilities",
        capabilityFocusArgsForPlan(plan),
        plan,
        true,
      ),
      null,
    );
    assert.match(
      __sdkTurnRunnerTestHooks.gearFirstCapabilityFocusViolationReason(
        "gear_first",
        "mcp__gee__gear_list_capabilities",
        capabilityFocusArgsForPlan(plan, "stage_download_media"),
        plan,
        true,
      ) ?? "",
      /must include the runtime plan focus/,
    );
    assert.equal(
      __sdkTurnRunnerTestHooks.gearFirstCapabilityFocusViolationReason(
        "gear_first",
        "mcp__gee__gear_list_capabilities",
        capabilityFocusArgsForPlan(plan, "stage_download_media"),
        plan,
        false,
      ),
      null,
    );
    assert.match(
      __sdkTurnRunnerTestHooks.gearFirstCapabilityFocusViolationReason(
        "gear_first",
        "mcp__gee__gear_list_capabilities",
        {
          ...capabilityFocusArgsForPlan(plan),
          stage_id: "stage_unknown",
        },
        plan,
        false,
      ) ?? "",
      /blocked an unscoped full capability summary/,
    );
    assert.match(
      __sdkTurnRunnerTestHooks.gearFirstCapabilityFocusViolationReason(
        "gear_first",
        "mcp__gee__gear_list_capabilities",
        { detail: "summary" },
        plan,
        false,
      ) ?? "",
      /blocked an unscoped full capability summary/,
    );
    assert.equal(
      __sdkTurnRunnerTestHooks.gearFirstCapabilityFocusViolationReason(
        "gear_first",
        "mcp__gee__gear_list_capabilities",
        { detail: "capabilities", gear_id: "twitter.capture" },
        plan,
        false,
      ),
      null,
    );
  });

  it("records Phase 3.6 plan, focus, stage start, and stage conclusion events", () => {
    const store = defaultRuntimeStore("2026-04-30T00:00:00.000Z");
    const sessionId = executionSessionIdForConversation(store.active_conversation_id);
    const plan = buildRuntimeRunPlan(
      "save this tweet to bookmarks and import its media into the media browser https://x.com/0xbisc/status/2049100073481716076?s=20",
      "gear_first",
    );
    assert.ok(plan);

    appendRunPlanForSession(store, sessionId, plan);
    appendCapabilityFocusForSession(store, sessionId, plan);
    appendStageStartedForSession(store, sessionId, plan);
    appendStageConclusionForSession(
      store,
      sessionId,
      plan,
      "completed",
      "Stage completed by test.",
    );

    const kinds = store.transcript_events.map((event) => event.payload.kind);
    assert.deepEqual(kinds, [
      "run_plan_created",
      "capability_focus_locked",
      "stage_started",
      "stage_concluded",
    ]);
    const focusEvent = store.transcript_events[1]?.payload;
    assert.deepEqual(focusEvent.focus_capability_ids, ["twitter.fetch_tweet"]);
    const conclusion = store.transcript_events[3]?.payload;
    assert.equal(conclusion.stage_id, "stage_fetch_tweet");
    assert.equal(conclusion.status, "completed");
  });

  it("advances Phase 3.6 stages from structured Gear completion results", () => {
    const plan = buildRuntimeRunPlan(
      "save this tweet to bookmarks and import its media into the media browser https://x.com/0xbisc/status/2049100073481716076?s=20",
      "gear_first",
    );
    assert.ok(plan);

    const decision = advanceRunPlanAfterHostCompletions(plan, [
      {
        host_action_id: "host_action_fetch",
        tool_id: "gee.gear.invoke",
        status: "succeeded",
        summary: "twitter.capture twitter.fetch_tweet completed",
        result_json: JSON.stringify({
          gear_id: "twitter.capture",
          capability_id: "twitter.fetch_tweet",
          tweet_count: 1,
        }),
      },
    ]);

    assert.equal(decision.concluded, true);
    assert.equal(decision.status, "completed");
    assert.equal(decision.nextPlan?.current_stage_id, "stage_download_media");
    assert.match(terminalRunPlanBlocker(decision.nextPlan!) ?? "", /smartyt\.media\/smartyt\.download_now/);
  });

  it("does not advance Phase 3.6 stages from summary-only Gear completion prose", () => {
    const plan = buildRuntimeRunPlan(
      "save this tweet to bookmarks and import its media into the media browser https://x.com/0xbisc/status/2049100073481716076?s=20",
      "gear_first",
    );
    assert.ok(plan);

    const decision = advanceRunPlanAfterHostCompletions(plan, [
      {
        host_action_id: "host_action_fetch",
        tool_id: "gee.gear.invoke",
        status: "succeeded",
        summary: "twitter.capture twitter.fetch_tweet completed",
      },
    ]);

    assert.equal(decision.concluded, false);
    assert.match(terminalRunPlanBlocker(plan) ?? "", /twitter\.capture\/twitter\.fetch_tweet/);
  });

  it("does not advance Phase 3.6 stages from Gear schema disclosure", () => {
    const plan = buildRuntimeRunPlan(
      "save this tweet to bookmarks and import its media into the media browser https://x.com/YaReYaRu30Life/status/2049545035176362120?s=20",
      "gear_first",
    );
    assert.ok(plan);

    const decision = advanceRunPlanAfterHostCompletions(plan, [
      {
        host_action_id: "host_action_schema",
        tool_id: "gee.gear.listCapabilities",
        status: "succeeded",
        summary: "twitter.capture twitter.fetch_tweet completed",
        result_json: JSON.stringify({
          disclosure_level: "schema",
          gear_id: "twitter.capture",
          capability_id: "twitter.fetch_tweet",
          args_schema: {
            type: "object",
            required: ["url"],
          },
        }),
      },
    ]);

    assert.equal(decision.concluded, false);
    assert.match(terminalRunPlanBlocker(plan) ?? "", /twitter\.capture\/twitter\.fetch_tweet/);
  });

  it("blocks Phase 3.6 stages from failed Gear completion results", () => {
    const plan = buildRuntimeRunPlan(
      "save this tweet to bookmarks and import its media into the media browser https://x.com/0xbisc/status/2049100073481716076?s=20",
      "gear_first",
    );
    assert.ok(plan);

    const decision = advanceRunPlanAfterHostCompletions(plan, [
      {
        host_action_id: "host_action_fetch",
        tool_id: "gee.gear.invoke",
        status: "failed",
        error: "twitter.capture is unauthorized",
      },
    ]);

    assert.equal(decision.concluded, true);
    assert.equal(decision.status, "blocked");
    assert.equal(decision.nextPlan, null);
    assert.match(decision.summary ?? "", /unauthorized/);
  });

  it("rejects non-Gee tool events inside Gear-bridge-first turns", async () => {
    const turn: SdkTurnResult = {
      assistant_chunks: [],
      tool_events: [],
      auto_approved_tools: 0,
    };
    let closed = false;
    const managed = {
      events: [
        {
          type: "session.tool_use",
          sessionId: "session_test",
          toolUseId: "toolu_bash",
          toolName: "Bash",
          input: { command: "pwd && ls" },
          raw: {},
        },
      ],
      waiters: [],
      session: {
        close() {
          closed = true;
        },
      },
      toolBoundaryMode: "gear_first",
    };

    await __sdkTurnRunnerTestHooks.collectEventsUntilPauseOrResult(
      undefined,
      managed as never,
      "session_test",
      [],
      turn,
      undefined,
      undefined,
      5_000,
      "gear_first",
    );

    assert.equal(closed, true);
    assert.match(turn.failed_reason ?? "", /Gear-first runtime boundary rejected `Bash`/);
    assert.equal(turn.tool_events.length, 0);
  });

  it("allows non-Gee tools after a Gear-first plan reaches a model-only stage", () => {
    let plan = buildRuntimeRunPlan(
      "save this tweet to bookmarks https://x.com/YaReYaRu30Life/status/2049545035176362120?s=20, download its media into the media library gear, then search related information and explain the technologies involved.",
      "gear_first",
    );
    assert.ok(plan);
    while (plan.current_stage_id !== "stage_research_technologies") {
      const nextPlan = nextRuntimeRunPlan(plan);
      assert.ok(nextPlan);
      plan = nextPlan;
    }

    assert.equal(
      __sdkTurnRunnerTestHooks.gearFirstBoundaryViolationReason("gear_first", "Bash", plan),
      null,
    );
  });

  it("accepts Gear-first final results after the plan reaches a model-only stage", async () => {
    let plan = buildRuntimeRunPlan(
      "save this tweet to bookmarks https://x.com/YaReYaRu30Life/status/2049545035176362120?s=20, download its media into the media library gear, then search related information and explain the technologies involved.",
      "gear_first",
    );
    assert.ok(plan);
    while (plan.current_stage_id !== "stage_research_technologies") {
      const nextPlan = nextRuntimeRunPlan(plan);
      assert.ok(nextPlan);
      plan = nextPlan;
    }

    const turn: SdkTurnResult = {
      assistant_chunks: [],
      tool_events: [],
      auto_approved_tools: 0,
    };
    let closed = false;
    const managed = {
      events: [
        {
          type: "session.tool_use",
          sessionId: "session_test",
          toolUseId: "toolu_research",
          toolName: "Bash",
          input: { command: "curl https://example.com" },
          raw: {},
        },
        {
          type: "session.tool_result",
          sessionId: "session_test",
          toolUseId: "toolu_research",
          status: "succeeded",
          summary: "research evidence",
          raw: {},
        },
        {
          type: "session.assistant_text",
          sessionId: "session_test",
          text: "Saved and explained.",
          raw: {},
        },
        {
          type: "session.result",
          sessionId: "session_test",
          subtype: "success",
          durationMs: 1000,
          totalCostUsd: 0,
          result: "Saved and explained.",
          raw: {},
        },
      ],
      waiters: [],
      session: {
        close() {
          closed = true;
        },
      },
      toolBoundaryMode: "gear_first",
      runPlan: plan,
      toolInvocationCount: 4,
    };

    await __sdkTurnRunnerTestHooks.collectEventsUntilPauseOrResult(
      undefined,
      managed as never,
      "session_test",
      [],
      turn,
      undefined,
      undefined,
      5_000,
      "gear_first",
      plan,
    );

    assert.equal(turn.failed_reason, undefined);
    assert.equal(turn.final_result, "Saved and explained.");
    assert.equal(turn.assistant_chunks.at(-1), "Saved and explained.");
    assert.equal(closed, false);
  });

  it("concludes model-only research, synthesis, and verification stages from SDK evidence", () => {
    let plan = buildRuntimeRunPlan(
      "save this tweet to bookmarks https://x.com/YaReYaRu30Life/status/2049545035176362120?s=20, download its media into the media library gear, then search related information and explain the technologies involved.",
      "gear_first",
    );
    assert.ok(plan);
    while (plan.current_stage_id !== "stage_research_technologies") {
      const nextPlan = nextRuntimeRunPlan(plan);
      assert.ok(nextPlan);
      plan = nextPlan;
    }
    const store = defaultRuntimeStore();
    const turn: SdkTurnResult = {
      assistant_chunks: ["Saved and explained."],
      auto_approved_tools: 1,
      tool_events: [
        {
          kind: "invocation",
          invocation_id: "toolu_research",
          tool_name: "Bash",
          input_summary: "curl search",
        },
        {
          kind: "result",
          invocation_id: "toolu_research",
          status: "succeeded",
          summary: "research evidence",
        },
      ],
    };

    const finalPlan = __turnTestHooks.applyModelOnlyStageConclusionsForTurn(
      store,
      "session_research",
      plan,
      turn,
    );

    assert.equal(finalPlan, null);
    assert.deepEqual(
      store.transcript_events
        .map((event) => (event as { payload?: { kind?: string; stage_id?: string; status?: string } }).payload)
        .filter((payload) => payload?.kind === "stage_concluded")
        .map((payload) => [payload?.stage_id, payload?.status]),
      [
        ["stage_research_technologies", "completed"],
        ["stage_synthesize_explanation", "completed"],
        ["stage_verify", "completed"],
      ],
    );
  });

  it("rejects Gear-first runs that invoke before focused capability discovery", async () => {
    const turn: SdkTurnResult = {
      assistant_chunks: [],
      tool_events: [],
      auto_approved_tools: 0,
    };
    let closed = false;
    const managed = {
      events: [
        {
          type: "session.tool_use",
          sessionId: "session_test",
          toolUseId: "toolu_invoke_first",
          toolName: "mcp__gee__gear_invoke",
          input: {
            gear_id: "twitter.capture",
            capability_id: "twitter.fetch_tweet",
            args: { url: "https://x.com/openai/status/123" },
          },
          raw: {},
        },
      ],
      waiters: [],
      session: {
        close() {
          closed = true;
        },
      },
      toolBoundaryMode: "gear_first",
    };

    await __sdkTurnRunnerTestHooks.collectEventsUntilPauseOrResult(
      undefined,
      managed as never,
      "session_test",
      [],
      turn,
      undefined,
      undefined,
      5_000,
      "gear_first",
    );

    assert.equal(closed, true);
    assert.match(turn.failed_reason ?? "", /first Gear-first action must be focused capability discovery/i);
    assert.equal(turn.tool_events.length, 0);
  });

  it("rejects focused Gear-first runs that start with an unscoped summary", async () => {
    const plan = buildRuntimeRunPlan(
      "save this tweet to bookmarks and import its media into the media browser https://x.com/0xbisc/status/2049100073481716076?s=20",
      "gear_first",
    );
    assert.ok(plan);
    const turn: SdkTurnResult = {
      assistant_chunks: [],
      tool_events: [],
      auto_approved_tools: 0,
    };
    let closed = false;
    const managed = {
      events: [
        {
          type: "session.tool_use",
          sessionId: "session_test",
          toolUseId: "toolu_unscoped",
          toolName: "mcp__gee__gear_list_capabilities",
          input: { detail: "summary" },
          raw: {},
        },
      ],
      waiters: [],
      session: {
        close() {
          closed = true;
        },
      },
      toolBoundaryMode: "gear_first",
      runPlan: plan,
    };

    await __sdkTurnRunnerTestHooks.collectEventsUntilPauseOrResult(
      undefined,
      managed as never,
      "session_test",
      [],
      turn,
      undefined,
      undefined,
      5_000,
      "gear_first",
      plan,
    );

    assert.equal(closed, true);
    assert.match(turn.failed_reason ?? "", /must include the runtime plan focus/);
    assert.equal(turn.tool_events.length, 0);
  });

  it("allows Gear-first invokes for the current runtime plan stage", async () => {
    const plan = buildRuntimeRunPlan(
      "save this tweet to bookmarks and import its media into the media browser https://x.com/0xbisc/status/2049100073481716076?s=20",
      "gear_first",
    );
    assert.ok(plan);
    const turn: SdkTurnResult = {
      assistant_chunks: [],
      tool_events: [],
      auto_approved_tools: 0,
    };
    let closed = false;
    const managed = {
      events: [
        {
          type: "session.tool_use",
          sessionId: "session_test",
          toolUseId: "toolu_fetch",
          toolName: "mcp__gee__gear_invoke",
          input: {
            gear_id: "twitter.capture",
            capability_id: "twitter.fetch_tweet",
            args: { url: "https://x.com/0xbisc/status/2049100073481716076?s=20" },
          },
          raw: {},
        },
        {
          type: "session.host_action_requested",
          sessionId: "session_test",
          hostAction: {
            host_action_id: "host_action_fetch",
            tool_id: "gee.gear.invoke",
            arguments: {
              gear_id: "twitter.capture",
              capability_id: "twitter.fetch_tweet",
              args: { url: "https://x.com/0xbisc/status/2049100073481716076?s=20" },
            },
          },
        },
      ],
      waiters: [],
      session: {
        close() {
          closed = true;
        },
      },
      toolBoundaryMode: "gear_first",
      runPlan: plan,
      toolInvocationCount: 1,
    };

    await __sdkTurnRunnerTestHooks.collectEventsUntilPauseOrResult(
      undefined,
      managed as never,
      "session_test",
      [],
      turn,
      undefined,
      undefined,
      5_000,
      "gear_first",
      plan,
    );

    assert.equal(closed, false);
    assert.equal(turn.failed_reason, undefined);
    assert.equal(turn.pending_host_actions?.[0]?.host_action_id, "host_action_fetch");
  });

  it("rejects Gear-first invokes outside the current runtime plan stage", async () => {
    const plan = buildRuntimeRunPlan(
      "save this tweet to bookmarks and import its media into the media browser https://x.com/0xbisc/status/2049100073481716076?s=20",
      "gear_first",
    );
    assert.ok(plan);
    const turn: SdkTurnResult = {
      assistant_chunks: [],
      tool_events: [],
      auto_approved_tools: 0,
    };
    let closed = false;
    const managed = {
      events: [
        {
          type: "session.tool_use",
          sessionId: "session_test",
          toolUseId: "toolu_out_of_stage",
          toolName: "mcp__gee__gear_invoke",
          input: {
            gear_id: "bookmark.vault",
            capability_id: "bookmark.save",
            args: { url: "https://x.com/0xbisc/status/2049100073481716076?s=20" },
          },
          raw: {},
        },
      ],
      waiters: [],
      session: {
        close() {
          closed = true;
        },
      },
      toolBoundaryMode: "gear_first",
      runPlan: plan,
      toolInvocationCount: 1,
    };

    await __sdkTurnRunnerTestHooks.collectEventsUntilPauseOrResult(
      undefined,
      managed as never,
      "session_test",
      [],
      turn,
      undefined,
      undefined,
      5_000,
      "gear_first",
      plan,
    );

    assert.equal(closed, true);
    assert.match(turn.failed_reason ?? "", /current stage only allows required capability/);
    assert.equal(turn.tool_events.length, 0);
  });

  it("does not treat a resumed Gear-first tool call as the first tool of the whole run", async () => {
    const plan = buildRuntimeRunPlan(
      "save this tweet to bookmarks and import its media into the media browser https://x.com/0xbisc/status/2049100073481716076?s=20",
      "gear_first",
    );
    assert.ok(plan);
    let closed = false;
    const managed = {
      events: [
        {
          type: "session.tool_use",
          sessionId: "session_test",
          toolUseId: "toolu_first_focus",
          toolName: "mcp__gee__gear_list_capabilities",
          input: capabilityFocusArgsForPlan(plan),
          raw: {},
        },
        {
          type: "session.host_action_requested",
          sessionId: "session_test",
          hostAction: {
            host_action_id: "host_action_first_focus",
            tool_id: "gee.gear.listCapabilities",
            arguments: capabilityFocusArgsForPlan(plan),
          },
        },
      ],
      waiters: [],
      session: {
        close() {
          closed = true;
        },
      },
      toolBoundaryMode: "gear_first",
      runPlan: plan,
      toolInvocationCount: 0,
    };
    const firstTurn: SdkTurnResult = {
      assistant_chunks: [],
      tool_events: [],
      auto_approved_tools: 0,
    };

    await __sdkTurnRunnerTestHooks.collectEventsUntilPauseOrResult(
      undefined,
      managed as never,
      "session_test",
      [],
      firstTurn,
      undefined,
      undefined,
      5_000,
      "gear_first",
      plan,
    );

    assert.equal(firstTurn.failed_reason, undefined);
    assert.equal(firstTurn.pending_host_actions?.[0]?.host_action_id, "host_action_first_focus");
    assert.equal(managed.toolInvocationCount, 1);

    managed.events = [
      {
        type: "session.tool_use",
        sessionId: "session_test",
        toolUseId: "toolu_second_focus",
        toolName: "mcp__gee__gear_list_capabilities",
        input: capabilityFocusArgsForPlan(plan, "stage_download_media"),
        raw: {},
      },
      {
        type: "session.host_action_requested",
        sessionId: "session_test",
        hostAction: {
          host_action_id: "host_action_second_focus",
          tool_id: "gee.gear.listCapabilities",
          arguments: capabilityFocusArgsForPlan(plan, "stage_download_media"),
        },
      },
    ];
    const secondTurn: SdkTurnResult = {
      assistant_chunks: [],
      tool_events: [],
      auto_approved_tools: 0,
    };

    await __sdkTurnRunnerTestHooks.collectEventsUntilPauseOrResult(
      undefined,
      managed as never,
      "session_test",
      [],
      secondTurn,
      undefined,
      undefined,
      5_000,
      "gear_first",
      plan,
    );

    assert.equal(closed, false);
    assert.equal(secondTurn.failed_reason, undefined);
    assert.equal(secondTurn.pending_host_actions?.[0]?.host_action_id, "host_action_second_focus");
    assert.equal(managed.toolInvocationCount, 2);

    managed.events = [
      {
        type: "session.tool_use",
        sessionId: "session_test",
        toolUseId: "toolu_bash_after_resume",
        toolName: "Bash",
        input: { command: "cat /tmp/result.json" },
        raw: {},
      },
    ];
    const thirdTurn: SdkTurnResult = {
      assistant_chunks: [],
      tool_events: [],
      auto_approved_tools: 0,
    };

    await __sdkTurnRunnerTestHooks.collectEventsUntilPauseOrResult(
      undefined,
      managed as never,
      "session_test",
      [],
      thirdTurn,
      undefined,
      undefined,
      5_000,
      "gear_first",
      plan,
    );

    assert.equal(closed, true);
    assert.match(thirdTurn.failed_reason ?? "", /rejected `Bash`/);
  });

  it("marks Gear-bridge-first text-only turns failed instead of complete", async () => {
    const turn: SdkTurnResult = {
      assistant_chunks: [],
      tool_events: [],
      auto_approved_tools: 0,
    };
    let closed = false;
    const managed = {
      events: [
        {
          type: "session.assistant_text",
          sessionId: "session_test",
          text: "I cannot see the Gee Gear bridge.",
          raw: {},
        },
        {
          type: "session.result",
          sessionId: "session_test",
          subtype: "success",
          result: "I cannot see the Gee Gear bridge.",
          raw: { is_error: false },
        },
      ],
      waiters: [],
      session: {
        close() {
          closed = true;
        },
      },
      toolBoundaryMode: "gear_first",
    };

    await __sdkTurnRunnerTestHooks.collectEventsUntilPauseOrResult(
      undefined,
      managed as never,
      "session_test",
      [],
      turn,
      undefined,
      undefined,
      5_000,
      "gear_first",
    );

    assert.equal(closed, false);
    assert.match(turn.failed_reason ?? "", /ended without requesting any Gee MCP Gear bridge action/);
  });

  it("does not treat light Gear capability discovery as task completion", async () => {
    const turn: SdkTurnResult = {
      assistant_chunks: [],
      tool_events: [],
      auto_approved_tools: 0,
    };
    const managed = {
      events: [
        {
          type: "session.tool_use",
          sessionId: "session_test",
          toolUseId: "toolu_list",
          toolName: "mcp__gee__gear_list_capabilities",
          input: { detail: "summary" },
          raw: {},
        },
        {
          type: "session.tool_result",
          sessionId: "session_test",
          toolUseId: "toolu_list",
          status: "succeeded",
          summary: "media.library is available",
          raw: {},
        },
        {
          type: "session.assistant_text",
          sessionId: "session_test",
          text: "Done.",
          raw: {},
        },
        {
          type: "session.result",
          sessionId: "session_test",
          subtype: "success",
          result: "Done.",
          raw: { is_error: false },
        },
      ],
      waiters: [],
      session: {
        close() {},
      },
      toolBoundaryMode: "gear_first",
      toolInvocationCount: 0,
    };

    await __sdkTurnRunnerTestHooks.collectEventsUntilPauseOrResult(
      undefined,
      managed as never,
      "session_test",
      [],
      turn,
      undefined,
      undefined,
      5_000,
      "gear_first",
      null,
    );

    assert.match(turn.failed_reason ?? "", /capability discovery without executing a Gear invocation/);
  });

  it("extracts generic Gee host-action directives for any enabled Gear", () => {
    const actions = __sdkTurnRunnerTestHooks.extractHostActionDirective([
      'Need native Gear work.\n<gee-host-actions>{"actions":[',
      '{"tool_id":"gee.gear.listCapabilities","arguments":{"detail":"summary"}},',
      '{"tool_id":"gee.gear.invoke","arguments":{"gear_id":"bookmark.vault","capability_id":"bookmark.save","args":{"content":"hello"}}},',
      '{"tool_id":"shell.run","arguments":{"command":"rm -rf /"}}',
      "]}</gee-host-actions>",
    ]);

    assert.equal(actions.length, 2);
    assert.equal(actions[0].tool_id, "gee.gear.listCapabilities");
    assert.deepEqual(actions[0].arguments, { detail: "summary" });
    assert.equal(actions[1].tool_id, "gee.gear.invoke");
    assert.deepEqual(actions[1].arguments, {
      gear_id: "bookmark.vault",
      capability_id: "bookmark.save",
      args: { content: "hello" },
    });
    assert.match(actions[0].host_action_id, /^host_action_directive_[a-f0-9]{8}_[a-f0-9]{8}$/);
  });

  it("keeps Gee host-action directives out of visible assistant text", () => {
    const partition = __sdkTurnRunnerTestHooks.partitionAssistantControlText(
      [
        "I will use the native Gear bridge.",
        '<gee-host-actions>{"actions":[{"tool_id":"gee.gear.listCapabilities","arguments":{"detail":"summary"}}]}</gee-host-actions>',
      ].join("\n"),
    );

    assert.equal(partition.sawHostActionDirective, true);
    assert.equal(partition.visibleText.trim(), "I will use the native Gear bridge.");
    assert.match(partition.controlText, /<gee-host-actions>/);
    assert.doesNotMatch(partition.visibleText, /gee-host-actions/);
  });

  it("keeps split Gee host-action directives out of streamed assistant text", () => {
    const filter = __sdkTurnRunnerTestHooks.createAssistantControlTextFilter();
    const first = filter.push("Planning <gee-host");
    const second = filter.push('-actions>{"actions":[]}</gee-host-actions> done');
    const flushed = filter.flush();

    assert.equal(first.visibleText, "Planning ");
    assert.equal(second.visibleText, " done");
    assert.equal(flushed.visibleText, "");
    assert.match(second.controlText, /gee-host-actions/);
  });

  it("extracts multiple Gee host-action directive blocks from one assistant result", () => {
    const actions = __sdkTurnRunnerTestHooks.extractHostActionDirective([
      '<gee-host-actions>{"actions":[{"tool_id":"gee.gear.listCapabilities","arguments":{"detail":"summary"}}]}</gee-host-actions>',
      '<gee-host-actions>{"actions":[{"tool_id":"gee.gear.listCapabilities","arguments":{"detail":"capabilities","gear_id":"bookmark.vault"}}]}</gee-host-actions>',
    ]);

    assert.equal(actions.length, 2);
    assert.deepEqual(actions[0].arguments, { detail: "summary" });
    assert.deepEqual(actions[1].arguments, {
      detail: "capabilities",
      gear_id: "bookmark.vault",
    });
  });

  it("normalizes raw Gee host-action directives into the canonical gear args envelope", () => {
    const actions = __sdkTurnRunnerTestHooks.extractHostActionDirective([
      "<gee-host-actions>{\"actions\":[",
      "{\"tool_id\":\"gee.gear.invoke\",\"arguments\":{\"gear_id\":\"wespy.reader\",\"capability_id\":\"wespy.fetch_article\",\"payload\":{\"url\":\"https://mp.weixin.qq.com/s/demo\",\"save_html\":true}}},",
      "{\"tool_id\":\"gee.gear.invoke\",\"arguments\":{\"gear_id\":\"wespy.reader\",\"capability_id\":\"wespy.fetch_article\",\"url\":\"https://mp.weixin.qq.com/s/demo2\",\"save_json\":true}}",
      "]}</gee-host-actions>",
    ]);

    assert.deepEqual(actions.map((action) => action.arguments), [
      {
        gear_id: "wespy.reader",
        capability_id: "wespy.fetch_article",
        args: {
          url: "https://mp.weixin.qq.com/s/demo",
          save_html: true,
        },
      },
      {
        gear_id: "wespy.reader",
        capability_id: "wespy.fetch_article",
        args: {
          url: "https://mp.weixin.qq.com/s/demo2",
          save_json: true,
        },
      },
    ]);
  });

  it("validates Gear host-action directives before creating host actions", () => {
    const extraction = __sdkTurnRunnerTestHooks.extractHostActionDirectiveResult([
      "<gee-host-actions>{\"actions\":[",
      "{\"tool_id\":\"gee.gear.invoke\",\"arguments\":{\"gear_id\":\"wespy.reader\",\"capability_id\":\"wespy.fetch_article\",\"args\":{\"save_html\":true}}}",
      "]}</gee-host-actions>",
    ]);

    assert.equal(extraction.sawDirective, true);
    assert.deepEqual(extraction.actions, []);
    assert.equal(extraction.errors.length, 1);
    assert.equal(extraction.errors[0]?.tool_id, "gee.gear.invoke");
    assert.equal(extraction.errors[0]?.code, "gear.args.url");
    assert.match(
      extraction.errors[0]?.message ?? "",
      /required string `url` is missing/,
    );
    assert.deepEqual(
      __sdkTurnRunnerTestHooks.extractHostActionDirective([
        "<gee-host-actions>{\"actions\":[",
        "{\"tool_id\":\"gee.gear.invoke\",\"arguments\":{\"gear_id\":\"wespy.reader\",\"capability_id\":\"wespy.fetch_article\",\"args\":{}}}",
        "]}</gee-host-actions>",
      ]),
      [],
    );
  });

  it("rejects unsupported Gee host-action directive tools instead of silently no-oping", () => {
    const extraction = __sdkTurnRunnerTestHooks.extractHostActionDirectiveResult([
      "<gee-host-actions>{\"actions\":[",
      "{\"tool_id\":\"shell.run\",\"arguments\":{\"command\":\"echo nope\"}}",
      "]}</gee-host-actions>",
    ]);

    assert.equal(extraction.sawDirective, true);
    assert.deepEqual(extraction.actions, []);
    assert.equal(extraction.errors[0]?.code, "gee.host_actions.unsupported_tool");
    assert.match(extraction.errors[0]?.message ?? "", /shell\.run/);
  });

  it("parses English media-library extension filters without hardcoded assistant text", () => {
    const routed = routeLocalGearIntent("show all PNG files in the media library");
    assert.ok(routed);
    assert.deepEqual(routed.hostActions[1].arguments, {
      gear_id: "media.library",
      capability_id: "media.filter",
      args: { kind: "all", extensions: ["png"] },
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

    const gearRaw = await handleNativeRuntimeCommand(
      "invoke-tool",
      [
        JSON.stringify({
          tool_id: "gee.gear.invoke",
          arguments: {
            gear_id: "media.library",
            capability_id: "media.filter",
            args: { kind: "image", extensions: ["png"] },
          },
        }),
      ],
      { configDir },
    );
    const gearOutcome = JSON.parse(gearRaw);
    assert.equal(gearOutcome.kind, "completed");
    assert.equal(gearOutcome.tool_id, "gee.gear.invoke");
    assert.deepEqual(gearOutcome.payload, {
      intent: "gear.invoke",
      gear_id: "media.library",
      capability_id: "media.filter",
      args: { kind: "image", extensions: ["png"] },
    });
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
    assert.match(messages.at(-1).content, /SDK runtime is not live/i);
    assert.equal(snapshot.last_run_state.status, "failed");
    assert.equal(snapshot.last_run_state.stop_reason, "sdk_runtime_not_live");
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

  it("treats lsof listening-port no-match as a successful inspection result", async () => {
    const normalized = await __sdkTurnRunnerTestHooks.normalizeSdkToolResult(
      undefined,
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

  it("keeps unrelated non-zero Bash results marked as failed", async () => {
    const normalized = await __sdkTurnRunnerTestHooks.normalizeSdkToolResult(
      undefined,
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
    assert.match(normalized.error ?? "", /Exit code 1/);
  });

  it("materializes large SDK tool results as transcript artifact references", async () => {
    const configDir = await mkdtemp(join(tmpdir(), "geeagent-artifacts-"));
    const largeOutput = Array.from({ length: 5000 }, (_, index) => `line ${index}`).join("\n");

    const normalized = await __sdkTurnRunnerTestHooks.normalizeSdkToolResult(
      configDir,
      {
        type: "session.tool_result",
        sessionId: "session_test",
        toolUseId: "toolu_large",
        status: "succeeded",
        summary: largeOutput,
        raw: {},
      },
      {
        tool_name: "Bash",
        input: {
          command: "printf lots",
        },
      },
    );

    assert.equal(normalized.status, "succeeded");
    assert.equal(normalized.artifacts.length, 1);
    const artifact = normalized.artifacts[0];
    assert.equal(artifact.type, "tool_result_artifact");
    assert.match(artifact.title, /Bash output/);
    assert.match(artifact.inlinePreviewSummary ?? "", /5000 lines/);
    assert.ok(artifact.payloadRef.startsWith(join(configDir, "Artifacts")));
    const payload = await readFile(artifact.payloadRef, "utf8");
    assert.equal(payload, largeOutput);
    assert.ok((normalized.summary ?? "").length < largeOutput.length / 4);
  });

  it("materializes large host-action completions before model continuation", async () => {
    const configDir = await mkdtemp(join(tmpdir(), "geeagent-host-action-artifacts-"));
    const artifactRoot = join(configDir, "Artifacts");
    const largeBody = "article paragraph ".repeat(4_000);
    const resultJSON = JSON.stringify({
      gear_id: "wespy.reader",
      capability_id: "wespy.fetch_article",
      article_count: 1,
      articles: [
        {
          title: "Large article",
          url: "https://mp.weixin.qq.com/s/demo",
          body: largeBody,
        },
      ],
    });

    const prepared = await prepareHostActionCompletionsForModel(
      [
        {
          host_action_id: "host_action_large_wespy",
          tool_id: "gee.gear.invoke",
          status: "succeeded",
          summary: "wespy.reader fetched one article",
          result_json: resultJSON,
        },
      ],
      artifactRoot,
    );

    assert.equal(prepared.completions.length, 1);
    assert.equal(prepared.artifacts.length, 1);
    assert.equal(prepared.completions[0]?.result, undefined);
    assert.match(prepared.completions[0]?.result_artifact?.path ?? "", /host_action_large_wespy/);
    assert.ok(
      prepared.completions[0]?.result_artifact?.token_estimate &&
        prepared.completions[0].result_artifact.token_estimate > 1_500,
    );
    const payload = await readFile(prepared.completions[0]?.result_artifact?.path ?? "", "utf8");
    assert.deepEqual(JSON.parse(payload), JSON.parse(resultJSON));

    const continuationPrompt =
      await __sdkTurnRunnerTestHooks.composeHostActionContinuationPrompt(
        [
          {
            host_action_id: "host_action_large_wespy",
            tool_id: "gee.gear.invoke",
            status: "succeeded",
            summary: "wespy.reader fetched one article",
            result_json: resultJSON,
          },
        ],
        artifactRoot,
      );
    assert.match(continuationPrompt, /Known Gee Gear required args/);
    assert.match(continuationPrompt, /media\.library\/media\.import_files: args\.paths/);
    assert.match(continuationPrompt, /Never call `gee\.gear\.invoke` with guessed or empty required arguments/);
    assert.match(continuationPrompt, /result_artifact/);
    assert.doesNotMatch(continuationPrompt, /article paragraph article paragraph/);
  });

  it("persists SDK tool artifact refs into transcript tool results", () => {
    const store = defaultRuntimeStore("2026-04-27T00:00:00.000Z");
    const sessionId = executionSessionIdForConversation(store.active_conversation_id);
    appendToolEvents(store, sessionId, "msg_user_artifact", [
      {
        kind: "result",
        invocation_id: "toolu_artifact",
        status: "succeeded",
        summary: "Large output stored as an artifact.",
        artifacts: [
          {
            artifactId: "artifact_toolu_artifact",
            type: "tool_result_artifact",
            title: "Bash output",
            payloadRef: "/tmp/geeagent-artifact.txt",
            inlinePreviewSummary: "Large output preview.",
          },
        ],
      },
    ]);

    const payload = (store.transcript_events.at(-1) as { payload: Record<string, unknown> } | undefined)
      ?.payload;
    assert.equal(payload?.kind, "tool_result");
    assert.deepEqual(payload?.artifacts, [
      {
        artifactId: "artifact_toolu_artifact",
        type: "tool_result_artifact",
        title: "Bash output",
        payloadRef: "/tmp/geeagent-artifact.txt",
        inlinePreviewSummary: "Large output preview.",
      },
    ]);
  });

  it("threads first-class run ids through transcript events, host actions, and stage capsules", () => {
    const store = defaultRuntimeStore("2026-04-27T00:00:00.000Z");
    const cursor = beginTurnReplay(
      store,
      "cli_workspace_chat",
      "save this tweet to bookmarks https://x.com/demo/status/123",
    );
    const plan = buildRuntimeRunPlan(
      "save this tweet to bookmarks https://x.com/demo/status/123",
      "gear_first",
    );
    assert.ok(plan);
    appendRunPlanForSession(store, cursor.sessionId, plan);
    appendCapabilityFocusForSession(store, cursor.sessionId, plan);
    appendStageStartedForSession(store, cursor.sessionId, plan);
    appendToolEvents(store, cursor.sessionId, cursor.userMessageId, [
      {
        kind: "invocation",
        invocation_id: "toolu_fetch",
        tool_name: "gear_invoke",
        input_summary: "Fetch tweet",
      },
    ]);
    appendToolResultForExistingInvocation(
      store,
      cursor.sessionId,
      "toolu_fetch",
      "succeeded",
      "Fetched structured tweet result.",
      undefined,
      [],
      cursor.runId,
    );
    __turnTestHooks.recordHostActionRuns(
      store,
      "sdk_same_run",
      cursor.runId,
      cursor.sessionId,
      cursor.userMessageId,
      [
        {
          host_action_id: "host_action_fetch",
          tool_id: "gee.gear.invoke",
          arguments: {
            gear_id: "twitter.capture",
            capability_id: "twitter.fetch_tweet",
            args: { url: "https://x.com/demo/status/123" },
          },
        },
      ],
    );
    const capsule = __turnTestHooks.stageSummaryCapsuleForTurn(
      store,
      cursor,
      {
        assistant_chunks: ["Done."],
        final_result: "Done.",
        tool_events: [],
        auto_approved_tools: 0,
      },
      "Done.",
      plan,
    );
    finalizeTurnReplay(store, cursor, "run id lineage test completed", capsule);

    assert.match(cursor.runId, /^run_session_/);
    assert.equal(latestRunIdForSession(store, cursor.sessionId), cursor.runId);
    assert.equal(store.host_action_runs?.[0]?.run_id, cursor.runId);
    assert.match(capsule, new RegExp(`Run id: ${cursor.runId}`));

    const turnEvents = (store.transcript_events as Array<Record<string, unknown>>).filter(
      (event) => event.session_id === cursor.sessionId,
    );
    assert.ok(turnEvents.length > 0);
    assert.ok(turnEvents.every((event) => event.run_id === cursor.runId));
    assert.deepEqual(
      turnEvents.map((event) => event.sequence),
      turnEvents.map((_, index) => index + 1),
    );
    assert.ok(
      turnEvents.every(
        (event) =>
          typeof event.payload === "object" &&
          event.payload !== null &&
          !Array.isArray(event.payload) &&
          (event.payload as Record<string, unknown>).run_id === cursor.runId,
      ),
    );
  });

  it("exports a replay bundle for one runtime run without prompt replay context", async () => {
    const configDir = await tempConfigDir();
    const store = defaultRuntimeStore("2026-04-27T00:00:00.000Z");
    const cursor = beginTurnReplay(
      store,
      "cli_workspace_chat",
      "save this tweet to bookmarks https://x.com/demo/status/123",
    );
    appendToolEvents(store, cursor.sessionId, cursor.userMessageId, [
      {
        kind: "invocation",
        invocation_id: "toolu_replay",
        tool_name: "Read",
        input_summary: "Read replay evidence",
      },
      {
        kind: "result",
        invocation_id: "toolu_replay",
        status: "succeeded",
        summary: "Large output stored as an artifact.",
        artifacts: [
          {
            artifactId: "artifact_replay",
            type: "tool_result_artifact",
            title: "Replay artifact",
            payloadRef: "/tmp/geeagent-replay-artifact.json",
            inlinePreviewSummary: "Replay evidence.",
          },
        ],
      },
    ]);
    __turnTestHooks.recordHostActionRuns(
      store,
      "sdk_same_run",
      cursor.runId,
      cursor.sessionId,
      cursor.userMessageId,
      [
        {
          host_action_id: "host_action_replay",
          tool_id: "gee.gear.invoke",
          arguments: {
            gear_id: "bookmark.vault",
            capability_id: "bookmark.save",
            args: { content: "https://x.com/demo/status/123" },
          },
        },
      ],
    );
    store.approval_requests.push({
      approval_request_id: "approval_replay",
      run_id: cursor.runId,
      machine_context: {
        run_id: cursor.runId,
        runtime_session_id: cursor.sessionId,
      },
    });
    await writeFile(join(configDir, "runtime-store.json"), JSON.stringify(store, null, 2), "utf8");

    const raw = await handleNativeRuntimeCommand("export-runtime-run", [cursor.runId], {
      configDir,
    });
    const exported = JSON.parse(raw);

    assert.equal(exported.schema_version, 1);
    assert.equal(exported.run_id, cursor.runId);
    assert.deepEqual(
      exported.events.map((event: { sequence: number }) => event.sequence),
      [1, 2, 3, 4],
    );
    assert.deepEqual(exported.execution_session_ids, [cursor.sessionId]);
    assert.deepEqual(exported.conversation_ids, [store.active_conversation_id]);
    assert.equal(exported.host_action_runs[0].run_id, cursor.runId);
    assert.equal(exported.approval_requests[0].run_id, cursor.runId);
    assert.deepEqual(exported.artifact_ids, ["artifact_replay"]);
    assert.equal(exported.artifact_refs[0].artifact_id, "artifact_replay");
    assert.equal(exported.artifact_refs[0].path, "/tmp/geeagent-replay-artifact.json");
    assert.equal(exported.artifact_refs[0].source_event_sequence, 4);
    assert.equal(exported.artifact_refs[0].source_invocation_id, "toolu_replay");
    assert.equal(exported.artifact_refs[0].source_tool_name, "Read");
    assert.deepEqual(exported.diagnostics.duplicate_event_ids, []);
    assert.deepEqual(exported.diagnostics.missing_parent_event_ids, []);
    assert.deepEqual(exported.diagnostics.missing_sequence_numbers, []);
    assert.deepEqual(exported.diagnostics.out_of_order_event_ids, []);

    const projectedRaw = await handleNativeRuntimeCommand("project-runtime-run", [cursor.runId], {
      configDir,
    });
    const projected = JSON.parse(projectedRaw);
    assert.equal(projected.run_id, cursor.runId);
    assert.deepEqual(
      projected.rows.map((row: { projection_kind: string }) => row.projection_kind),
      ["user_message", "runtime_state", "tool", "tool_result"],
    );
    assert.deepEqual(projected.artifact_ids, ["artifact_replay"]);
    assert.equal(projected.artifact_refs[0].source_tool_name, "Read");
    assert.equal(projected.rows[0].projection_scope, "main_timeline");
    assert.equal(projected.rows[1].projection_scope, "inspector");
    assert.equal(projected.rows[2].projection_scope, "worked");
    assert.deepEqual(projected.rows[3].artifact_ids, ["artifact_replay"]);

    await assert.rejects(
      handleNativeRuntimeCommand("export-runtime-run", ["run_missing"], { configDir }),
      /has no transcript events/,
    );
  });

  it("imports replay fixtures into deterministic projections with diagnostics", async () => {
    const configDir = await tempConfigDir();
    const replay = {
      schema_version: 1,
      run_id: "run_fixture",
      exported_at: "2026-05-01T00:00:00.000Z",
      event_count: 3,
      conversation_ids: ["conv_fixture"],
      execution_session_ids: ["session_fixture"],
      sdk_session_ids: [],
      parent_run_ids: [],
      host_action_runs: [],
      approval_requests: [],
      artifact_ids: ["artifact_late", "artifact_early"],
      artifact_refs: [
        {
          artifact_id: "artifact_late",
          path: "/tmp/late.json",
          source_event_sequence: 4,
        },
        {
          artifact_id: "artifact_early",
          path: "/tmp/early.json",
          source_event_sequence: 2,
        },
      ],
      diagnostics: {
        duplicate_event_ids: [],
        missing_parent_event_ids: [],
        missing_sequence_numbers: [],
        out_of_order_event_ids: [],
      },
      events: [
        {
          event_id: "event_assistant",
          session_id: "session_fixture",
          parent_event_id: "event_missing",
          run_id: "run_fixture",
          sequence: 2,
          payload: {
            kind: "assistant_message",
            content: "Done.",
          },
        },
        {
          event_id: "event_user",
          session_id: "session_fixture",
          parent_event_id: null,
          sequence: 1,
          payload: {
            kind: "user_message",
            content: "Replay this.",
          },
        },
        {
          event_id: "event_user",
          session_id: "session_fixture",
          parent_event_id: "event_assistant",
          run_id: "run_fixture",
          sequence: 4,
          payload: {
            kind: "session_state_changed",
            summary: "State changed.",
          },
        },
      ],
    };

    const raw = await handleNativeRuntimeCommand(
      "project-runtime-run-replay",
      [JSON.stringify(replay)],
      { configDir },
    );
    const projected = JSON.parse(raw);

    assert.equal(projected.schema_version, 1);
    assert.equal(projected.run_id, "run_fixture");
    assert.deepEqual(
      projected.rows.map((row: { sequence: number }) => row.sequence),
      [1, 2, 4],
    );
    assert.deepEqual(
      projected.rows.map((row: { projection_kind: string }) => row.projection_kind),
      ["user_message", "assistant_message", "runtime_state"],
    );
    assert.deepEqual(
      projected.artifact_refs.map((artifact: { artifact_id: string }) => artifact.artifact_id),
      ["artifact_early", "artifact_late"],
    );
    assert.deepEqual(projected.diagnostics.duplicate_event_ids, ["event_user"]);
    assert.deepEqual(projected.diagnostics.missing_parent_event_ids, ["event_missing"]);
    assert.deepEqual(projected.diagnostics.missing_sequence_numbers, [3]);
    assert.deepEqual(projected.diagnostics.out_of_order_event_ids, ["event_user"]);
  });

  it("classifies runtime waits with run lineage evidence", async () => {
    const configDir = await tempConfigDir();
    const storePath = join(configDir, "runtime-store.json");

    const toolStore = defaultRuntimeStore("2026-05-01T00:00:00.000Z");
    const toolCursor = beginTurnReplay(toolStore, "cli_workspace_chat", "inspect tool wait");
    appendToolEvents(toolStore, toolCursor.sessionId, toolCursor.userMessageId, [
      {
        kind: "invocation",
        invocation_id: "toolu_wait",
        tool_name: "Bash",
        input_summary: "sleep 1",
      },
    ]);
    await writeFile(storePath, JSON.stringify(toolStore, null, 2), "utf8");
    const toolWait = JSON.parse(
      await handleNativeRuntimeCommand("classify-runtime-run-wait", [toolCursor.runId], {
        configDir,
      }),
    );
    assert.equal(toolWait.wait_kind, "tool_wait");
    assert.equal(toolWait.evidence.pending_tool_use_id, "toolu_wait");
    assert.equal(toolWait.evidence.last_tool_use_id, "toolu_wait");

    const hostStore = defaultRuntimeStore("2026-05-01T00:00:00.000Z");
    const hostCursor = beginTurnReplay(hostStore, "cli_workspace_chat", "wait for host");
    const hostAction = {
      host_action_id: "host_action_wait",
      tool_id: "gee.gear.invoke",
      arguments: {
        gear_id: "media.library",
        capability_id: "media.filter",
        args: { kind: "video" },
      },
    };
    hostStore.host_action_intents = [hostAction];
    __turnTestHooks.recordHostActionRuns(
      hostStore,
      "sdk_same_run",
      hostCursor.runId,
      hostCursor.sessionId,
      hostCursor.userMessageId,
      [hostAction],
    );
    await writeFile(storePath, JSON.stringify(hostStore, null, 2), "utf8");
    const hostWait = JSON.parse(
      await handleNativeRuntimeCommand("classify-runtime-run-wait", [hostCursor.runId], {
        configDir,
      }),
    );
    assert.equal(hostWait.wait_kind, "host_wait");
    assert.deepEqual(hostWait.evidence.pending_host_action_ids, ["host_action_wait"]);
    assert.equal(hostWait.evidence.pending_host_action_payloads[0].arguments.gear_id, "media.library");

    const approvalStore = defaultRuntimeStore("2026-05-01T00:00:00.000Z");
    const approvalCursor = beginTurnReplay(
      approvalStore,
      "cli_workspace_chat",
      "wait for approval",
    );
    approvalStore.approval_requests.push({
      approval_request_id: "approval_wait",
      run_id: approvalCursor.runId,
      status: "open",
      machine_context: {
        run_id: approvalCursor.runId,
        runtime_session_id: "sdk_approval",
        runtime_request_id: "gateway_req_approval",
      },
    });
    await writeFile(storePath, JSON.stringify(approvalStore, null, 2), "utf8");
    const approvalWait = JSON.parse(
      await handleNativeRuntimeCommand("classify-runtime-run-wait", [approvalCursor.runId], {
        configDir,
      }),
    );
    assert.equal(approvalWait.wait_kind, "approval_wait");
    assert.equal(approvalWait.evidence.pending_approval_id, "approval_wait");
    assert.equal(approvalWait.evidence.sdk_session_id, "sdk_approval");
    assert.equal(approvalWait.evidence.gateway_request_id, "gateway_req_approval");

    const lostStore = defaultRuntimeStore("2026-05-01T00:00:00.000Z");
    const lostCursor = beginTurnReplay(lostStore, "cli_workspace_chat", "lost session");
    lostStore.last_run_state = {
      conversation_id: lostStore.active_conversation_id,
      status: "failed",
      stop_reason: "sdk_host_action_session_lost",
      detail: "lost",
      resumable: false,
      task_id: null,
      module_run_id: null,
    };
    await writeFile(storePath, JSON.stringify(lostStore, null, 2), "utf8");
    const sessionLost = JSON.parse(
      await handleNativeRuntimeCommand("classify-runtime-run-wait", [lostCursor.runId], {
        configDir,
      }),
    );
    assert.equal(sessionLost.wait_kind, "session_lost");
    assert.equal(sessionLost.status, "failed");

    const completedStore = defaultRuntimeStore("2026-05-01T00:00:00.000Z");
    const completedCursor = beginTurnReplay(completedStore, "cli_workspace_chat", "finish run");
    appendAssistantMessageForActiveConversation(
      completedStore,
      completedCursor.sessionId,
      "Done.",
      completedCursor.assistantMessageId,
    );
    await writeFile(storePath, JSON.stringify(completedStore, null, 2), "utf8");
    const completed = JSON.parse(
      await handleNativeRuntimeCommand("classify-runtime-run-wait", [completedCursor.runId], {
        configDir,
      }),
    );
    assert.equal(completed.wait_kind, "completed");
    assert.equal(completed.status, "complete");

    const silentStore = defaultRuntimeStore("2026-05-01T00:00:00.000Z");
    await writeFile(storePath, JSON.stringify(silentStore, null, 2), "utf8");
    const silence = JSON.parse(
      await handleNativeRuntimeCommand("classify-runtime-run-wait", ["run_missing"], {
        configDir,
      }),
    );
    assert.equal(silence.wait_kind, "event_silence");
  });

  it("persists assistant deltas with the same message id as the final assistant message", () => {
    const store = defaultRuntimeStore("2026-04-27T00:00:00.000Z");
    store.conversations[0].messages.push({
      message_id: "msg_user_01",
      role: "user",
      content: "stream a response",
      timestamp: "2026-04-27T00:00:00.000Z",
    });
    const sessionId = executionSessionIdForConversation(store.active_conversation_id);

    const deltaMessageId = appendAssistantDeltaForActiveConversation(
      store,
      sessionId,
      "partial response",
    );
    const finalMessageId = appendAssistantMessageForActiveConversation(
      store,
      sessionId,
      "partial response complete",
    );

    assert.equal(deltaMessageId, finalMessageId);
    assert.deepEqual(
      store.transcript_events
        .filter((event) => event.session_id === sessionId)
        .map((event) => event.payload.kind),
      ["assistant_message_delta", "assistant_message"],
    );
  });

  it("keeps assistant stream ids stable for the whole turn cursor", () => {
    const store = defaultRuntimeStore("2026-04-27T00:00:00.000Z");
    const cursor = beginTurnReplay(store, "chat", "stream this turn");

    const firstDeltaId = appendAssistantDeltaForActiveConversation(
      store,
      cursor.sessionId,
      "first ",
      cursor.assistantMessageId,
    );
    store.conversations[0].messages.push({
      message_id: "msg_system_interleaved",
      role: "assistant",
      content: "interleaved non-stream message",
      timestamp: "2026-04-27T00:00:00.000Z",
    });
    const secondDeltaId = appendAssistantDeltaForActiveConversation(
      store,
      cursor.sessionId,
      "second",
      cursor.assistantMessageId,
    );
    const finalMessageId = appendAssistantMessageForActiveConversation(
      store,
      cursor.sessionId,
      "first second",
      cursor.assistantMessageId,
    );

    assert.equal(firstDeltaId, cursor.assistantMessageId);
    assert.equal(secondDeltaId, cursor.assistantMessageId);
    assert.equal(finalMessageId, cursor.assistantMessageId);
  });

  it("strips stage-progress assistant text before it becomes chat", () => {
    const strip = __sdkTurnRunnerTestHooks.stripAssistantStageProgressText;

    assert.equal(
      strip("Stage complete: fetched the tweet and found one video media URL."),
      "",
    );
    assert.equal(
      strip(
        "Stage complete: saved the bookmark with the imported local media path attached.Done — both parts completed.",
      ),
      "Done — both parts completed.",
    );
    assert.equal(
      strip("Useful final reply."),
      "Useful final reply.",
    );
  });

  it("builds stage capsules from the active conversation instead of reused message ids", () => {
    const now = "2026-04-27T00:00:00.000Z";
    const store = defaultRuntimeStore(now);
    store.conversations = [
      {
        conversation_id: "conv_old",
        title: "Old",
        status: "idle",
        messages: [
          {
            message_id: "msg_user_01",
            role: "user",
            content: "old conversation request",
            timestamp: now,
          },
        ],
      },
      {
        conversation_id: "conv_new",
        title: "New",
        status: "active",
        messages: [
          {
            message_id: "msg_user_01",
            role: "user",
            content: "new active request",
            timestamp: now,
          },
        ],
      },
    ];
    store.active_conversation_id = "conv_new";
    store.execution_sessions.push({
      session_id: "session_conv_new",
      conversation_id: "conv_new",
      surface: "cli_workspace_chat",
      mode: "interactive",
      project_path: "/tmp",
      parent_session_id: null,
      persistence_policy: "persisted",
      created_at: now,
      updated_at: now,
    });

    const capsule = __turnTestHooks.stageSummaryCapsuleForTurn(
      store,
      {
        sessionId: "session_conv_new",
        userMessageId: "msg_user_01",
        stepCount: 1,
      },
      {
        assistant_chunks: ["done"],
        final_result: "done",
        tool_events: [],
        auto_approved_tools: 0,
      },
      "done",
    );

    assert.match(capsule, /new active request/);
    assert.doesNotMatch(capsule, /old conversation request/);
  });

  it("keeps successful stage capsules successful when an exploratory tool failed", () => {
    const now = "2026-04-27T00:00:00.000Z";
    const store = defaultRuntimeStore(now);
    store.conversations[0].messages = [
      {
        message_id: "msg_user_01",
        role: "user",
        content: "check whether a port is listening",
        timestamp: now,
      },
    ];

    const capsule = __turnTestHooks.stageSummaryCapsuleForTurn(
      store,
      {
        sessionId: `session_${store.active_conversation_id}`,
        userMessageId: "msg_user_01",
        stepCount: 1,
      },
      {
        assistant_chunks: ["No process is listening."],
        final_result: "No process is listening.",
        auto_approved_tools: 0,
        tool_events: [
          {
            kind: "invocation",
            invocation_id: "toolu_probe",
            tool_name: "Bash",
            input_summary: "lsof -nP -iTCP:8088 -sTCP:LISTEN",
          },
          {
            kind: "result",
            invocation_id: "toolu_probe",
            status: "failed",
            summary: "Exit code 1",
            error: "Exit code 1",
          },
        ],
      },
      "No process is listening.",
    );

    assert.match(capsule, /Status: succeeded/);
    assert.match(capsule, /Bash \[failed\]/);
  });

  it("keeps completed local follow-up results visible when Gear final reply times out", () => {
    const reply = __turnTestHooks.gearCompletionFailureReply(
      "save the WeChat article content to a desktop markdown file",
      [
        {
          host_action_id: "host_action_wespy",
          tool_id: "gee.gear.invoke",
          status: "succeeded",
          summary:
            "wespy.reader wespy.fetch_article completed; files: 1; output: /tmp/wespy/output",
        },
      ],
      "The SDK runtime produced no new event for 10 seconds.",
      {
        assistant_chunks: [],
        auto_approved_tools: 0,
        failed_reason: "The SDK runtime produced no new event for 10 seconds.",
        tool_events: [
          {
            kind: "invocation",
            invocation_id: "call_read",
            tool_name: "Read",
            input_summary: "{\"file_path\":\"/tmp/wespy/output/article.md\"}",
          },
          {
            kind: "result",
            invocation_id: "call_read",
            status: "succeeded",
            summary: "article markdown preview",
          },
          {
            kind: "invocation",
            invocation_id: "call_cp",
            tool_name: "Bash",
            input_summary: "{\"command\":\"cp article.md ~/Desktop/article.md\"}",
          },
          {
            kind: "result",
            invocation_id: "call_cp",
            status: "succeeded",
            summary: "-rw-r--r-- /tmp/Desktop/article.md",
          },
        ],
      },
    );

    assert.match(reply, /user objective is not confirmed complete/);
    assert.match(reply, /wespy\.reader wespy\.fetch_article completed/);
    assert.match(reply, /Bash: -rw-r--r-- \/tmp\/Desktop\/article\.md/);
  });

  it("marks SDK turns without assistant text as failed instead of fake completed", () => {
    const turn: SdkTurnResult = {
      assistant_chunks: [],
      auto_approved_tools: 0,
      tool_events: [],
    };

    __turnTestHooks.markMissingAssistantReplyAsFailure(turn, "without a final assistant reply");

    assert.match(turn.failed_reason ?? "", /without a final assistant reply/);
    assert.match(turn.failed_reason ?? "", /instead of presenting a fake completion/);
  });

  it("keeps SDK event waits below the native client timeout", () => {
    const previous = process.env.GEEAGENT_SDK_EVENT_IDLE_TIMEOUT_MS;
    process.env.GEEAGENT_SDK_EVENT_IDLE_TIMEOUT_MS = "6000";
    try {
      assert.equal(__sdkTurnRunnerTestHooks.sdkEventIdleTimeoutMs(), 6_000);
      assert.equal(__sdkTurnRunnerTestHooks.sdkEventIdleTimeoutMs(10_000), 10_000);
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

  it("closes pending Gee host bridge MCP tool invocations from host completions", () => {
    const store = defaultRuntimeStore("2026-04-27T00:00:00.000Z");
    const sessionId = executionSessionIdForConversation(store.active_conversation_id);
    appendToolEvents(store, sessionId, "msg_user_host_action", [
      {
        kind: "invocation",
        invocation_id: "toolu_list_capabilities",
        tool_name: "gear_list_capabilities",
        input_summary: "{\"detail\":\"summary\"}",
      },
    ]);

    appendToolResultForHostBridgeCompletion(
      store,
      sessionId,
      "gee.gear.listCapabilities",
      "failed",
      undefined,
      "No enabled Gear capabilities are available for `wespy.reader`.",
    );

    const result = store.transcript_events.find(
      (event) =>
        event.session_id === sessionId &&
        event.payload.kind === "tool_result" &&
        event.payload.invocation_id === "toolu_list_capabilities",
    );
    assert.ok(result);
    assert.equal(result.payload.status, "failed");
    assert.equal(
      result.payload.error,
      "No enabled Gear capabilities are available for `wespy.reader`.",
    );
  });

  it("matches repeated Gee host bridge completions to invocations in request order", () => {
    const store = defaultRuntimeStore("2026-04-27T00:00:00.000Z");
    const sessionId = executionSessionIdForConversation(store.active_conversation_id);
    appendToolEvents(store, sessionId, "msg_user_host_action", [
      {
        kind: "invocation",
        invocation_id: "toolu_first_invoke",
        tool_name: "gear_invoke",
        input_summary: "{\"gear_id\":\"wespy.reader\"}",
      },
      {
        kind: "invocation",
        invocation_id: "toolu_second_invoke",
        tool_name: "gear_invoke",
        input_summary: "{\"gear_id\":\"bookmark.vault\"}",
      },
    ]);

    appendToolResultForHostBridgeCompletion(
      store,
      sessionId,
      "gee.gear.invoke",
      "succeeded",
      "first result",
    );
    appendToolResultForHostBridgeCompletion(
      store,
      sessionId,
      "gee.gear.invoke",
      "succeeded",
      "second result",
    );

    const results = store.transcript_events.filter(
      (event) =>
        event.session_id === sessionId &&
        event.payload.kind === "tool_result" &&
        ["toolu_first_invoke", "toolu_second_invoke"].includes(
          String(event.payload.invocation_id),
        ),
    );
    assert.deepEqual(
      results.map((event) => [event.payload.invocation_id, event.payload.summary]),
      [
        ["toolu_first_invoke", "first result"],
        ["toolu_second_invoke", "second result"],
      ],
    );
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
      /Use Bash with an inspectable command such as curl or python3 urllib/,
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
