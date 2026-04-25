# GeeAgent

[English](README.md) | [日本語](README.ja.md)

![macOS](https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6.1-FA7343?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-Native_UI-0A84FF?logo=swift&logoColor=white)
![AppKit](https://img.shields.io/badge/AppKit-macOS_Framework-1F6FEB)
![Rust](https://img.shields.io/badge/Rust-Workspace-000000?logo=rust&logoColor=white)
![Cargo](https://img.shields.io/badge/Cargo-Build_System-8C4A2F?logo=rust&logoColor=white)
![Tauri](https://img.shields.io/badge/Tauri-v2-24C8DB?logo=tauri&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green.svg)

GeeAgent 是一个面向 macOS 的 AI 工作台项目，重点探索陪伴式交互、可视化任务执行，以及模块化运行时编排。

这个项目将原生 macOS 外壳与 Rust 运行时结合起来，让交互、路由、审批、任务状态和模块执行在系统持续演进时依然保持可观察、可扩展、可调试。

## 项目目标

大多数 AI 产品仍然以聊天框或命令行为主要入口。GeeAgent 希望探索另一种形态：

- 可召唤的桌面原生助手，而不是浏览器标签页
- 能看见任务状态、审批流程和执行进展的工作台
- 用模块化运行路径替代单体黑盒式 agent loop
- 面向用户本地状态与工作流的 local-first 配置
- 保持开放、易于扩展和便于贡献者理解的系统架构

## 技术栈

GeeAgent 当前主要使用以下组件：

- `SwiftUI` 与 `AppKit`：原生 macOS 外壳和界面
- `Swift Package Manager`：macOS 应用包管理
- `Rust` 与 `Cargo`：运行时逻辑、执行契约、路由与工作区状态
- `Tauri v2`：用于壳层与运行时的桥接组件
- `TOML`：路由与模块配置

## 架构概览

GeeAgent 目前主要由三层组成：

1. 原生 macOS 外壳，负责 companion、workbench、菜单栏等交互界面。
2. Rust 运行时层，负责路由、执行契约、工作区状态、模块分发和任务生命周期。
3. 面向一方能力与外部服务的模块化集成边界。

代表性运行时 crate：

- `agent-kernel`：校验并加载 agent pack
- `automation-engine`：自动化策略与调度规则
- `execution-runtime`：提示执行与自动化草稿
- `model-router`：模型与 provider 路由
- `module-gateway`：模块清单与执行契约
- `runtime-kernel`：一方工具调用规则
- `task-engine`：任务阶段与生命周期
- `workspace-runtime`：工作台快照契约

核心目录：

- `apps/macos-bridge`：原生 macOS 外壳
- `apps/desktop-shell/src-tauri`：Rust bridge / runtime 集成层
- `crates/*`：核心运行时 crate
- `config/*`：路由与模块配置
- `examples/agent-packs/*`：示例 agent pack

## 快速开始

### 前置要求

- macOS 15+
- 支持 Swift 6.1 的 Xcode
- Rust toolchain
- Cargo

### 构建原生应用

```bash
swift build --package-path apps/macos-bridge
```

### 构建并启动工作台

```bash
bash apps/macos-bridge/script/build_and_run.sh
```

这个命令会同时构建原生 macOS 应用以及工作台依赖的 Rust runtime bridge。

### 运行 Rust 工作区测试

```bash
cargo test
```

## 贡献说明

欢迎贡献。为了让仓库保持清晰、专业、易审阅，建议遵循以下约定：

- 优先提交目标明确、边界清晰的 PR
- 不要提交机器相关文件、密钥、缓存文件和本地规划资料
- 如果修改影响到路由、任务生命周期、工作台快照或模块边界，请在 PR 中说明
- 修改 crate 级运行时行为时，尽量补充对应测试

如果你扩展了运行时能力，最好同时说明由哪个 crate 定义契约、由哪个 UI 界面消费它。

## 许可证

MIT
