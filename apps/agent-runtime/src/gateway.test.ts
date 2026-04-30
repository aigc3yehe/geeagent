import assert from "node:assert/strict";
import http, {
  type IncomingMessage,
  type ServerResponse,
} from "node:http";
import type { AddressInfo } from "node:net";
import { describe, it } from "node:test";

import { __gatewayTestHooks, startAnthropicGateway } from "./gateway.js";

async function readRequestBody(request: IncomingMessage): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of request) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  return Buffer.concat(chunks).toString("utf8");
}

async function listen(server: http.Server): Promise<number> {
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      server.off("error", reject);
      resolve();
    });
  });
  const address = server.address() as AddressInfo | null;
  assert.ok(address);
  return address.port;
}

async function closeServer(server: http.Server): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
}

function writeJsonResponse(
  response: ServerResponse,
  statusCode: number,
  payload: unknown,
): void {
  response.writeHead(statusCode, { "Content-Type": "application/json" });
  response.end(JSON.stringify(payload));
}

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

  it("normalizes tool-call input at provider ingress before it reaches the SDK", () => {
    const message = __gatewayTestHooks.buildAnthropicMessageFromXenodia(
      {
        model: "claude-sonnet-4-6",
        messages: [{ role: "user", content: "read the skill" }],
      },
      {
        id: "chatcmpl_read_pages",
        choices: [
          {
            message: {
              content: null,
              tool_calls: [
                {
                  id: "call_empty_pages",
                  type: "function",
                  function: {
                    name: "Read",
                    arguments:
                      "{\"file_path\":\"/tmp/SKILL.md\",\"limit\":2500,\"offset\":0,\"pages\":\"\"}",
                  },
                },
                {
                  id: "call_valid_pages",
                  type: "function",
                  function: {
                    name: "Read",
                    arguments:
                      "{\"file_path\":\"/tmp/doc.pdf\",\"pages\":\"1-3\"}",
                  },
                },
              ],
            },
          },
        ],
      },
    );

    assert.deepEqual(message.content, [
      {
        type: "tool_use",
        id: "call_empty_pages",
        name: "Read",
        input: {
          file_path: "/tmp/SKILL.md",
          limit: 2500,
          offset: 0,
        },
        caller: "direct",
      },
      {
        type: "tool_use",
        id: "call_valid_pages",
        name: "Read",
        input: {
          file_path: "/tmp/doc.pdf",
          pages: "1-3",
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

  it("uses runtime token and temperature defaults when the SDK request omits them", () => {
    const request = __gatewayTestHooks.toOpenAIChatCompletionRequest(
      {
        model: "sonnet",
        messages: [{ role: "user", content: "hello" }],
      },
      {
        xenodiaApiKey: "test-key",
        maxCompletionTokens: 700,
        temperature: 0.35,
      },
    );

    assert.equal(request.max_completion_tokens, 700);
    assert.equal(request.temperature, 0.35);
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

  it("surfaces the primary upstream failure instead of retrying another model", async () => {
    const seenModels: string[] = [];
    const upstream = http.createServer(
      (request: IncomingMessage, response: ServerResponse) => {
        void readRequestBody(request).then((raw) => {
          const payload = JSON.parse(raw) as { model?: string };
          if (payload.model) {
            seenModels.push(payload.model);
          }
          if (seenModels.length === 1) {
            writeJsonResponse(response, 500, {
              error: { message: "primary unavailable" },
            });
            return;
          }
          writeJsonResponse(response, 200, { id: "unexpected_retry", choices: [] });
        });
      },
    );
    const port = await listen(upstream);
    const gateway = await startAnthropicGateway({
      xenodiaApiKey: "test-key",
      backendUrl: `http://127.0.0.1:${port}/v1/chat/completions`,
      modelOverride: "primary-model",
      requestTimeoutSeconds: 1,
      maxCompletionTokens: 700,
    });

    try {
      const response = await fetch(`${gateway.baseUrl}/v1/messages`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-api-key": gateway.apiKey,
        },
        body: JSON.stringify({
          model: "sonnet",
          messages: [{ role: "user", content: "hello" }],
          stream: false,
        }),
      });

      assert.equal(response.status, 500);
      const body = (await response.json()) as { error?: { message?: string } };
      assert.match(body.error?.message ?? "", /primary unavailable/);
      assert.deepEqual(seenModels, ["primary-model"]);
    } finally {
      await gateway.close();
      await closeServer(upstream);
    }
  });
});
