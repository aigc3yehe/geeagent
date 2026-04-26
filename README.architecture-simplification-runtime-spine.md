# GeeAgent Architecture Simplification Runtime Spine

## Current Status

GeeAgent's active architecture is now:

- native SwiftUI/AppKit macOS app for all user-facing desktop surfaces;
- TypeScript GeeAgent runtime for routing, persisted state, approvals,
  conversations, tasks, tool execution, and command dispatch;
- Agent SDK session loop inside the TypeScript runtime;
- no Tauri/React product shell path;
- no Rust/Cargo runtime transition layer in the active repository.

The old Rust transition layer was removed after confirmation:

- `Cargo.toml`
- `Cargo.lock`
- `apps/runtime-bridge/`
- `apps/runtime-core/`
- `crates/`
- root `target/`
- stale SwiftPM `.build` artifacts that still pointed at the old folder names

Documentation is retained, but active build, test, launch, and development paths
must use the Swift app plus TypeScript runtime shape described here.

## Governance

Runtime work follows the phase-2 council:

- Turing owns phase scope and exit criteria.
- Locke owns SDK runtime architecture.
- Anscombe owns provider and Xenodia compatibility.
- Noether owns product and engineering reality.
- Rawls owns SDK documentation discipline.

Main app UI work must preserve Sagan's native workbench contract: one main
workspace, one persistent agent rail, shallow navigation, no duplicate chat
surfaces, and no visible architecture churn in product UI.

Gear work is out of scope for this cleanup except preserving current gear
visibility, packaged gear discovery, and native window launch behavior.

## Active Boundaries

Active source roots:

- `apps/macos-app`: native macOS app, SwiftUI/AppKit views, stores, runtime
  process client, Live2D host, packaged gears, and app launch script.
- `apps/agent-runtime`: TypeScript runtime, Agent SDK integration,
  native runtime server, persisted store reducers, tools, approvals, and tests.
- `config/*`: routing and module configuration.
- `examples/agent-packs/*`: example agent-pack layouts.

Protected product behavior:

- user-facing app layout and navigation;
- conversations, tasks, approvals, tool timeline, and settings behavior;
- provider routing and Xenodia-compatible gateway configuration;
- Live2D first-party Gee appearance and local persona asset loading;
- gear discovery and native gear window behavior;
- startup behavior from `apps/macos-app/script/build_and_run.sh`.

Protected runtime contracts:

- TypeScript runtime process protocol in `apps/agent-runtime/src/protocol.ts`;
- Swift runtime client mapping in `apps/macos-app/Sources/GeeAgentMac/Runtime`;
- persisted task, approval, conversation, settings, and profile data shape;
- same-run SDK tool continuation and same-run approval pause/resume semantics;
- no chat-only fake completion path.

Some persisted data identifiers may still contain historical words such as
`bridge` for compatibility with existing user state. Those names are data
schema compatibility details, not active Rust or old-shell runtime paths. Rename
them only with an explicit migration.

## Current Verification

Use these commands for the current architecture:

```bash
npm run typecheck --prefix apps/agent-runtime
npm run test --prefix apps/agent-runtime
npm run build --prefix apps/agent-runtime
swift test --package-path apps/macos-app --scratch-path apps/macos-app/.swift-build
bash apps/macos-app/script/build_and_run.sh --verify
```

The native app launch script builds the TypeScript runtime, builds the Swift app,
stages `GeeAgentMac.app` under `apps/macos-app/dist`, launches it as a macOS app
bundle, and auto-allows the removable-volume prompt when macOS shows it.

## Cleanup Guardrails

Do not reintroduce:

- Tauri or React as a product shell;
- Cargo workspace or Rust runtime packages;
- self-built agent loop execution as a runtime path;
- fallback execution paths that hide an incomplete migration;
- new scenario-specific pseudo-tools for generic local work.

Runtime work should keep moving toward one run, one session lineage, one event
truth, same-run tool continuation, same-run approval pause/resume, and no fake
completion. If a cleanup removes a compatibility layer, add or confirm tests for
the behavior it used to cover before deleting it.

## Completed Migration Record

Completed during the simplification branch:

- moved the app shell from `apps/macos-bridge` to `apps/macos-app`;
- moved the TypeScript runtime from `apps/agent-runtime-bridge` to
  `apps/agent-runtime`;
- renamed process protocol events from `bridge.*` to `runtime.*`;
- renamed Swift runtime process errors and helper types away from bridge
  terminology where they were active implementation names;
- deleted the old `GeeAgent.app` installation after confirming it was the stale
  app shell;
- removed old Tauri/React app shell source;
- removed Rust/Cargo transition source and build artifacts after the TypeScript
  runtime owned the active command surface;
- kept Live2D persona loading intact by resolving first-party Gee assets from
  the local persona asset roots.
