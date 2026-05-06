# Telegram Bridge

Telegram Bridge is an optional GeeAgent Gear for Telegram-connected workflows.

The current implementation includes the Gear package, native shell,
GearHost-backed push delivery, native app-started polling, Codex remote
control, and GeeAgent Phase 3 channel ingress. Push delivery and the native
polling service read bot tokens from GeeAgent's local app data store in the
native app, while the standalone worker service reads tokens from environment
variables.

## Account Roles

- `codex_remote`: remote control for Codex desktop sessions with
  `/start`/`/help`, `/list`/`/recent`, `/open <session_id>`,
  `/latest [session_id]`, `/desktop [session_id]`, `/tracked`, `/cancel`,
  `/send <text>`, and `/send <session_id> <prompt>`. The native bridge keeps
  the Telegram bot command menu registered, sends inline keyboard buttons for
  project selection, paginated project/thread browsing, Track/Untrack, and
  thread actions, and lists sessions by project. Selecting a thread and sending
  plain text stages the prompt first; Codex receives it only after Confirm, so
  accidental Telegram messages do not immediately resume a Codex thread. The
  file-scan path only lists Codex Desktop-originated, non-subagent sessions so
  Telegram does not show internal conversations that are invisible in the Codex
  app. It scans Codex JSONL session summaries incrementally so very large
  session files do not block the Telegram reply path. Long Telegram replies are
  split into multiple messages instead of being truncated.
- `gee_direct`: bidirectional Telegram channel for GeeAgent Phase 3 runs.
  Send `/new` to start a fresh GeeAgent conversation for the same Telegram
  chat and clear the previous runtime history. When a Gee Direct run needs to
  return a local file, it can use `telegram_direct.send_file`; the native
  Gear validates the local path and sends it to the active Telegram chat. If
  the Phase 3 runtime fails before producing a reply projection, the native
  bridge sends that failure back to the same Telegram chat and records it as
  `runtime_failed`.
- `push_only`: one-way Telegram delivery channel for scheduled reports and
  notifications. It can send text through `telegram_push.send_message` and
  readable local files through `telegram_push.send_file`.

Push-only accounts do not poll Telegram, do not accept webhooks, do not parse
commands, do not require inbound user allowlists, and do not create GeeAgent
conversation sessions. They send only to explicit configured outbound targets.
After a push channel is saved, the native Gear UI exposes a Test action on the
saved channel row. The Test action sends a short message through
`telegram_push.send_message`, so it verifies the stored account token, channel
binding, Telegram target, and delivery path used by Codex/Gee pushes. Long
plain-text push messages are split into multiple Telegram messages; long
messages that request a Telegram parse mode remain blocked so formatting tags
are not split into invalid chunks. Push file delivery validates the local path,
uses Telegram photo/video/animation endpoints for common image, video, and GIF
files, and sends other readable files as documents.

Inbound accounts enforce configured Telegram user and chat allowlists. Group
messages default to `deny`; `mention_required` accepts only messages that
mention the configured `botUsername`. `requirePairing: true` currently returns
a structured `pairing_required_unavailable` result until pairing is implemented.
The native setup UI can fill allowlist user IDs from already-consumed local
Telegram conversation history and runtime channel ingress history before it
queries Telegram Bot API updates, so background polling does not empty the
source used by the configuration helper.

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
- `telegram_push.send_file`
- `telegram_direct.send_file` (native GearHost bridge only)

The native GearHost bridge exposes `telegram_bridge.status`,
`telegram_push.list_channels`, `telegram_push.upsert_channel`, and
`telegram_push.send_message`, and `telegram_push.send_file`, plus contextual
`telegram_direct.send_file` for Gee Direct conversations, to GeeAgent. Codex
export is enabled for status, list, push text send, and push file send.
`upsert_channel` stays Gee-native only because target confirmation and bot
token binding are local setup steps. Direct file send is not exported to
detached Codex pushes because it depends on the active Gee Direct Telegram
chat.

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

Send a local file to a push-only channel:

```bash
TELEGRAM_BRIDGE_TOKENS_JSON='{"news_push":"<bot-token>"}' \
npm run cli -- send-push-file \
  --config ~/Library/Application\ Support/GeeAgent/gear-data/telegram.bridge/config.json \
  --channel morning_news \
  --file /tmp/report.pdf \
  --caption "Daily report" \
  --idempotency-key report-2026-05-06
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
