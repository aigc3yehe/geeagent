# Telegram Bridge

Telegram Bridge is an optional GeeAgent Gear for Telegram-connected workflows.

The current implementation includes the Gear package, native shell,
GearHost-backed push delivery, worker-side polling, Codex remote control, and
GeeAgent Phase 3 channel ingress. Push delivery reads bot tokens from the
macOS Keychain in the native app, while the standalone worker service reads
tokens from environment variables.

## Account Roles

- `codex_remote`: remote control for Codex desktop sessions.
- `gee_direct`: bidirectional Telegram channel for GeeAgent Phase 3 runs.
- `push_only`: one-way Telegram delivery channel for scheduled reports and
  notifications.

Push-only accounts do not poll Telegram, do not accept webhooks, do not parse
commands, do not require inbound user allowlists, and do not create GeeAgent
conversation sessions. They send only to explicit configured outbound targets.

Inbound accounts enforce configured Telegram user and chat allowlists. Group
messages default to `deny`; `mention_required` accepts only messages that
mention the configured `botUsername`. `requirePairing: true` currently returns
a structured `pairing_required_unavailable` result until pairing is implemented.

## Worker Checks

From the repository root:

```bash
cd apps/agent-runtime
node --test --import tsx ../macos-app/Gears/telegram.bridge/worker/src/*.test.ts
```

The worker currently validates configuration shape, push-only account rules,
push channel account binding, redacted Telegram targets, push message delivery
contracts, Telegram Bot API response mapping, polling state, Codex remote
commands, native runtime channel submission, and structured command dispatch
for:

- `telegram_push.list_channels`
- `telegram_push.upsert_channel`
- `telegram_push.send_message`

The native GearHost bridge exposes `telegram_bridge.status`,
`telegram_push.list_channels`, `telegram_push.upsert_channel`, and
`telegram_push.send_message` to GeeAgent. Codex export is enabled for status,
list, and send. `upsert_channel` stays Gee-native only because target
confirmation and bot token binding are local setup steps.

## Standalone Worker

Create or update a push-only channel:

```bash
cd apps/macos-app/Gears/telegram.bridge/worker
npm run cli -- upsert-push-channel \
  --channel morning_news \
  --account news_push \
  --target-kind chat_id \
  --target-value 777
```

Run one polling pass:

```bash
TELEGRAM_BRIDGE_TOKENS_JSON='{"gee_direct_default":"<bot-token>"}' \
npm run cli -- poll-once \
  --config ~/Library/Application\ Support/GeeAgent/gear-data/telegram.bridge/config.json \
  --state ~/Library/Application\ Support/GeeAgent/gear-data/telegram.bridge/polling-state.json \
  --runtime-entry /path/to/native-runtime/index.mjs \
  --runtime-config-dir ~/Library/Application\ Support/GeeAgent
```

Use `poll-loop` for a long-running local service. The worker never falls back
from app-server Codex mode to CLI resume or from runtime channel ingress to a
chat-only completion; unavailable dependencies produce structured
`failed`/`degraded` results with `fallback_attempted: false`.
