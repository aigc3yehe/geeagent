import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { describe, it } from "node:test";

import { defaultRuntimeStore } from "./store/defaults.js";
import {
  classifyRuntimeRunWait,
  projectRuntimeRunReplay,
  type RuntimeRunReplayProjection,
} from "./store/run-replay.js";
import type { RuntimeStore } from "./store/types.js";

async function readReplayFixture(name: string): Promise<unknown> {
  const fixtureURL = new URL(`./fixtures/replays/${name}`, import.meta.url);
  return JSON.parse(await readFile(fixtureURL, "utf8"));
}

function storeForReplayFixture(replay: unknown): RuntimeStore {
  assertRecord(replay);
  const store = defaultRuntimeStore("2026-05-07T00:00:00.000Z");
  const conversationId = stringArray(replay.conversation_ids)[0] ?? "conv_golden";
  const sessionIds = stringArray(replay.execution_session_ids);
  store.active_conversation_id = conversationId;
  store.conversations = [{
    conversation_id: conversationId,
    title: "Golden Replay",
    status: "active",
    tags: [],
    messages: [],
  }];
  store.execution_sessions = sessionIds.map((sessionId) => ({
    session_id: sessionId,
    conversation_id: conversationId,
  }));
  store.transcript_events = Array.isArray(replay.events) ? replay.events : [];
  store.approval_requests = Array.isArray(replay.approval_requests)
    ? replay.approval_requests
    : [];
  store.host_action_runs = Array.isArray(replay.host_action_runs)
    ? replay.host_action_runs as RuntimeStore["host_action_runs"]
    : [];
  if (isRecord(replay.store_overlay)) {
    store.last_run_state = isRecord(replay.store_overlay.last_run_state)
      ? replay.store_overlay.last_run_state
      : null;
    store.host_action_intents = Array.isArray(replay.store_overlay.host_action_intents)
      ? replay.store_overlay.host_action_intents
      : [];
  }
  return store;
}

function projectCleanReplayFixture(replay: unknown): RuntimeRunReplayProjection {
  assertReplayIntegrity(replay);
  const projection = projectRuntimeRunReplay(replay);
  assert.deepEqual(projection.diagnostics, {
    duplicate_event_ids: [],
    missing_parent_event_ids: [],
    missing_sequence_numbers: [],
    out_of_order_event_ids: [],
  });
  return projection;
}

function assertReplayIntegrity(replay: unknown): void {
  assertRecord(replay);
  const runId = stringField(replay, "run_id");
  assert.ok(runId, "Replay fixture must declare a run_id.");
  const events = Array.isArray(replay.events) ? replay.events : [];
  assert.equal(
    numberField(replay, "event_count"),
    events.length,
    `Replay fixture ${runId} event_count must match events.length.`,
  );
  for (const event of events) {
    assertRecord(event);
    assert.equal(stringField(event, "run_id"), runId);
    const payload = isRecord(event.payload) ? event.payload : {};
    assert.equal(stringField(payload, "run_id"), runId);
  }
}

