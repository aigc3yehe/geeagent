# Native Runtime Server

This folder is the TypeScript native runtime spine used by the macOS app.

Keep files small and role-specific:

- `protocol.ts`: JSON-lines request/response envelope shared with Swift.
- `paths.ts`: GeeAgent config file locations.
- `commands.ts`: command routing only.
- `server.ts`: stdin/stdout JSON-lines loop only.
- `index.ts`: CLI argument parsing only.
- `store/`: persisted runtime state, snapshot projection, reducers, and small
  file adapters.

Migration rule: keep command families here, prove parity with tests, and keep
Swift pointed at the bundled `dist/native-runtime/index.mjs` entry.
