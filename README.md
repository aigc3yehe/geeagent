# GeeAgent

![GeeAgent banner](apps/macos-app/Resources/bg.png)

[中文](README.zh-CN.md) | [日本語](README.ja.md)

[Public Docs](https://aigc3yehe.github.io/geeagent/)

![macOS](https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6.1-FA7343?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-Native_UI-0A84FF?logo=swift&logoColor=white)
![AppKit](https://img.shields.io/badge/AppKit-macOS_Framework-1F6FEB)
![TypeScript](https://img.shields.io/badge/TypeScript-Agent_Runtime-3178C6?logo=typescript&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-SDK_Sidecar-339933?logo=node.js&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green.svg)

GeeAgent is a macOS-first AI workbench built around companion-style interaction, visible task execution, and modular runtime orchestration.

The project combines a native macOS app with a TypeScript agent runtime so that interaction, routing, approvals, task state, and module execution can remain inspectable as the system grows.

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
- `TypeScript` and `Node.js` for the GeeAgent runtime and Agent SDK session loop
- `TOML` configuration for routing and module definitions

## Architecture

At a high level, GeeAgent is organized as:

1. A native macOS shell for the companion, workbench, menu-bar flows, and operator-facing UI.
2. A TypeScript runtime that owns routing, execution contracts, workspace state, approvals, conversations, and task progression.
3. A Agent SDK session layer inside the TypeScript runtime for the live agent loop.
4. A modular integration boundary for first-party actions and external services.

Representative runtime modules:

- `apps/agent-runtime/src/native-runtime`: persisted runtime state, snapshots, tools, turns, approvals, and command dispatch
- `apps/agent-runtime/src/session.ts`: Agent SDK session wrapper and permission callback handling
- `apps/agent-runtime/src/gateway.ts`: Anthropic-compatible gateway for the configured model route
- `apps/agent-runtime/src/chat-runtime.ts`: chat routing settings and provider readiness

Important active paths:

- `apps/macos-app`: native macOS app
- `apps/agent-runtime`: TypeScript GeeAgent runtime and Agent SDK integration
- `config/*`: routing and module configuration
- `examples/agent-packs/*`: example agent-pack layouts

## Getting Started

### Prerequisites

- macOS 15+
- Xcode with Swift 6.1 support
- Node.js and npm

### Build the Native App

```bash
swift build --package-path apps/macos-app --scratch-path apps/macos-app/.swift-build
```

### Build and Launch the Native Workbench App

```bash
bash apps/macos-app/script/build_and_run.sh
```

This command builds the TypeScript runtime and launches the native macOS app.

### Run the Runtime Tests

```bash
npm run test --prefix apps/agent-runtime
swift test --package-path apps/macos-app --scratch-path apps/macos-app/.swift-build
```

## Contributing

Contributions are welcome. A few repository expectations help keep the project clean and reviewable:

- prefer focused PRs with a clear runtime, UI, or architecture objective
- keep machine-specific files, secrets, caches, and local planning materials out of version control
- document contract changes when they affect routing, task lifecycle, workspace snapshots, or module boundaries
- include tests when changing runtime behavior

If you extend the runtime surface, it is especially helpful to note which TypeScript module owns the contract and which UI surface consumes it.

## License

MIT
