<p align="center">
  <img src="gee-nyko.png" alt="GeeAgent icon" width="112" style="border-radius: 24px;" />
</p>

<h1 align="center">GeeAgent</h1>

<p align="center">Make your agent unique</p>

<p align="center">
  <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white" />
  <img alt="Swift 6.1" src="https://img.shields.io/badge/Swift-6.1-FA7343?logo=swift&logoColor=white" />
  <img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-Native_UI-0A84FF?logo=swift&logoColor=white" />
  <img alt="AppKit" src="https://img.shields.io/badge/AppKit-macOS_Framework-1F6FEB" />
  <img alt="TypeScript Agent Runtime" src="https://img.shields.io/badge/TypeScript-Agent_Runtime-3178C6?logo=typescript&logoColor=white" />
  <img alt="MIT License" src="https://img.shields.io/badge/License-MIT-green.svg" />
</p>

<p align="center">
  <a href="README.zh-CN.md">中文</a> | <a href="README.ja.md">日本語</a>
</p>

GeeAgent is a lightweight macOS AI workbench for persona-driven agents, local app assistance, and AI visual production.

It is not trying to become a huge, heavy, all-purpose agent that swallows every workflow. GeeAgent is designed to stay small enough to feel close at hand: a native desktop companion for daily tasks, files, apps, creative planning, image generation, video generation, editing, and publishing.

The hope behind GeeAgent is simple: make agents feel different from one another, with their own presence, memory, taste, and way of helping.

## Why GeeAgent

Most agent tools still begin with a blank chat box. GeeAgent begins with a different question: what if an agent could feel like a durable creative presence, not just a prompt window?

GeeAgent is built around three ideas:

- **Agent Persona**: an agent should have a stable identity, voice, visual presence, boundaries, and tool posture. Persona is not decoration. It is how humans build trust, memory, taste, and collaboration with an AI agent over time.
- **Gear**: useful agent work should not be trapped inside one monolithic app. Gears are optional local apps, widgets, and capability packages that can grow into an open desktop app market.
- **Lightweight Focus**: GeeAgent should be simple, fast, and readable. It helps with everyday local work, but it has a special bias toward AI visual creation: images, videos, clips, publishing flows, and creator operations.

<p align="center">
  <img src="ui.png" alt="GeeAgent UI preview" />
</p>

## Agent Persona

GeeAgent treats persona as a first-class product layer. A persona can define how an agent speaks, what it cares about, how it appears, which skills it prefers, and which tools it is allowed to use.

The long-term direction is to connect persona with an agent actor protocol. In that future, a persona is not just a local skin or prompt file. It can become the human-readable surface of a deeper actor record: identity, capabilities, creative history, licensing rules, attribution, and economic participation. The desktop agent becomes the place where that actor is experienced, directed, trusted, and put to work.

This matters especially for creative AI. If AI characters, performers, assistants, and collaborators are going to appear across stories, videos, tools, and markets, they need more than text prompts. They need continuity.

## Gear: An Open App Market

GeeAgent's Gear system is the path toward an open local app market.

A Gear can be a native app, a Home widget, a local tool surface, or a capability package. Gears are meant to stay optional: a missing, disabled, broken, or uninstalled Gear should not break the main workbench.

The goal is practical and creator-friendly:

- install or copy small local tools without bloating the core app
- keep app-specific logic inside the Gear boundary
- expose only declared capabilities to the agent
- preserve a path for third-party creators to build focused tools around media, automation, publishing, and local workflows

GeeAgent should feel like a small studio bench, not a maze of plugins.

## Built For Visual Creators

GeeAgent is shaped around two strong use cases.

First, it helps with local app assistance: files, commands, task state, approvals, settings, and small pieces of desktop work that are easier when an agent can see the workflow instead of only answering in chat.

Second, it is optimized for AI visual production. The product direction gives extra weight to:

- image generation and prompt iteration
- video generation and shot planning
- clip selection, editing, and packaging
- publishing workflows for short films, social video, and visual assets
- persona-driven creative agents that can keep style, taste, and role consistent

GeeAgent should be capable, but not heavy. Its best version is a compact creative cockpit for people who make things with AI.

## For Builders

GeeAgent is still young, which is part of the charm. The project is close enough to the ground that contributors can still shape its language, its rituals, and its extension culture.

The codebase has two main centers: a native macOS workbench and a TypeScript runtime. Around them, persona and Gear are the two doors we expect many contributors to walk through: one for giving agents continuity and presence, the other for giving creators small tools that do one thing well.

If you want to help, the best contributions are focused and humane: make one workflow clearer, one creative tool easier to reach, one persona easier to understand, or one local task safer to hand to an agent.

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

Contributions are welcome, especially around:

- persona packages, visual presence, and creative agent design
- Gear development for local tools, media workflows, and creator utilities
- native macOS interaction, accessibility, and desktop polish
- runtime reliability, task continuation, approvals, and observable execution

Please keep PRs focused and avoid committing local secrets, caches, or machine-specific files.

## License

MIT

## Public Docs

The public docs go deeper than this README, but they are not meant to turn the project into a pile of implementation notes. They describe the ideas GeeAgent wants to keep stable as the product grows.

[Public Docs](https://aigc3yehe.github.io/geeagent/) | [Agent Persona](https://aigc3yehe.github.io/geeagent/?doc=docs/en/agent-persona.md) | [Gear Development](https://aigc3yehe.github.io/geeagent/?doc=docs/en/gear-development.md) | [Gee Basic Development](https://aigc3yehe.github.io/geeagent/?doc=docs/en/gee-basic-development.md)
