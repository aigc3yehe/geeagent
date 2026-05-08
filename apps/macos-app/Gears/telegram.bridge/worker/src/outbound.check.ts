import assert from "node:assert/strict";
import { describe, it } from "node:test";

import type { TelegramBridgeAccount } from "./config.js";
import {
  sendTelegramTextProjection,
} from "./outbound.js";

const account: TelegramBridgeAccount = {
  id: "gee_direct_default",
  role: "gee_direct",
  botUsername: "gee_direct_bot",
  transport: { mode: "polling" },
};

describe("Telegram outbound projection", () => {
  it("sends text through the configured account token and stable idempotency key", async () => {
    const sends: unknown[] = [];
    const result = await sendTelegramTextProjection(
      {
        account,
        chatId: "777",
        updateId: 9001,
        message: "Hello from Gee runtime.",
        idempotencyKey: "telegram:reply:9001",
      },
      {
        tokenProvider: async () => "gee-token",
        telegramClient: {
          async sendMessage(input) {
            sends.push(input);
            return {
              ok: true,
              telegramMessageId: "9002",
              sentAt: "2026-05-02T12:00:00.000Z",
            };
          },
        },
      },
    );

    assert.equal(result.status, "success");
    assert.equal(result.fallback_attempted, false);
    assert.deepEqual(sends, [
      {
        token: "gee-token",
        target: { kind: "chat_id", value: "777" },
        message: "Hello from Gee runtime.",
        disableWebPreview: true,
        idempotencyKey: "telegram:reply:9001",
      },
    ]);
  });

  it("fails before Telegram delivery when the account token is missing", async () => {
    let sendCount = 0;
    const result = await sendTelegramTextProjection(
      {
        account,
        chatId: "777",
        updateId: 9001,
        message: "Hello from Gee runtime.",
        idempotencyKey: "telegram:reply:9001",
      },
      {
        tokenProvider: async () => undefined,
        telegramClient: {
          async sendMessage() {
            sendCount += 1;
            throw new Error("send should not be called");
          },
        },
      },
    );

    assert.equal(result.status, "failed");
    assert.equal(result.error?.code, "token_missing");
    assert.equal(result.fallback_attempted, false);
    assert.equal(sendCount, 0);
  });

  it("maps retryable Telegram failures to degraded results without fallback", async () => {
    const result = await sendTelegramTextProjection(
      {
        account,
        chatId: "777",
        updateId: 9001,
        message: "Hello from Gee runtime.",
        idempotencyKey: "telegram:reply:9001",
      },
      {
        tokenProvider: async () => "gee-token",
        telegramClient: {
          async sendMessage() {
            return {
              ok: false,
              code: "telegram_rate_limited",
              message: "Telegram asked GeeAgent to retry later.",
              retryAfterMs: 2000,
            };
          },
        },
      },
    );

    assert.equal(result.status, "degraded");
    assert.equal(result.error?.code, "telegram_rate_limited");
    assert.equal(result.error?.retryAfterMs, 2000);
    assert.equal(result.fallback_attempted, false);
  });
});
