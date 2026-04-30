import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { buildRuntimeRunPlan, nextRuntimeRunPlan } from "./planning.js";
import {
  advanceRunPlanAfterHostCompletions,
  terminalRunPlanBlocker,
} from "./stage-advancer.js";

function tweetMediaPlan() {
  const plan = buildRuntimeRunPlan(
    "save this tweet to bookmarks and import its media into the media browser https://x.com/0xbisc/status/2049100073481716076?s=20",
    "gear_first",
  );
  assert.ok(plan);
  assert.equal(plan.current_stage_id, "stage_fetch_tweet");
  return plan;
}

function tweetMediaPlanAt(stageID: string) {
  let plan = tweetMediaPlan();
  while (plan.current_stage_id !== stageID) {
    const nextPlan = nextRuntimeRunPlan(plan);
    assert.ok(nextPlan, `Expected plan to advance to ${stageID}`);
    plan = nextPlan;
  }
  return plan;
}

describe("stage advancer", () => {
  it("advances from structured Gear execution envelopes", () => {
    const plan = tweetMediaPlan();

    const decision = advanceRunPlanAfterHostCompletions(plan, [
      {
        host_action_id: "host_action_fetch",
        tool_id: "gee.gear.invoke",
        status: "succeeded",
        summary: "twitter.capture twitter.fetch_tweet completed",
        result_json: JSON.stringify({
          kind: "execution",
          tool_id: "gee.gear.invoke",
          status: "succeeded",
          gear_id: "twitter.capture",
          capability_id: "twitter.fetch_tweet",
          tweet_count: 1,
        }),
      },
    ]);

    assert.equal(decision.concluded, true);
    assert.equal(decision.status, "completed");
    assert.equal(decision.nextPlan?.current_stage_id, "stage_download_media");
  });

  it("does not advance from Gear schema disclosure even when it names the required capability", () => {
    const plan = tweetMediaPlan();

    const decision = advanceRunPlanAfterHostCompletions(plan, [
      {
        host_action_id: "host_action_schema",
        tool_id: "gee.gear.listCapabilities",
        status: "succeeded",
        summary: "twitter.capture twitter.fetch_tweet completed",
        result_json: JSON.stringify({
          disclosure_level: "schema",
          tool: "gee.gear.listCapabilities",
          gear_id: "twitter.capture",
          capability_id: "twitter.fetch_tweet",
          args_schema: {
            type: "object",
            required: ["url"],
            properties: {
              url: { type: "string" },
            },
          },
        }),
      },
    ]);

    assert.equal(decision.concluded, false);
    assert.match(terminalRunPlanBlocker(plan) ?? "", /twitter\.capture\/twitter\.fetch_tweet/);
  });

  it("does not advance from Gear execution envelopes with failed inner status", () => {
    const plan = tweetMediaPlan();

    const decision = advanceRunPlanAfterHostCompletions(plan, [
      {
        host_action_id: "host_action_fetch",
        tool_id: "gee.gear.invoke",
        status: "succeeded",
        summary: "twitter.capture twitter.fetch_tweet completed",
        result_json: JSON.stringify({
          kind: "execution",
          tool_id: "gee.gear.invoke",
          status: "failed",
          gear_id: "twitter.capture",
          capability_id: "twitter.fetch_tweet",
          error: "tweet unavailable",
        }),
      },
    ]);

    assert.equal(decision.concluded, false);
    assert.match(terminalRunPlanBlocker(plan) ?? "", /twitter\.capture\/twitter\.fetch_tweet/);
  });

  it("still advances from legacy flattened Gear invoke payloads with domain kind and status fields", () => {
    const plan = tweetMediaPlan();

    const decision = advanceRunPlanAfterHostCompletions(plan, [
      {
        host_action_id: "host_action_fetch",
        tool_id: "gee.gear.invoke",
        status: "succeeded",
        summary: "twitter.capture twitter.fetch_tweet completed",
        result_json: JSON.stringify({
          gear_id: "twitter.capture",
          capability_id: "twitter.fetch_tweet",
          kind: "tweet",
          status: "completed",
          tweet_count: 1,
        }),
      },
    ]);

    assert.equal(decision.concluded, true);
    assert.equal(decision.status, "completed");
    assert.equal(decision.nextPlan?.current_stage_id, "stage_download_media");
  });

  it("does not advance media import stages without imported or existing item proof", () => {
    const plan = tweetMediaPlanAt("stage_import_media");

    const decision = advanceRunPlanAfterHostCompletions(plan, [
      {
        host_action_id: "host_action_import",
        tool_id: "gee.gear.invoke",
        status: "succeeded",
        summary: "media.library media.import_files completed",
        result_json: JSON.stringify({
          kind: "execution",
          tool_id: "gee.gear.invoke",
          status: "succeeded",
          gear_id: "media.library",
          capability_id: "media.import_files",
          action: "imported_files",
          imported_count: 0,
          existing_count: 0,
          available_count: 0,
          imported_items: [],
          existing_items: [],
          available_items: [],
        }),
      },
    ]);

    assert.equal(decision.concluded, false);
    assert.match(terminalRunPlanBlocker(plan) ?? "", /media\.library\/media\.import_files/);
  });

  it("advances media import stages when duplicate files already exist in the library", () => {
    const plan = tweetMediaPlanAt("stage_import_media");

    const decision = advanceRunPlanAfterHostCompletions(plan, [
      {
        host_action_id: "host_action_import",
        tool_id: "gee.gear.invoke",
        status: "succeeded",
        summary: "media.library media.import_files completed",
        result_json: JSON.stringify({
          kind: "execution",
          tool_id: "gee.gear.invoke",
          status: "succeeded",
          gear_id: "media.library",
          capability_id: "media.import_files",
          action: "import_noop",
          reason: "all_duplicates",
          imported_count: 0,
          existing_count: 2,
          available_count: 2,
          existing_items: [
            { id: "item-video", file_path: "/library/images/item-video.info/video.mp4" },
            { id: "item-image", file_path: "/library/images/item-image.info/image.jpg" },
          ],
        }),
      },
    ]);

    assert.equal(decision.concluded, true);
    assert.equal(decision.status, "completed");
    assert.equal(decision.nextPlan?.current_stage_id, "stage_save_bookmark");
  });
});