function assertRecord(value: unknown): asserts value is Record<string, unknown> {
  assert.equal(typeof value, "object");
  assert.notEqual(value, null);
  assert.equal(Array.isArray(value), false);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function stringField(value: Record<string, unknown>, key: string): string | null {
  const field = value[key];
  return typeof field === "string" && field.trim().length > 0 ? field : null;
}

function numberField(value: Record<string, unknown>, key: string): number | null {
  const field = value[key];
  return typeof field === "number" && Number.isFinite(field) ? field : null;
}

describe("runtime golden replay fixtures", () => {
  it("projects the minimum Twitter bookmark media workflow from event truth", async () => {
    const replay = await readReplayFixture("twitter-bookmark-media-complete.json");
    const projection = projectCleanReplayFixture(replay);

    assert.equal(projection.run_id, "run_golden_twitter_bookmark_media");
    assert.equal(projection.row_count, 26);
    assert.deepEqual(projection.artifact_ids, [
      "artifact_downloaded_media_manifest",
      "artifact_imported_media_record",
    ]);

    assert.deepEqual(
      projection.rows.map((row) => row.projection_kind),
      [
        "user_message",
        "plan",
        "focus",
        "stage",
        "tool",
        "tool_result",
        "stage",
        "plan",
        "focus",
        "stage",
        "tool",
        "tool_result",
        "stage",
        "plan",
        "focus",
        "stage",
        "tool",
        "tool_result",
        "stage",
        "plan",
        "focus",
        "stage",
        "tool",
        "tool_result",
        "stage",
        "assistant_message",
      ],
    );

    const concludedStages = projection.rows
      .filter((row) => row.event_kind === "stage_concluded")
      .map((row) => `${row.stage_id}:${row.status}`);
    assert.deepEqual(concludedStages, [
      "stage_fetch_tweet:completed",
      "stage_download_media:completed",
      "stage_import_media:completed",
      "stage_save_bookmark:completed",
    ]);

    const downloadResult = projection.rows.find(
      (row) => row.stage_id === "stage_download_media" && row.projection_kind === "tool_result",
    );
    assert.deepEqual(downloadResult?.artifact_ids, ["artifact_downloaded_media_manifest"]);
    assert.equal(downloadResult?.expandable, true);

    const importResult = projection.rows.find(
      (row) => row.stage_id === "stage_import_media" && row.projection_kind === "tool_result",
    );
    assert.deepEqual(importResult?.artifact_ids, ["artifact_imported_media_record"]);
    assert.equal(importResult?.status, "succeeded");

    const finalRow = projection.rows.at(-1);
    assert.equal(finalRow?.projection_scope, "main_timeline");
    assert.match(finalRow?.summary ?? "", /Saved the tweet bookmark/);
  });

  it("projects approval pause and same-run resume without leaving the run waiting", async () => {
    const replay = await readReplayFixture("approval-pause-resume-complete.json");
    const projection = projectCleanReplayFixture(replay);

    assert.equal(projection.run_id, "run_golden_approval_pause_resume");
    assert.deepEqual(
      projection.rows.map((row) => row.projection_kind),
      [
        "user_message",
        "tool",
        "runtime_state",
        "runtime_state",
        "tool_result",
        "assistant_message",
      ],
    );
    assert.deepEqual(
      projection.rows
        .filter((row) => row.projection_kind === "runtime_state")
        .map((row) => row.summary),
      [
        "Approval requested for Bash execution.",
        "Approval approved; resuming the same run.",
      ],
    );

    const classification = classifyRuntimeRunWait(
      storeForReplayFixture(replay),
      "run_golden_approval_pause_resume",
    );
    assert.equal(classification.wait_kind, "completed");
    assert.equal(classification.status, "complete");
  });

  it("projects terminal/file continuation through an artifact reference", async () => {
    const replay = await readReplayFixture("terminal-file-artifact-complete.json");
    const projection = projectCleanReplayFixture(replay);

    assert.equal(projection.run_id, "run_golden_terminal_file_artifact");
    assert.deepEqual(projection.artifact_ids, ["artifact_runtime_log_read"]);
    assert.deepEqual(
      projection.rows.map((row) => row.projection_kind),
      ["user_message", "tool", "tool_result", "assistant_message"],
    );

    const toolResult = projection.rows.find((row) => row.projection_kind === "tool_result");
    assert.deepEqual(toolResult?.artifact_ids, ["artifact_runtime_log_read"]);
    assert.equal(toolResult?.expandable, true);

    const classification = classifyRuntimeRunWait(
      storeForReplayFixture(replay),
      "run_golden_terminal_file_artifact",
    );
    assert.equal(classification.wait_kind, "completed");
    assert.equal(classification.status, "complete");
  });

  it("projects chat attachments and directory snapshot results through replay", async () => {
    const replay = await readReplayFixture("chat-attachments-directory-snapshot-complete.json");
    const projection = projectCleanReplayFixture(replay);

    assert.equal(projection.run_id, "run_golden_chat_attachments_directory_snapshot");
    assert.deepEqual(
      projection.rows.map((row) => row.projection_kind),
      ["user_message", "tool", "tool_result", "assistant_message"],
    );

    const userRow = projection.rows.find((row) => row.projection_kind === "user_message") as
      | (Record<string, unknown> & { projection_kind: string })
      | undefined;
    assert.deepEqual(userRow?.attachment_ids, ["att_screenshot_tree", "att_actual_dir"]);
    assert.deepEqual(userRow?.attachment_statuses, ["ready", "ready"]);
    assert.match(String(userRow?.summary ?? ""), /2 attachments/);

    const toolResult = projection.rows.find((row) => row.projection_kind === "tool_result");
    assert.equal(toolResult?.tool_name, "mcp__gee__files_directory_snapshot");
    assert.match(toolResult?.summary ?? "", /README\.md/);

    const classification = classifyRuntimeRunWait(
      storeForReplayFixture(replay),
      "run_golden_chat_attachments_directory_snapshot",
    );
    assert.equal(classification.wait_kind, "completed");
    assert.equal(classification.status, "complete");
  });

  it("classifies session loss before treating a pending tool as ordinary waiting", async () => {
    const replay = await readReplayFixture("session-lost-pending-tool.json");
    const projection = projectCleanReplayFixture(replay);

    assert.equal(projection.run_id, "run_golden_session_lost_pending_tool");
    assert.deepEqual(
      projection.rows.map((row) => row.projection_kind),
      ["user_message", "tool"],
    );

    const classification = classifyRuntimeRunWait(
      storeForReplayFixture(replay),
      "run_golden_session_lost_pending_tool",
    );
    assert.equal(classification.wait_kind, "session_lost");
    assert.equal(classification.status, "failed");
    assert.equal(classification.evidence.pending_tool_use_id, "toolu_pending_when_lost");
    assert.equal(classification.evidence.last_tool_use_id, "toolu_pending_when_lost");
  });
});
