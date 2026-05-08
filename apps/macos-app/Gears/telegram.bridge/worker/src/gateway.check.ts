import assert from "node:assert/strict";
import { describe, it } from "node:test";

import type { TelegramBridgeAccount } from "./config.js";
import {
  authorizeTelegramGatewayEnvelope,
  buildGeeDirectRuntimeInput,
  normalizeTelegramGatewayUpdate,
} from "./gateway.js";

function geeDirectAccount(overrides: Partial<TelegramBridgeAccount> = {}): TelegramBridgeAccount {
  return {
    id: "gee_direct_default",
    role: "gee_direct",
    botUsername: "gee_direct_bot",
    transport: { mode: "polling" },
    security: {
      allowUserIds: ["1234"],
      allowChatIds: ["777"],
      requirePairing: false,
      groupPolicy: "deny",
    },
    ...overrides,
  };
}

describe("Telegram Gateway envelope", () => {
  it("normalizes private text updates into stable Gee Direct runtime input", () => {
    const normalized = normalizeTelegramGatewayUpdate(geeDirectAccount(), {
      update_id: 9001,
      message: {
        message_id: 12,
        chat: { id: 777, type: "private" },
        from: { id: 1234 },
        text: "hello gee",
      },
    });

    assert.equal(normalized.status, "success");
    const envelope = normalized.envelope!;
    assert.equal(envelope.idempotencyKey, "telegram:update:9001");
    assert.equal(envelope.routing.channelIdentity, "telegram:gee_direct_default:bot:unknown:dm:777");

    const security = authorizeTelegramGatewayEnvelope(geeDirectAccount(), envelope);
    assert.equal(security.status, "allowed");
    assert.deepEqual(buildGeeDirectRuntimeInput(envelope, security), {
      source: "telegram.bridge",
      role: "gee_direct",
      channelIdentity: "telegram:gee_direct_default:bot:unknown:dm:777",
      message: {
        idempotencyKey: "telegram:update:9001",
        telegramUpdateId: 9001,
        chatId: "777",
        messageId: "12",
        fromUserId: "1234",
        text: "hello gee",
        attachments: [],
      },
      security: {
        decision: "allowed",
        policyId: "allowlist",
      },
      projection: {
        surface: "telegram",
        replyTarget: {
          chatId: "777",
          messageId: "12",
        },
      },
    });
  });

  it("rejects text updates with missing stable identity fields", () => {
    const normalized = normalizeTelegramGatewayUpdate(geeDirectAccount(), {
      update_id: 9001,
      message: {
        message_id: 12,
        chat: { id: 777, type: "private" },
        text: "hello gee",
      },
    });

    assert.equal(normalized.status, "failed");
    assert.equal(normalized.error.code, "message_identity_missing");
  });

  it("normalizes captioned media updates into Telegram artifact references", () => {
    const normalized = normalizeTelegramGatewayUpdate(geeDirectAccount(), {
      update_id: 9004,
      message: {
        message_id: 15,
        chat: { id: 777, type: "private" },
        from: { id: 1234 },
        caption: "photo caption",
        photo: [{ file_id: "photo_file_id", file_unique_id: "photo_unique_id", width: 800, height: 600 }],
      },
    });

    assert.equal(normalized.status, "success");
    const envelope = normalized.envelope!;
    assert.equal(envelope.message.text, "photo caption");
    assert.deepEqual(buildGeeDirectRuntimeInput(envelope, { status: "allowed", policyId: "allowlist" }).message.attachments, [
      {
        artifact_id: "telegram:gee_direct_default:9004:photo:photo_unique_id",
        kind: "telegram_file",
        type: "image",
        title: "Telegram photo",
        uri: "telegram://file/photo_file_id",
        summary: "Telegram photo attachment from chat 777 message 15.",
        mime_type: "image/*",
        telegram_file_id: "photo_file_id",
        telegram_file_unique_id: "photo_unique_id",
        telegram_media_kind: "photo",
        width: 800,
        height: 600,
      },
    ]);
  });

  it("rejects unsupported attachment-bearing updates instead of forwarding caption-only text", () => {
    const normalized = normalizeTelegramGatewayUpdate(geeDirectAccount(), {
      update_id: 9005,
      message: {
        message_id: 16,
        chat: { id: 777, type: "private" },
        from: { id: 1234 },
        caption: "paid media caption",
        paid_media: {},
      },
    });

    assert.equal(normalized.status, "failed");
    assert.equal(normalized.error.code, "message_attachment_unsupported");
  });

  it("keeps group topic identity stable when mention-required policy allows the message", () => {
    const account = geeDirectAccount({
      botUsername: "@gee_direct_bot",
      security: {
        allowUserIds: ["1234"],
        allowChatIds: ["777"],
        requirePairing: false,
        groupPolicy: "mention_required",
      },
    });
    const normalized = normalizeTelegramGatewayUpdate(account, {
      update_id: 9002,
      message: {
        message_id: 13,
        message_thread_id: 55,
        chat: { id: 777, type: "supergroup" },
        from: { id: 1234 },
        text: "@gee_direct_bot continue",
      },
    });

    assert.equal(normalized.status, "success");
    const envelope = normalized.envelope!;
    assert.equal(envelope.routing.channelIdentity, "telegram:gee_direct_default:bot:unknown:chat:777:topic:55");
    assert.equal(authorizeTelegramGatewayEnvelope(account, envelope).status, "allowed");
  });

  it("denies mention-required group messages before runtime input is built", () => {
    const account = geeDirectAccount({
      security: {
        allowUserIds: ["1234"],
        allowChatIds: ["777"],
        requirePairing: false,
        groupPolicy: "mention_required",
      },
    });
    const normalized = normalizeTelegramGatewayUpdate(account, {
      update_id: 9003,
      message: {
        message_id: 14,
        chat: { id: 777, type: "group" },
        from: { id: 1234 },
        text: "continue",
      },
    });

    assert.equal(normalized.status, "success");
    assert.deepEqual(authorizeTelegramGatewayEnvelope(account, normalized.envelope!), {
      status: "denied",
      code: "group_policy_mention_required",
      message: "Telegram group messages must mention this bot before GeeAgent accepts them.",
    });
  });
});
