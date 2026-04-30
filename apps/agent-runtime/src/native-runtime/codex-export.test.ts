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
  it("reports only implemented read-only export tools as available", async () => {
    const raw = await handleNativeRuntimeCommand("codex-export-status");
    const result = JSON.parse(raw) as {
      status: string;
      implemented_tools: string[];
      planned_tools: string[];
    };

    assert.equal(result.status, "success");
    assert.deepEqual(result.implemented_tools, [
      "gee_status",
      "gee_list_capabilities",
      "gee_describe_capability",
    ]);
    assert.deepEqual(result.planned_tools, [
      "gee_invoke_capability",
      "gee_open_surface",
      "gee_get_invocation",
    ]);
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
