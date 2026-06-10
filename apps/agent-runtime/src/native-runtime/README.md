# Native Runtime Server

This folder is the TypeScript native runtime spine used by the macOS app.

Keep files small and role-specific:

- `protocol.ts`: JSON-lines request/response envelope shared with Swift.
- `paths.ts`: GeeAgent config file locations.
- `commands.ts`: command routing only.
- `server.ts`: stdin/stdout JSON-lines loop only.
- `index.ts`: CLI argument parsing only.
- `codex-export.ts`: manifest-backed Codex capability export projection.
- `codex-external-invocations.ts`: shared-store queue for Codex-originated
  calls that GeeAgentMac drains through GearHost.
- `codex-mcp-server.ts`: Codex-facing MCP stdio surface for the export projection.
- `codex-plugin.ts`: local `geeagent-codex` plugin package generator.
- `agent-gateway.ts`: neutral manifest-backed capability projection for personal
  local agents.
- `agent-gateway-clients.ts`: read-only MCP configuration/status material for
  Codex, Claude Code, and WorkBuddy/OpenClaw.
- `agent-gateway-mcp-server.ts`: shared stdio MCP surface for personal local
  agents.
- `store/`: persisted runtime state, snapshot projection, reducers, and small
  file adapters.
- `store/run-replay.ts`: read-only run replay export, replay projection,
  artifact membership, and wait classification by `run_id`; do not feed replay
  bundles into normal model prompts.

Migration rule: keep command families here, prove parity with tests, and keep
Swift pointed at the bundled `dist/native-runtime/index.mjs` entry.

## Codex Plugin Development Install

Build the runtime before generating the local plugin package:

```bash
cd /path/to/geeagent/apps/agent-runtime
npm run build
node dist/native-runtime/index.mjs codex-export-install-plugin '{}'
```

By default this writes a home-local plugin to `~/plugins/geeagent-codex`,
refreshes `~/.agents/plugins/marketplace.json`, and refreshes the Codex-loaded
cache package at
`~/.codex/plugins/cache/geeagent-local/geeagent-codex/<plugin-version>`.
The cache package is derived from the home-local plugin package, not from the
development checkout. The plugin package includes a
versioned copy of the built native runtime at
`runtime/native-runtime/<plugin-version>/index.mjs`; the generated `.mcp.json`
points Codex at that plugin-local bundle instead of the development checkout.
It also includes `gears/<gear-id>/gear.json` manifest projections for exported
capabilities so discovery works from any project cwd without scanning the
development tree.

Codex calls enter the shared runtime store as external invocations. Keep
GeeAgentMac running so it can drain those invocations through GearHost; the MCP
server never runs Gear business logic directly or through fallback scripts.
`gee_get_invocation` reads the recorded store result directly and accepts an
optional `wait_ms` for a short terminal-state wait. GeeAgentMac prioritizes
read-only Media Generator model/task queries while still returning those results
through the same external invocation completion record. Stale `running`
invocations degrade with manual-retry recovery guidance instead of being retried
automatically.

Media Generator image and video creation is exported as
`media.generator/media_generator.create_task`. Codex should call
`gee_describe_capability` for the schema, pass explicit user prompts through the
Gear bridge, normalize the user-facing `image-2` model name to `gpt-image-2`,
use `batch_count` 1-4 for multi-result image or video requests while keeping
image provider `n` at 1, and report the returned task or batch id/status/artifact
references instead of claiming a provider result before Gee returns it.

Media Library local file import is exported as
`media.library/media.import_files`. Codex should call
`gee_describe_capability`, pass only explicit local `paths` from the user or
prior Gee results, and report `imported_items`, `existing_items`,
`pending_paths`, `missing_paths`, and authorization failures from Gee instead of
reading or copying files through Codex-side shell shortcuts.

WeSpy Reader explicit URL capture is exported as
`wespy.reader/wespy.fetch_article`, `wespy.reader/wespy.list_album`, and
`wespy.reader/wespy.fetch_album`. Codex should pass only explicit article or
album URLs from the user or prior Gee results, preserve returned task paths,
article metadata, generated files, and structured failures, and never run the
package-local WeSpy sidecar or scraper substitutes from the Codex side.

SmartYT media acquisition is exported as `smartyt.media/smartyt.search_candidates`,
`smartyt.media/smartyt.sniff`, `smartyt.media/smartyt.download`,
`smartyt.media/smartyt.download_now`, and task inspection capabilities. Codex
should use `smartyt.search_candidates` for explicit media search queries,
including `platforms: ["douyin"]` or `["xiaohongshu"]` when the user asks for
Douyin or Xiaohongshu/RED clips. YouTube search uses yt-dlp, Xiaohongshu search
uses `xiaohongshu-cli` with browser cookies, and Douyin search uses `dy-cli`
when a Douyin account and required proxy/network route are configured. Selected
candidates or explicit Douyin/Xiaohongshu short-video URLs should then be
downloaded with `smartyt.download_now`; Douyin video downloads use the same
Gear-declared `dy-cli` route, while Xiaohongshu explicit URLs continue through
the URL download provider. Generated files remain in SmartYT output directories
unless another Gear import is explicitly requested. Missing CLI dependencies,
missing Douyin login state, or missing Douyin proxy/network readiness are
returned as structured Gear failures, not Codex-side fallback work.

WeChat Watcher account-name discovery is exported as
`wechat.watcher/wechat.latest_articles`, with supporting auth status, search,
watchlist, and update-check capabilities. Codex should call the Gee MCP bridge
when the user gives a WeChat public-account name and asks for latest articles:
the live Gear searches the authenticated WeChat Official Account backend, uses
the returned `fakeid`, optionally records the watchlist entry, and returns
explicit article URLs. Codex must not substitute official websites, search
engines, profile-page scraping, or package-local scripts for this path.

WeChat Channels explicit URL resolution and download is exported as
`wechat.channels/wechat_channels.metadata` and
`wechat.channels/wechat_channels.download`, with supporting auth-status and task
inspection capabilities. Codex should pass only explicit `weixin.qq.com/sph/...`
or `channels.weixin.qq.com/finder-preview/...` URLs. Short share links first use
Tencent's official `shortUri` feed route for metadata; the live Gear reads the
configured Yuanbao web session from Keychain only when a downloadable feed URL
needs recovery. It returns structured profile/task evidence and downloads only
Tencent-returned video URLs. Codex must surface `auth_missing`, Tencent
rejection, or `no_video_url` as structured failed or degraded results and must
not use third-party parser sites, browser scraping, SmartYT, or local scripts as
a fallback.
