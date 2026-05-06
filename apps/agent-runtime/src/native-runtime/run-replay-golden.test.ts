import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { describe, it } from "node:test";

import { projectRuntimeRunReplay } from "./store/run-replay.js";

async function readReplayFixture(name: string): Promise<unknown> {
  const fixtureURL = new URL(`./fixtures/replays/${name}`, import.meta.url);
  return JSON.parse(await readFile(fixtureURL, "utf8"));
}

describe("runtime golden replay fixtures", () => {
  it("projects the minimum Twitter bookmark media workflow from event truth", async () => {
    const replay = await readReplayFixture("twitter-bookmark-media-complete.json");
    const projection = projectRuntimeRunReplay(replay);

    assert.equal(projection.run_id, "run_golden_twitter_bookmark_media");
    assert.equal(projection.row_count, 26);
    assert.deepEqual(projection.diagnostics, {
      duplicate_event_ids: [],
      missing_parent_event_ids: [],
      missing_sequence_numbers: [],
      out_of_order_event_ids: [],
    });
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
});
