import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { __sdkTurnRunnerTestHooks } from "./sdk-turn-runner.js";
import { geeGearInvoke } from "./tools/gears.js";

describe("Gee Gear invoke envelope normalization", () => {
  it("normalizes nested arguments.args into the canonical host args envelope", () => {
    const outcome = geeGearInvoke({
      tool_id: "gee.gear.invoke",
      arguments: {
        gear_id: "twitter.capture",
        capability_id: "twitter.fetch_tweet",
        arguments: {
          args: {
            url: "https://x.com/YaReYaRu30Life/status/2049545035176362120?s=20",
          },
        },
      },
    });

    assert.equal(outcome.kind, "completed");
    assert.deepEqual(outcome.kind === "completed" ? outcome.payload : {}, {
      intent: "gear.invoke",
      gear_id: "twitter.capture",
      capability_id: "twitter.fetch_tweet",
      args: {
        url: "https://x.com/YaReYaRu30Life/status/2049545035176362120?s=20",
      },
    });
  });

  it("normalizes top-level gear parameters before capability validation", () => {
    const outcome = geeGearInvoke({
      tool_id: "gee.gear.invoke",
      arguments: {
        gear_id: "smartyt.media",
        capability_id: "smartyt.download_now",
        url: "https://x.com/YaReYaRu30Life/status/2049545035176362120?s=20",
      },
    });

    assert.equal(outcome.kind, "completed");
    assert.deepEqual(
      outcome.kind === "completed" ? outcome.payload.args : undefined,
      {
        url: "https://x.com/YaReYaRu30Life/status/2049545035176362120?s=20",
      },
    );
  });

  it("rejects malformed top-level args before execution with a typed diagnostic", () => {
    const outcome = geeGearInvoke({
      tool_id: "gee.gear.invoke",
      arguments: {
        gear_id: "twitter.capture",
        capability_id: "twitter.fetch_tweet",
        args: "https://x.com/YaReYaRu30Life/status/2049545035176362120?s=20",
      },
    });

    assert.equal(outcome.kind, "error");
    assert.equal(outcome.kind === "error" ? outcome.code : "", "gear.args.args");
    assert.match(outcome.kind === "error" ? outcome.message : "", /must be an object/);
  });

  it("rejects conflicting Gear invoke envelopes before creating directive host actions", () => {
    const extraction = __sdkTurnRunnerTestHooks.extractHostActionDirectiveResult([
      "<gee-host-actions>",
      JSON.stringify({
        actions: [
          {
            tool_id: "gee.gear.invoke",
            arguments: {
              gear_id: "twitter.capture",
              capability_id: "twitter.fetch_tweet",
              args: {
                url: "https://x.com/YaReYaRu30Life/status/2049545035176362120?s=20",
              },
              arguments: {
                args: {
                  url: "https://x.com/YaReYaRu30Life/status/2049545035176362120",
                },
              },
            },
          },
        ],
      }),
      "</gee-host-actions>",
    ]);

    assert.equal(extraction.sawDirective, true);
    assert.deepEqual(extraction.actions, []);
    assert.equal(extraction.errors[0]?.tool_id, "gee.gear.invoke");
    assert.equal(extraction.errors[0]?.code, "gear.args.envelope");
    assert.match(extraction.errors[0]?.message ?? "", /conflicting/);
  });

  it("validates media generator create_task requires an explicit prompt", () => {
    const missing = geeGearInvoke({
      tool_id: "gee.gear.invoke",
      arguments: {
        gear_id: "media.generator",
        capability_id: "media_generator.create_task",
        args: {
          model: "gpt-image-2",
          aspect_ratio: "3:4",
          resolution: "2K",
        },
      },
    });

    assert.equal(missing.kind, "error");
    assert.equal(missing.kind === "error" ? missing.code : "", "gear.args.prompt");

    const valid = geeGearInvoke({
      tool_id: "gee.gear.invoke",
      arguments: {
        gear_id: "media.generator",
        capability_id: "media_generator.create_task",
        args: {
          prompt: "A soft pastel toy-house jelly beetle illustration",
          model: "image-2",
          aspect_ratio: "3:4",
          resolution: "2K",
        },
      },
    });

    assert.equal(valid.kind, "completed");
    assert.deepEqual(valid.kind === "completed" ? valid.payload : {}, {
      intent: "gear.invoke",
      gear_id: "media.generator",
      capability_id: "media_generator.create_task",
      args: {
        prompt: "A soft pastel toy-house jelly beetle illustration",
        model: "image-2",
        aspect_ratio: "3:4",
        resolution: "2K",
      },
    });
  });

  it("validates app icon generation requires an explicit source path", () => {
    const missing = geeGearInvoke({
      tool_id: "gee.gear.invoke",
      arguments: {
        gear_id: "app.icon.forge",
        capability_id: "app_icon.generate",
        args: {
          name: "AppIcon",
        },
      },
    });

    assert.equal(missing.kind, "error");
    assert.equal(missing.kind === "error" ? missing.code : "", "gear.args.source_path");

    const valid = geeGearInvoke({
      tool_id: "gee.gear.invoke",
      arguments: {
        gear_id: "app.icon.forge",
        capability_id: "app_icon.generate",
        args: {
          source_path: "/tmp/logo.png",
          output_dir: "/tmp/icons",
          name: "AppIcon",
        },
      },
    });

    assert.equal(valid.kind, "completed");
    assert.deepEqual(valid.kind === "completed" ? valid.payload : {}, {
      intent: "gear.invoke",
      gear_id: "app.icon.forge",
      capability_id: "app_icon.generate",
      args: {
        source_path: "/tmp/logo.png",
        output_dir: "/tmp/icons",
        name: "AppIcon",
      },
    });
  });
});
