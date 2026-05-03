import assert from "node:assert/strict";
import { mkdtemp, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";

import { handleNativeRuntimeCommand } from "./commands.js";

async function tempConfigDir(): Promise<string> {
  return mkdtemp(join(tmpdir(), "geeagent-channel-ingress-"));
}

describe("native runtime channel ingress", () => {
  it("submits Telegram direct messages through a stable channel conversation", async () => {
    const configDir = await tempConfigDir();
    const previousKey = process.env.XENODIA_API_KEY;
    delete process.env.XENODIA_API_KEY;
    try {
      const raw = await handleNativeRuntimeCommand(
        "submit-channel-message",
        [
          JSON.stringify({
            source: "telegram.bridge",
            role: "gee_direct",
            channelIdentity: "telegram:gee_direct_default:bot:42:dm:777",
            message: {
              idempotencyKey: "telegram:update:9001",
              telegramUpdateId: 9001,
              chatId: "777",
              messageId: "12",
              fromUserId: "1234",
              text: "hello from telegram",
              attachments: [],
            },
            security: {
              decision: "allowed",
              policyId: "paired-dm",
            },
            projection: {
              surface: "telegram",
              replyTarget: {
                chatId: "777",
                messageId: "12",
              },
            },
          }),
        ],
        { configDir },
      );
      const snapshot = JSON.parse(raw);
      const store = JSON.parse(await readFile(join(configDir, "runtime-store.json"), "utf8"));

      assert.equal(snapshot.active_conversation.title, "Telegram 777");
      assert.deepEqual(snapshot.active_conversation.tags, ["telegram.bridge", "gee_direct"]);
      assert.equal(snapshot.active_conversation.messages.at(-2).role, "user");
      assert.equal(snapshot.active_conversation.messages.at(-2).content, "hello from telegram");
      assert.equal(snapshot.active_conversation.messages.at(-1).role, "assistant");
      assert.match(snapshot.active_conversation.messages.at(-1).content, /SDK runtime is not live/i);
      assert.equal(snapshot.last_request_outcome.source, "telegram.bridge");
      assert.equal(snapshot.last_run_state.fallback_attempted, false);
      assert.deepEqual(store.channel_bindings, [
        {
          source: "telegram.bridge",
          role: "gee_direct",
          channel_identity: "telegram:gee_direct_default:bot:42:dm:777",
          conversation_id: snapshot.active_conversation.conversation_id,
          created_at: store.channel_bindings[0].created_at,
          updated_at: store.channel_bindings[0].updated_at,
        },
      ]);

      const ingress = snapshot.transcript_events.find(
        (event: { payload?: { kind?: string } }) => event.payload?.kind === "channel_message_received",
      );
      assert.equal(ingress.run_id, snapshot.last_run_state.run_id);
      assert.deepEqual(ingress.payload.channel, {
        source: "telegram.bridge",
        role: "gee_direct",
        channel_identity: "telegram:gee_direct_default:bot:42:dm:777",
        idempotency_key: "telegram:update:9001",
        telegram_update_id: 9001,
        chat_id: "777",
        message_id: "12",
        from_user_id: "1234",
        security_decision: "allowed",
        security_policy_id: "paired-dm",
        projection_surface: "telegram",
        reply_target: {
          chatId: "777",
          messageId: "12",
        },
        fallback_attempted: false,
      });

      const duplicateRaw = await handleNativeRuntimeCommand(
        "submit-channel-message",
        [
          JSON.stringify({
            source: "telegram.bridge",
            role: "gee_direct",
            channelIdentity: "telegram:gee_direct_default:bot:42:dm:777",
            message: {
              idempotencyKey: "telegram:update:9001",
              telegramUpdateId: 9001,
              chatId: "777",
              messageId: "12",
              fromUserId: "1234",
              text: "hello from telegram",
              attachments: [],
            },
            security: {
              decision: "allowed",
              policyId: "paired-dm",
            },
            projection: {
              surface: "telegram",
              replyTarget: {
                chatId: "777",
                messageId: "12",
              },
            },
          }),
        ],
        { configDir },
      );
      const duplicateSnapshot = JSON.parse(duplicateRaw);
      const duplicateStore = JSON.parse(await readFile(join(configDir, "runtime-store.json"), "utf8"));
      assert.equal(
        duplicateSnapshot.active_conversation.messages.length,
        snapshot.active_conversation.messages.length,
      );
      assert.equal(duplicateSnapshot.last_run_state.duplicate_channel_message, true);
      assert.equal(duplicateStore.channel_messages.length, 1);
    } finally {
      if (previousKey === undefined) {
        delete process.env.XENODIA_API_KEY;
      } else {
        process.env.XENODIA_API_KEY = previousKey;
      }
    }
  });
});
