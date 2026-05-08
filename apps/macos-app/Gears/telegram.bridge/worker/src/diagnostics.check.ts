import assert from "node:assert/strict";
import { describe, it } from "node:test";

import type { TelegramBridgeConfig } from "./config.js";
import {
  buildTelegramBridgeGatewayHealth,
  type TelegramBridgeGatewayTokenStatus,
} from "./diagnostics.js";

const configuredToken: TelegramBridgeGatewayTokenStatus = {
  configured: true,
  status: "configured",
};

function testConfig(): TelegramBridgeConfig {
  return {
    version: 1,
    accounts: [
      {
        id: "gee_direct_default",
        role: "gee_direct",
        transport: { mode: "polling" },
      },
      {
        id: "codex_remote_default",
        role: "codex_remote",
        transport: { mode: "webhook" },
      },
      {
        id: "news_push",
        role: "push_only",
        transport: { mode: "outbound_only" },
        push: { acceptInbound: false },
      },
    ],
    pushChannels: [
      {
        id: "morning_news",
        accountId: "news_push",
        enabled: true,
        target: { kind: "chat_id", value: "123456" },
      },
      {
        id: "quiet_news",
        accountId: "news_push",
        enabled: false,
        target: { kind: "chat_id", value: "789000" },
      },
    ],
  };
}

describe("Telegram Bridge gateway diagnostics", () => {
  it("reports explicit health issues for missing tokens and webhook-only accounts", async () => {
    const health = await buildTelegramBridgeGatewayHealth(
      testConfig(),
      { offsets: { gee_direct_default: 120 } },
      async (accountId) =>
        accountId === "gee_direct_default"
          ? { configured: false, status: "missing" }
          : configuredToken,
    );

    assert.equal(health.status, "failed");
    assert.equal(health.fallback_attempted, false);
    assert.equal(health.polling_account_count, 1);
    assert.equal(health.webhook_account_count, 1);
    assert.equal(health.push_only_account_count, 1);
    assert.equal(health.enabled_push_channel_count, 1);
    assert.equal(health.disabled_push_channel_count, 1);
    assert.deepEqual(health.missing_token_account_ids, ["gee_direct_default"]);
    assert.deepEqual(health.webhook_account_ids, ["codex_remote_default"]);
    assert.deepEqual(
      health.issues.map((issue) => issue.code),
      ["token_missing", "webhook_transport_not_ready"],
    );
    assert.deepEqual(health.accounts[0], {
      id: "gee_direct_default",
      role: "gee_direct",
      transport: "polling",
      token_configured: false,
      token_status: "missing",
      polling_offset: 120,
    });
  });

  it("reports success when configured accounts have tokens and no unsupported transport is active", async () => {
    const health = await buildTelegramBridgeGatewayHealth(
      {
        version: 1,
        accounts: [
          {
            id: "gee_direct_default",
            role: "gee_direct",
            transport: { mode: "polling" },
          },
        ],
        pushChannels: [],
      },
      { offsets: {} },
      async () => configuredToken,
    );

    assert.equal(health.status, "success");
    assert.deepEqual(health.issues, []);
    assert.deepEqual(health.missing_token_account_ids, []);
    assert.deepEqual(health.webhook_account_ids, []);
  });

  it("reports polling lifecycle readiness without attempting fallback", async () => {
    const health = await buildTelegramBridgeGatewayHealth(
      {
        version: 1,
        accounts: [],
        pushChannels: [],
      },
      { offsets: {} },
      async () => configuredToken,
      {
        mode: "worker_cli",
        pollingLoop: "running",
        pollIntervalMs: 3000,
        startedAt: "2026-05-07T08:00:00.000Z",
      },
    );

    assert.deepEqual(health.lifecycle, {
      mode: "worker_cli",
      polling_loop: "running",
      poll_interval_ms: 3000,
      started_at: "2026-05-07T08:00:00.000Z",
      webhook_ready: false,
      webhook_status: "not_implemented",
      fallback_attempted: false,
    });
  });
});
