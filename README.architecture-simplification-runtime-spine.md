# GeeAgent Architecture Simplification Runtime Spine Plan

## Goal

Simplify GeeAgent without changing the product experience. The target shape is:

- native SwiftUI/AppKit app shell for all user-facing desktop surfaces;
- Rust runtime host for persisted state, projections, approvals, transcripts, tasks, modules, settings, and bridge contracts;
- TypeScript Claude Agent SDK sidecar as the only live agent loop;
- no Tauri/React product shell path in the final architecture;
- no legacy self-built agent loop as a runtime path.

## Governance

Runtime work follows the phase-2 council:

- Turing owns phase scope and exit criteria.
- Locke owns Claude SDK runtime architecture.
- Anscombe owns provider and Xenodia compatibility.
- Noether owns product and engineering reality.
- Rawls owns SDK documentation discipline.

Main app UI work must preserve Sagan's native workbench contract: one main workspace, one persistent agent rail, shallow navigation, no duplicate chat surfaces, and no visible architecture churn in product UI.

Gear work is out of scope for this slice except preserving current gear
visibility, packaged gear discovery, and native window launch behavior.

## Phase And Exit Criteria

Current phase: runtime spine completion plus shell retirement preparation.

Exit criteria:

- one run, one session lineage, one event truth;
- same-run tool continuation;
- same-run approval pause and resume;
- no chat-only fake completion;
- product-side behavior unchanged;
- Swift app uses the native runtime bridge binary and does not fall back to the old Tauri target.

Out of scope:

- new gear features;
- browser automation and computer-use work;
- app or persona market expansion;
- large UI redesign;
- deleting old runtime code before SDK-backed behavior has equivalent tests.

## Workstreams

1. Shell conversion and removal

   Introduce `apps/runtime-bridge` as the native Rust bridge package. The Swift
   app must fail loudly if this bridge cannot build; it must not silently fall
   back to the old Tauri bridge.

2. Agent loop handoff and removal

   Keep Claude SDK sidecar as the live loop. Legacy local planners, pseudo-tools, controlled-terminal lanes, and `invoke-tool` compatibility are deletion candidates only after SDK bridge tests prove equivalent behavior.

3. Product invariance and UX quality

   Lock Swift DTO fields, task and approval projections, quick input, settings, Apps/Gears visibility, dedicated native gear windows, and unavailable-runtime degradation behavior.

4. Provider compatibility

   Preserve Xenodia and Anthropic-compatible routing, saved chat runtime settings, and SDK bridge environment mapping.

5. Verification

   Every slice must pass Rust, Swift, TypeScript, bridge protocol, snapshot, packaging, and targeted SDK approval/resume checks before proceeding.

## Stable Boundaries

Still protected while removing old shell paths:

- `shell_runtime_bridge` command names and argument contract;
- `serve` JSON-lines protocol: `{ id, command, args }` in, `{ id, ok, output, error }` out;
- `GEEAGENT_NATIVE_BRIDGE_BIN` override;
- bundled `shell_runtime_bridge` resource lookup;
- SDK bridge session, approval, provider, and transcript behavior.

Allowed first-slice changes:

- add `apps/runtime-bridge`;
- copy `shell_runtime_bridge.rs` and `geeagent_cli.rs`;
- build the new package for macOS packaging;
- make Swift bridge lookup use `apps/runtime-bridge/target/...`;
- remove old Tauri target fallback from the product runtime path.

## First Slice Completed

Implemented on branch `codex/architecture-simplification-runtime-spine`:

- added standalone Cargo package `apps/runtime-bridge`;
- seeded `shell_runtime_bridge.rs` and `geeagent_cli.rs` from the old Tauri package;
- updated macOS packaging to build and bundle the new bridge binary;
- updated Swift runtime client to use the new bridge binary and build manifest, without old Tauri fallback;
- removed the new runtime bridge package's direct dependency on Tauri async runtime;
- removed the duplicate old bridge binaries from `apps/desktop-shell/src-tauri/src/bin`;
- removed the stale `clap` CLI dependency from the old Tauri crate after moving
  CLI binaries into `apps/runtime-bridge`;
