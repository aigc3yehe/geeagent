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

  it("accepts Swift snake_case Telegram channel payloads", async () => {
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
            channel_identity: "telegram:gee_direct_default:chat:7973901539",
            message: {
              idempotency_key: "telegram:update:491738594",
              telegram_update_id: 491738594,
              chat_id: "7973901539",
              message_id: "5",
              from_user_id: "7973901539",
              text: "Who are you?",
              attachments: [],
            },
            security: {
              decision: "allowed",
              policy_id: "telegram.allowlist",
            },
            projection: {
              surface: "telegram",
              reply_target: {
                chat_id: "7973901539",
                message_id: "5",
              },
            },
          }),
        ],
        { configDir },
      );
      const snapshot = JSON.parse(raw);
      const ingress = snapshot.transcript_events.find(
        (event: { payload?: { kind?: string } }) => event.payload?.kind === "channel_message_received",
      );

      assert.equal(snapshot.active_conversation.title, "Telegram 7973901539");
      assert.equal(snapshot.active_conversation.messages.at(-2).content, "Who are you?");
      assert.equal(ingress.payload.channel.channel_identity, "telegram:gee_direct_default:chat:7973901539");
      assert.equal(ingress.payload.channel.idempotency_key, "telegram:update:491738594");
      assert.deepEqual(ingress.payload.channel.reply_target, {
        chat_id: "7973901539",
        message_id: "5",
      });
    } finally {
      if (previousKey === undefined) {
        delete process.env.XENODIA_API_KEY;
      } else {
        process.env.XENODIA_API_KEY = previousKey;
      }
    }
  });

  it("resets a Telegram direct channel conversation when the user sends /new", async () => {
    const configDir = await tempConfigDir();
    const previousKey = process.env.XENODIA_API_KEY;
    delete process.env.XENODIA_API_KEY;
    try {
      const firstRaw = await handleNativeRuntimeCommand(
        "submit-channel-message",
        [
          JSON.stringify({
            source: "telegram.bridge",
            role: "gee_direct",
            channelIdentity: "telegram:gee_direct_default:chat:7973901539",
            message: {
              idempotencyKey: "telegram:update:1001",
              telegramUpdateId: 1001,
              chatId: "7973901539",
              messageId: "8",
              fromUserId: "7973901539",
              text: "remember this old Telegram turn",
              attachments: [],
            },
            security: {
              decision: "allowed",
              policyId: "telegram.allowlist",
            },
            projection: {
              surface: "telegram",
              replyTarget: {
                chatId: "7973901539",
                messageId: "8",
              },
            },
          }),
        ],
        { configDir },
      );
      const firstSnapshot = JSON.parse(firstRaw);
      const previousConversationId = firstSnapshot.active_conversation.conversation_id;

      const resetRaw = await handleNativeRuntimeCommand(
        "submit-channel-message",
        [
          JSON.stringify({
            source: "telegram.bridge",
            role: "gee_direct",
            channelIdentity: "telegram:gee_direct_default:chat:7973901539",
            message: {
              idempotencyKey: "telegram:update:1002",
              telegramUpdateId: 1002,
              chatId: "7973901539",
              messageId: "9",
              fromUserId: "7973901539",
              text: "/new",
              attachments: [],
            },
            security: {
              decision: "allowed",
              policyId: "telegram.allowlist",
            },
            projection: {
              surface: "telegram",
              replyTarget: {
                chatId: "7973901539",
                messageId: "9",
              },
            },
          }),
        ],
        { configDir },
      );

      const resetSnapshot = JSON.parse(resetRaw);
      const resetStore = JSON.parse(await readFile(join(configDir, "runtime-store.json"), "utf8"));
      const messages = resetSnapshot.active_conversation.messages;

      assert.notEqual(resetSnapshot.active_conversation.conversation_id, previousConversationId);
      assert.equal(messages.length, 1);
      assert.equal(messages[0].role, "assistant");
      assert.match(messages[0].content, /new Telegram conversation/i);
      assert.equal(
        resetSnapshot.active_conversation.messages.some((message: { content?: string }) =>
          message.content?.includes("remember this old Telegram turn"),
        ),
        false,
      );
      assert.equal(
        resetStore.conversations.some((conversation: { conversation_id?: string }) =>
          conversation.conversation_id === previousConversationId,
        ),
        false,
      );
      assert.equal(resetStore.channel_bindings[0].conversation_id, resetSnapshot.active_conversation.conversation_id);
      assert.equal(resetStore.last_run_state.stop_reason, "channel_conversation_reset");
      assert.equal(resetStore.channel_messages.length, 2);
    } finally {
      if (previousKey === undefined) {
        delete process.env.XENODIA_API_KEY;
      } else {
        process.env.XENODIA_API_KEY = previousKey;
      }
    }
  });
});
