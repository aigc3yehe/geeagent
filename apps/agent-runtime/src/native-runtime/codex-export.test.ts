import assert from "node:assert/strict";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";

import { handleNativeRuntimeCommand } from "./commands.js";

async function writeGearManifest(
  root: string,
  gearID: string,
  manifest: Record<string, unknown>,
): Promise<void> {
  const gearRoot = join(root, gearID);
  await mkdir(gearRoot, { recursive: true });
  await writeFile(join(gearRoot, "gear.json"), JSON.stringify(manifest, null, 2), "utf8");
}

function exportedGearManifest(): Record<string, unknown> {
  return {
    schema: "gee.gear.v1",
    id: "codex.safe",
    name: "Codex Safe Gear",
    description: "Fixture gear for Codex export tests.",
    developer: "Gee",
    version: "0.1.0",
    kind: "atmosphere",
    entry: {
      type: "native",
      native_id: "codex.safe",
    },
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
          side_effect: "read_only",
          exports: {
            codex: {
              enabled: true,
              risk: "low",
              requires_approval: false,
              skill_hint: "Use when Codex needs the safe fixture value.",
            },
          },
        },
        {
          id: "internal.write",
          title: "Internal write",
          description: "Not exported to Codex.",
          examples: ["Do an internal write"],
        },
        {
          id: "unsafe.native",
          title: "Unsafe native",
          description: "Explicitly hidden from Codex.",
          examples: ["Drive native state"],
          exports: {
            codex: {
              enabled: false,
              reason: "Requires native UI state Codex cannot inspect.",
            },
          },
        },
      ],
    },
  };
}

