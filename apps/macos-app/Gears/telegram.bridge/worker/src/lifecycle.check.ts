import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { buildPollLoopLifecycleEvent } from "./cli.js";

describe("Telegram Bridge poll-loop lifecycle events", () => {
  it("builds start and stop envelopes without fallback semantics", () => {
    const context = {
      pollIntervalMs: 3000,
      configPath: "/tmp/telegram/config.json",
      statePath: "/tmp/telegram/polling-state.json",
      occurredAt: "2026-05-07T09:00:00.000Z",
    };

    assert.deepEqual(buildPollLoopLifecycleEvent({ ...context, event: "poll_loop_started" }), {
      event: "poll_loop_started",
      status: "running",
      fallback_attempted: false,
      mode: "worker_cli",
      polling_loop: "running",
      poll_interval_ms: 3000,
      config_path: "/tmp/telegram/config.json",
      state_path: "/tmp/telegram/polling-state.json",
      occurred_at: "2026-05-07T09:00:00.000Z",
    });
    assert.deepEqual(buildPollLoopLifecycleEvent({ ...context, event: "poll_loop_stopped" }), {
      event: "poll_loop_stopped",
      status: "stopped",
      fallback_attempted: false,
      mode: "worker_cli",
      polling_loop: "stopped",
      poll_interval_ms: 3000,
      config_path: "/tmp/telegram/config.json",
      state_path: "/tmp/telegram/polling-state.json",
      occurred_at: "2026-05-07T09:00:00.000Z",
    });
  });

  it("builds structured iteration failure envelopes while keeping the loop running", () => {
    const event = buildPollLoopLifecycleEvent({
      event: "poll_loop_iteration_failed",
      pollIntervalMs: 3000,
      configPath: "/tmp/telegram/config.json",
      statePath: "/tmp/telegram/polling-state.json",
      occurredAt: "2026-05-07T09:00:01.000Z",
      error: {
        code: "poll_loop_failed",
        message: "token missing",
      },
    });

    assert.deepEqual(event, {
      event: "poll_loop_iteration_failed",
      status: "failed",
      fallback_attempted: false,
      mode: "worker_cli",
      polling_loop: "running",
      poll_interval_ms: 3000,
      config_path: "/tmp/telegram/config.json",
      state_path: "/tmp/telegram/polling-state.json",
      occurred_at: "2026-05-07T09:00:01.000Z",
      error: {
        code: "poll_loop_failed",
        message: "token missing",
      },
    });
  });
});