- changed native bridge submit APIs to synchronous Rust functions and removed
  `apps/runtime-bridge`'s direct `tokio` executor dependency;
- removed Tauri command handlers, tray/window/global-shortcut setup, React-shell
  route hints, module refresh polling, old setup-key writers, and other unused
  shell-only helpers from the Rust runtime library;
- removed direct Tauri, Tauri plugin, and Tauri build dependencies from
  `apps/desktop-shell/src-tauri/Cargo.toml`; the crate now builds as an `rlib`
  consumed by `apps/runtime-bridge`;
- removed old shell navigation, tray, module refresh, and chat setup writer
  tests after deleting those code paths;
- removed the legacy self-built planner and direct chat-completions branch from
  `chat_runtime.rs`, leaving provider routing, readiness, saved settings, and
  Xenodia gateway compatibility;
- removed the old repo-config runtime fallback from `chat_runtime.rs`; native
  bridge startup now reads explicit user config overrides or the compiled-in
  default config, avoiding old shell-era paths during packaged app launch;
- removed production `prepare_turn_context` pre-routing through the old
  first-party/local execution detector, status-follow-up detector, and
  runtime-fact direct-reply detector; those units are now test-only helpers and
  no longer form a runtime fallback before the SDK loop;
- deleted the unused controlled-terminal self-planner and stale kernel lineage
  recorder functions from the old Rust host path;
- removed the stale SDK approval replay fallback: if a paused SDK approval
  session is lost, GeeAgent now records a degraded failed state instead of
  re-running the request through a fresh path;
- kept product UI, DTOs, runtime semantics, approval semantics, and provider routing unchanged;
- updated stale tests to match the current tool catalog and native gear window behavior.
- copied native gear manifests into the packaged `.app` resources and made
  `GearRegistry` prefer `Contents/Resources/gears`, with the SwiftPM resource
  bundle limited to non-`.app` development/test runs.

## Verification Performed

- `cargo test`
- `swift test --package-path apps/macos-bridge`
- `npm run build --prefix apps/agent-runtime-bridge`
- `cargo build --manifest-path apps/runtime-bridge/Cargo.toml --bin shell_runtime_bridge`
- `cargo build --manifest-path apps/runtime-bridge/Cargo.toml --bin geeagent_cli`
- `cargo build --manifest-path apps/runtime-bridge/Cargo.toml --bins`
- `cargo test --manifest-path apps/desktop-shell/src-tauri/Cargo.toml --lib`
- `cargo test --manifest-path apps/desktop-shell/src-tauri/Cargo.toml native_bridge_task_action_ --lib`
- `cargo test --manifest-path apps/desktop-shell/src-tauri/Cargo.toml sdk_bridge_ --lib`
- `cargo tree --manifest-path apps/desktop-shell/src-tauri/Cargo.toml -p geeagent_desktop_shell --depth 1`
- old/new bridge snapshot comparison with timestamps normalized
- new bridge `serve` JSON-lines smoke test
- `bash apps/macos-bridge/script/build_and_run.sh --verify`
- front-end smoke check in the launched native app: Home `LIVE`, Gears
  atmosphere/widget lists, Workbench chat, Settings, Live2D host, widgets,
  active queue, and bridge snapshot status `live`.

## Remaining Deletion Queue

These files are no longer part of the active product/runtime path and should be
moved to the macOS Trash once deletion is confirmed:

- `apps/desktop-shell/src-tauri/build.rs`
- `apps/desktop-shell/src-tauri/src/main.rs`
- `apps/desktop-shell/src-tauri/tauri.conf.json`
- `apps/desktop-shell/src-tauri/capabilities/`
- `apps/desktop-shell/src-tauri/gen/`
- `apps/desktop-shell/src-tauri/icons/`
- `apps/desktop-shell/src-tauri/src/module_runtime.rs`

## Next Slice Gate

Before deleting more runtime behavior, add or confirm tests for:

- SDK workspace and quick prompt paths never using old local execution;
- Bash approval pause and same-run resume using the same bridge session and request ID;
- chained SDK approvals;
- denial behavior without command execution;
- persisted terminal permission rules;
- WebSearch/WebFetch auto-approval;
- unknown non-Bash denial.
