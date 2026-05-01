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
- `store/`: persisted runtime state, snapshot projection, reducers, and small
  file adapters.

Migration rule: keep command families here, prove parity with tests, and keep
Swift pointed at the bundled `dist/native-runtime/index.mjs` entry.

## Codex Plugin Development Install

Build the runtime before generating the local plugin package:

```bash
cd /path/to/geeagent/apps/agent-runtime
npm run build
node dist/native-runtime/index.mjs codex-export-generate-plugin '{
  "output_dir": "/path/to/plugins/geeagent-codex",
  "runtime_command": "node",
  "runtime_args": [
    "/path/to/geeagent/apps/agent-runtime/dist/native-runtime/index.mjs",
    "codex-mcp"
  ],
  "marketplace_path": "/path/to/plugin-marketplace/marketplace.json",
  "marketplace_name": "geeagent-local",
  "marketplace_display_name": "GeeAgent Local",
  "marketplace_plugin_path": "./plugins/geeagent-codex"
}'
```

Codex calls enter the shared runtime store as external invocations. Keep
GeeAgentMac running so it can drain those invocations through GearHost; the MCP
server never runs Gear business logic directly or through fallback scripts.
