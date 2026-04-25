# GeeAgent

[中文](README.zh-CN.md) | [日本語](README.ja.md)

![macOS](https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6.1-FA7343?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-Native_UI-0A84FF?logo=swift&logoColor=white)
![AppKit](https://img.shields.io/badge/AppKit-macOS_Framework-1F6FEB)
![Rust](https://img.shields.io/badge/Rust-Workspace-000000?logo=rust&logoColor=white)
![Cargo](https://img.shields.io/badge/Cargo-Build_System-8C4A2F?logo=rust&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green.svg)

GeeAgent is a macOS-first AI workbench built around companion-style interaction, visible task execution, and modular runtime orchestration.

The project combines a native macOS shell with a Rust-powered runtime layer so that interaction, routing, approvals, task state, and module execution can remain inspectable as the system grows.

## Why GeeAgent

Most AI products still start from a chat box or a CLI. GeeAgent explores a different interface model:

- a summonable desktop-native assistant instead of a browser tab
- a workbench that makes task state, approvals, and execution progress visible
- modular runtime paths instead of a single opaque agent loop
- local-first configuration for user-specific state and workflows
- an architecture that stays open to extension, debugging, and contributor inspection

## Tech Stack

GeeAgent currently uses the following core components:

- `SwiftUI` and `AppKit` for the native macOS shell and companion-facing UI
- `Swift Package Manager` for the macOS application package
- `Rust` and `Cargo` for runtime logic, execution contracts, routing, and workspace state
- a standalone Rust runtime bridge binary bundled by the native macOS app
- `TOML` configuration for routing and module definitions

## Architecture

At a high level, GeeAgent is organized as:

1. A native macOS shell for the companion, workbench, menu-bar flows, and operator-facing UI.
2. A Rust runtime layer that owns routing, execution contracts, workspace state, module dispatch, and task progression.
3. A modular integration boundary for first-party actions and external services.

Representative runtime crates:

- `agent-kernel`: validates and loads agent-pack content
- `automation-engine`: recurring execution rules and policies
- `execution-runtime`: prompt execution and automation drafts
- `model-router`: provider and route selection
- `module-gateway`: module manifest and module-run contracts
- `runtime-kernel`: first-party tool invocation rules
- `task-engine`: task stages and lifecycle
- `workspace-runtime`: workbench snapshot contracts

Important active paths:

- `apps/macos-bridge`: native macOS shell
- `apps/runtime-bridge`: native Rust bridge binaries used by the macOS shell
- `apps/desktop-shell/src-tauri`: transitional Rust runtime library while code moves out of the old shell path
- `crates/*`: core runtime crates
- `config/*`: routing and module configuration
- `examples/agent-packs/*`: example agent-pack layouts

## Getting Started

### Prerequisites

- macOS 15+
- Xcode with Swift 6.1 support
- Rust toolchain
- Cargo

### Build the Native App

```bash
swift build --package-path apps/macos-bridge
```

### Build and Launch the Native Workbench App

```bash
bash apps/macos-bridge/script/build_and_run.sh
```

This command builds the native macOS app together with the Rust runtime bridge it bundles.

### Run the Rust Workspace Tests

```bash
cargo test
```

## Contributing

Contributions are welcome. A few repository expectations help keep the project clean and reviewable:

- prefer focused PRs with a clear runtime, UI, or architecture objective
- keep machine-specific files, secrets, caches, and local planning materials out of version control
- document contract changes when they affect routing, task lifecycle, workspace snapshots, or module boundaries
- include tests when changing crate-level runtime behavior

If you extend the runtime surface, it is especially helpful to note which crate owns the contract and which UI surface consumes it.

## License

MIT
