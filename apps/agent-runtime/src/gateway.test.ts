import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { __gatewayTestHooks } from "./gateway.js";

describe("gateway protocol conversion", () => {
  it("maps Anthropic messages, tools, and tool choices into the Xenodia request shape", () => {
    const request = __gatewayTestHooks.toOpenAIChatCompletionRequest(
      {
        model: "sonnet",
        max_tokens: 64_000,
        system: [{ type: "text", text: "system guidance" }],
        messages: [
          {
            role: "user",
            content: [{ type: "text", text: "inspect the repo" }],
          },
          {
            role: "assistant",
            content: [
              {
                type: "tool_use",
                id: "toolu_1",
                name: "Bash",
                input: { command: "pwd" },
              },
            ],
          },
          {
            role: "user",
            content: [
              {
                type: "tool_result",
                tool_use_id: "toolu_1",
                content: [{ type: "text", text: "/tmp/project" }],
              },
            ],
          },
        ],
        tools: [
          {
            name: "Bash",
            description: "Run a shell command",
            input_schema: {
              type: "object",
              properties: {
                command: { type: "string" },
              },
            },
          },
        ],
        tool_choice: {
          type: "tool",
          name: "Bash",
        },
        temperature: 0.2,
      },
      {
        xenodiaApiKey: "test-key",
      },
    );

    assert.equal(request.model, "gpt-5.4");
    assert.equal(request.max_completion_tokens, 32_000);
    assert.equal(request.temperature, 0.2);
    assert.deepEqual(request.tool_choice, {
      type: "function",
      function: {
        name: "Bash",
      },
    });
    assert.equal(request.tools?.[0]?.function.name, "Bash");
    assert.deepEqual(request.messages, [
      {
        role: "system",
        content: "system guidance",
      },
      {
        role: "user",
        content: "inspect the repo",
      },
      {
        role: "assistant",
        content: null,
        tool_calls: [
          {
            id: "toolu_1",
            type: "function",
            function: {
              name: "Bash",
              arguments: "{\"command\":\"pwd\"}",
            },
          },
        ],
      },
      {
        role: "tool",
        tool_call_id: "toolu_1",
        content: "/tmp/project",
      },
    ]);
  });

  it("converts Xenodia tool calls back into Anthropic content blocks", () => {
    const message = __gatewayTestHooks.buildAnthropicMessageFromXenodia(
      {
        model: "claude-sonnet-4-6",
        messages: [{ role: "user", content: "open the file" }],
      },
      {
        id: "chatcmpl_1",
        choices: [
          {
            message: {
              content: "I need a file read.",
              tool_calls: [
                {
                  id: "call_1",
                  type: "function",
                  function: {
                    name: "Read",
                    arguments: "{\"file_path\":\"README.md\"}",
                  },
                },
              ],
            },
          },
        ],
        usage: {
          prompt_tokens: 7,
          completion_tokens: 3,
        },
      },
    );

    assert.equal(message.id, "chatcmpl_1");
    assert.equal(message.model, "claude-sonnet-4-6");
    assert.equal(message.stop_reason, "tool_use");
    assert.deepEqual(message.usage, {
      input_tokens: 7,
      cache_creation_input_tokens: null,
      cache_read_input_tokens: null,
      output_tokens: 3,
      server_tool_use: null,
    });
    assert.deepEqual(message.content, [
      {
        type: "text",
        text: "I need a file read.",
        citations: null,
      },
      {
        type: "tool_use",
        id: "call_1",
        name: "Read",
        input: {
          file_path: "README.md",
        },
        caller: "direct",
      },
    ]);
  });

  it("keeps non-Claude model names unless an explicit override is configured", () => {
    assert.equal(
      __gatewayTestHooks.resolveBackendModel("gpt-5.4", undefined),
      "gpt-5.4",
    );
    assert.equal(
      __gatewayTestHooks.resolveBackendModel("sonnet", "gpt-5.4-mini"),
      "gpt-5.4-mini",
    );
  });

  it("uses a bounded upstream timeout for the local Xenodia gateway", () => {
    assert.equal(
      __gatewayTestHooks.resolveRequestTimeoutMs({ xenodiaApiKey: "test-key" }),
      45_000,
    );
    assert.equal(
      __gatewayTestHooks.resolveRequestTimeoutMs({
        xenodiaApiKey: "test-key",
        requestTimeoutSeconds: 12.2,
      }),
      12_200,
    );
  });
});
