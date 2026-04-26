import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { runtimeProjectPath } from "./native-runtime/paths.js";
import {
  DEFAULT_SDK_AUTO_APPROVE_TOOLS,
  DEFAULT_SDK_DISALLOWED_TOOLS,
} from "./sdk-tool-policy.js";
import { __sessionTestHooks } from "./session.js";

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
  });

  it("normalizes non-object tool input into an empty object", () => {
    assert.deepEqual(__sessionTestHooks.normalizeToolInput("pwd"), {});
    assert.deepEqual(__sessionTestHooks.normalizeToolInput(["pwd"]), {});
    assert.deepEqual(__sessionTestHooks.normalizeToolInput({ command: "pwd" }), {
      command: "pwd",
    });
  });

  it("removes empty Read page selectors before the SDK executes the tool", () => {
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

  it("summarizes SDK tool result text blocks without losing multi-line output", () => {
    const summary = __sessionTestHooks.summarizeToolResultContent([
      { type: "text", text: "line one" },
      { type: "text", text: "line two" },
    ]);

    assert.equal(summary, "line one\nline two");
  });

  it("removes SDK TodoWrite from GeeAgent's main runtime tool context", () => {
    assert.ok(DEFAULT_SDK_DISALLOWED_TOOLS.includes("TodoWrite"));
    assert.equal(DEFAULT_SDK_DISALLOWED_TOOLS.includes("Bash"), false);
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