describe("Codex capability export projection", () => {
  it("reports the implemented MCP tool surface and live-bridge requirements", async () => {
    const raw = await handleNativeRuntimeCommand("codex-export-status");
    const result = JSON.parse(raw) as {
      status: string;
      implemented_tools: string[];
      planned_tools: string[];
      available_mcp_tools: string[];
      bridge_required_tools: string[];
    };

    assert.equal(result.status, "success");
    assert.deepEqual(result.implemented_tools, [
      "gee_status",
      "gee_list_capabilities",
      "gee_describe_capability",
      "gee_invoke_capability",
      "gee_open_surface",
      "gee_get_invocation",
    ]);
    assert.deepEqual(result.planned_tools, []);
    assert.deepEqual(result.available_mcp_tools, [
      "gee_status",
      "gee_list_capabilities",
      "gee_describe_capability",
      "gee_invoke_capability",
      "gee_open_surface",
      "gee_get_invocation",
    ]);
    assert.deepEqual(result.bridge_required_tools, [
      "gee_invoke_capability",
      "gee_open_surface",
    ]);
  });

  it("includes the bundled first-party capabilities explicitly exported to Codex", async () => {
    const raw = await handleNativeRuntimeCommand("codex-export-list-capabilities", [
      JSON.stringify({ detail: "schema" }),
    ]);
    const result = JSON.parse(raw) as {
      status: string;
      capabilities: Array<{
        capability_ref: string;
        risk?: string;
        requires_approval?: boolean;
        side_effect?: string;
        input_schema?: Record<string, unknown>;
        output_schema?: Record<string, unknown>;
        permissions?: string[];
      }>;
    };

    assert.equal(result.status, "success");
    const refs = new Set(result.capabilities.map((capability) => capability.capability_ref));
    assert.equal(refs.has("bookmark.vault/bookmark.save"), true);
    assert.equal(refs.has("media.generator/media_generator.list_models"), true);
    assert.equal(refs.has("media.generator/media_generator.get_task"), true);
    assert.equal(refs.has("media.generator/media_generator.create_task"), true);
    assert.equal(refs.has("media.library/media.filter"), true);
    assert.equal(refs.has("media.library/media.focus_folder"), true);
    assert.equal(refs.has("media.library/media.import_files"), true);
    assert.equal(refs.has("app.icon.forge/app_icon.generate"), true);
    assert.equal(refs.has("telegram.bridge/telegram_bridge.status"), true);
    assert.equal(refs.has("telegram.bridge/telegram_push.list_channels"), true);
    assert.equal(refs.has("telegram.bridge/telegram_push.send_message"), true);
    assert.equal(refs.has("telegram.bridge/telegram_push.send_file"), true);
    assert.equal(refs.has("telegram.bridge/telegram_push.upsert_channel"), false);
    assert.equal(refs.has("todo.manager/todo.create"), true);
    assert.equal(refs.has("todo.manager/todo.query"), true);
    assert.equal(refs.has("todo.manager/todo.update"), true);
    assert.equal(refs.has("todo.manager/todo.delete"), true);

    const focusFolder = result.capabilities.find(
      (capability) => capability.capability_ref === "media.library/media.focus_folder",
    );
    assert.equal(focusFolder?.risk, "low");
    assert.equal(focusFolder?.requires_approval, false);
    assert.equal(focusFolder?.side_effect, "native_view_state");
    assert.deepEqual(focusFolder?.input_schema?.required, ["folder_name"]);

    const importFiles = result.capabilities.find(
      (capability) => capability.capability_ref === "media.library/media.import_files",
    );
    assert.equal(importFiles?.risk, "high");
    assert.equal(importFiles?.requires_approval, false);
    assert.equal(importFiles?.side_effect, "media_library.import_files");
    assert.deepEqual(importFiles?.input_schema?.required, ["paths"]);
    assert.deepEqual(importFiles?.permissions, [
      "filesystem.read.user_selected",
      "media.library.write",
      "gear_data.write",
      "gear.surface.view_state",
    ]);

    const bookmarkSave = result.capabilities.find(
      (capability) => capability.capability_ref === "bookmark.vault/bookmark.save",
    );
    assert.equal(bookmarkSave?.risk, "medium");
    assert.equal(bookmarkSave?.requires_approval, false);
    assert.equal(bookmarkSave?.side_effect, "write_gear_data");
    assert.deepEqual(bookmarkSave?.input_schema?.required, ["content"]);
    assert.deepEqual(bookmarkSave?.permissions, ["gear_data.write", "network.metadata"]);

    const todoCreate = result.capabilities.find(
      (capability) => capability.capability_ref === "todo.manager/todo.create",
    );
    assert.equal(todoCreate?.risk, "medium");
    assert.equal(todoCreate?.requires_approval, false);
    assert.equal(todoCreate?.side_effect, "write_gear_data");
    assert.deepEqual(todoCreate?.input_schema?.required, ["title"]);
    assert.deepEqual(todoCreate?.permissions, ["gear_data.write", "notification.schedule"]);

    const todoQuery = result.capabilities.find(
      (capability) => capability.capability_ref === "todo.manager/todo.query",
    );
    assert.equal(todoQuery?.risk, "low");
    assert.equal(todoQuery?.side_effect, "read_only");
    assert.deepEqual(todoQuery?.permissions, ["gear_data.read"]);

    const todoDelete = result.capabilities.find(
      (capability) => capability.capability_ref === "todo.manager/todo.delete",
    );
    assert.equal(todoDelete?.risk, "high");
    assert.deepEqual(todoDelete?.input_schema?.required, ["task_id"]);

    const createTask = result.capabilities.find(
      (capability) => capability.capability_ref === "media.generator/media_generator.create_task",
    );
    assert.equal(createTask?.risk, "high");
    assert.equal(createTask?.requires_approval, false);
    assert.equal(createTask?.side_effect, "provider_task.create");
    assert.deepEqual(createTask?.input_schema?.required, ["prompt"]);
    const createTaskProperties = createTask?.input_schema?.properties as
      | Record<string, { enum?: string[]; minimum?: number; maximum?: number; maxItems?: number }>
      | undefined;
    assert.deepEqual(createTaskProperties?.model?.enum, [
      "nano-banana-pro",
      "gpt-image-2",
      "image-2",
      "veo3.1",
      "veo3.1_fast",
      "veo3.1_lite",
      "seedance-2",
      "seedance-2-fast",
      "seedance2.0",
      "seedance2.0-fast",
    ]);
    assert.deepEqual(createTaskProperties?.category?.enum, ["image", "video"]);
    assert.equal(createTaskProperties?.batch_count?.minimum, 1);
    assert.equal(createTaskProperties?.batch_count?.maximum, 4);
    assert.equal(createTaskProperties?.duration?.minimum, 4);
    assert.equal(createTaskProperties?.duration?.maximum, 15);
    assert.ok(createTaskProperties?.aspect_ratio?.enum?.includes("3:4"));
    assert.ok(createTaskProperties?.aspect_ratio?.enum?.includes("adaptive"));
    assert.ok(createTaskProperties?.resolution?.enum?.includes("2K"));
    assert.ok(createTaskProperties?.resolution?.enum?.includes("720p"));
    assert.equal(createTaskProperties?.reference_urls?.maxItems, 16);
    assert.equal(createTaskProperties?.reference_paths?.maxItems, 16);
    assert.equal(createTaskProperties?.reference_video_urls?.maxItems, 3);
    assert.equal(createTaskProperties?.reference_audio_urls?.maxItems, 3);
    assert.ok(createTaskProperties?.generation_type?.enum?.includes("REFERENCE_2_VIDEO"));
    assert.equal("nsfw_checker" in (createTaskProperties ?? {}), true);
    assert.deepEqual(createTask?.permissions, [
      "network.xenodia",
      "provider.media_generation",
      "gear_data.write",
    ]);

    const appIconGenerate = result.capabilities.find(
      (capability) => capability.capability_ref === "app.icon.forge/app_icon.generate",
    );
    assert.equal(appIconGenerate?.risk, "high");
    assert.equal(appIconGenerate?.requires_approval, false);
    assert.equal(appIconGenerate?.side_effect, "filesystem.write.user_selected");
    assert.deepEqual(appIconGenerate?.input_schema?.required, ["source_path"]);
    assert.deepEqual(appIconGenerate?.permissions, [
      "filesystem.read.user_selected",
      "filesystem.write.user_selected",
      "process.spawn",
    ]);

    const telegramPush = result.capabilities.find(
      (capability) => capability.capability_ref === "telegram.bridge/telegram_push.send_message",
    );
    assert.equal(telegramPush?.risk, "medium");
    assert.equal(telegramPush?.requires_approval, false);
    assert.equal(telegramPush?.side_effect, "network.telegram.send");
    assert.deepEqual(telegramPush?.input_schema?.required, [
      "channel_id",
      "message",
      "idempotency_key",
    ]);
    assert.deepEqual(telegramPush?.permissions, [
      "network.telegram",
      "secret.telegram.read",
      "gear_data.read",
      "gear_data.write",
    ]);

    const telegramPushFile = result.capabilities.find(
      (capability) => capability.capability_ref === "telegram.bridge/telegram_push.send_file",
    );
    assert.equal(telegramPushFile?.risk, "high");
    assert.equal(telegramPushFile?.requires_approval, false);
    assert.equal(telegramPushFile?.side_effect, "network.telegram.send_file");
    assert.deepEqual(telegramPushFile?.input_schema?.required, [
      "channel_id",
      "file_path",
      "idempotency_key",
    ]);
    assert.deepEqual(telegramPushFile?.output_schema?.required, [
      "status",
      "fallback_attempted",
      "error",
    ]);
    assert.deepEqual(telegramPushFile?.permissions, [
      "filesystem.read.user_selected",
      "network.telegram",
      "secret.telegram.read",
      "gear_data.read",
      "gear_data.write",
    ]);
  });

  it("finds bundled Gear manifests even when Codex starts from a project cwd", async () => {
    const previousCwd = process.cwd();
    const projectCwd = await mkdtemp(join(tmpdir(), "geeagent-codex-project-"));
    try {
      process.chdir(projectCwd);
      const raw = await handleNativeRuntimeCommand("codex-export-list-capabilities", [
        JSON.stringify({ detail: "schema" }),
      ]);
      const result = JSON.parse(raw) as {
        status: string;
        capabilities: Array<{ capability_ref: string }>;
      };

      assert.equal(result.status, "success");
      assert.equal(
        result.capabilities.some(
          (capability) => capability.capability_ref === "media.generator/media_generator.list_models",
        ),
        true,
      );
    } finally {
      process.chdir(previousCwd);
    }
  });

  it("lists only explicitly Codex-exported Gear capabilities", async () => {
    const root = await mkdtemp(join(tmpdir(), "geeagent-codex-export-"));
    await writeGearManifest(root, "codex.safe", exportedGearManifest());
    await writeGearManifest(root, "codex.disabled", {
      ...exportedGearManifest(),
      id: "codex.disabled",
      name: "Disabled Codex Gear",
      agent: {
        enabled: false,
        capabilities: [
          {
            id: "disabled.query",
            title: "Disabled query",
            description: "Should not be listed.",
            exports: {
              codex: {
                enabled: true,
                risk: "low",
              },
            },
          },
        ],
      },
    });

    const raw = await handleNativeRuntimeCommand("codex-export-list-capabilities", [
      JSON.stringify({ gear_roots: [root] }),
    ]);
    const result = JSON.parse(raw) as {
      status: string;
      standard: string;
      capabilities: Array<{
        capability_ref: string;
        gear_id: string;
        gear_name: string;
        capability_id: string;
        title: string;
        description: string;
        examples: string[];
        risk?: string;
        requires_approval?: boolean;
        side_effect?: string;
        skill_hint?: string;
      }>;
    };

    assert.equal(result.status, "success");
    assert.equal(result.standard, "gee.capability_export.v0.1");
    assert.deepEqual(
      result.capabilities.map((capability) => capability.capability_ref),
      ["codex.safe/safe.query"],
    );
    assert.deepEqual(result.capabilities[0], {
      capability_ref: "codex.safe/safe.query",
      gear_id: "codex.safe",
      gear_name: "Codex Safe Gear",
      capability_id: "safe.query",
      title: "Safe query",
      description: "Read a safe value.",
      examples: ["Read safe value"],
      risk: "low",
      requires_approval: false,
      side_effect: "read_only",
      skill_hint: "Use when Codex needs the safe fixture value.",
    });
  });

  it("deduplicates capability refs when multiple manifest roots expose the same Gear", async () => {
    const firstRoot = await mkdtemp(join(tmpdir(), "geeagent-codex-export-a-"));
    const secondRoot = await mkdtemp(join(tmpdir(), "geeagent-codex-export-b-"));
    await writeGearManifest(firstRoot, "codex.safe", exportedGearManifest());
    await writeGearManifest(secondRoot, "codex.safe", exportedGearManifest());

    const raw = await handleNativeRuntimeCommand("codex-export-list-capabilities", [
      JSON.stringify({ gear_roots: [firstRoot, secondRoot], gear_id: "codex.safe" }),
    ]);
    const result = JSON.parse(raw) as {
      status: string;
      capabilities: Array<{ capability_ref: string }>;
    };

    assert.equal(result.status, "success");
    assert.deepEqual(
      result.capabilities.map((capability) => capability.capability_ref),
      ["codex.safe/safe.query"],
    );
  });

  it("describes one exported capability without exposing hidden siblings", async () => {
    const root = await mkdtemp(join(tmpdir(), "geeagent-codex-export-"));
    await writeGearManifest(root, "codex.safe", exportedGearManifest());

    const raw = await handleNativeRuntimeCommand("codex-export-describe-capability", [
      JSON.stringify({
        gear_roots: [root],
        capability_ref: "codex.safe/safe.query",
      }),
    ]);
    const result = JSON.parse(raw) as {
      status: string;
      capability?: {
        capability_ref: string;
        input_schema?: Record<string, unknown>;
      };
    };

    assert.equal(result.status, "success");
    assert.equal(result.capability?.capability_ref, "codex.safe/safe.query");
    assert.deepEqual(result.capability?.input_schema, {
      type: "object",
      properties: {
        key: { type: "string" },
      },
    });

    const hiddenRaw = await handleNativeRuntimeCommand("codex-export-describe-capability", [
      JSON.stringify({
        gear_roots: [root],
        capability_ref: "codex.safe/internal.write",
      }),
    ]);
    const hidden = JSON.parse(hiddenRaw) as { status: string; code?: string };
    assert.equal(hidden.status, "failed");
    assert.equal(hidden.code, "gee.codex_export.capability_not_found");
  });
});
