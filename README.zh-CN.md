# GeeAgent

[English](README.md) | [日本語](README.ja.md)

![macOS](https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6.1-FA7343?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-Native_UI-0A84FF?logo=swift&logoColor=white)
![AppKit](https://img.shields.io/badge/AppKit-macOS_Framework-1F6FEB)
![TypeScript](https://img.shields.io/badge/TypeScript-Agent_Runtime-3178C6?logo=typescript&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-SDK_Sidecar-339933?logo=node.js&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green.svg)

GeeAgent 是一个面向 macOS 的 AI 工作台项目，重点探索陪伴式交互、可视化任务执行，以及模块化运行时编排。

这个项目将原生 macOS 应用与 TypeScript agent runtime 结合起来，让交互、路由、审批、任务状态和模块执行在系统持续演进时依然保持可观察、可扩展、可调试。

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
- `TypeScript` 与 `Node.js`：GeeAgent runtime 与 Agent SDK session loop
- `TOML`：路由与模块配置

## 架构概览

GeeAgent 目前主要由四层组成：

1. 原生 macOS 外壳，负责 companion、workbench、菜单栏等交互界面。
2. TypeScript runtime，负责路由、执行契约、工作区状态、审批、会话和任务生命周期。
3. TypeScript runtime 内部的 Agent SDK session 层，负责真实 agent loop。
4. 面向一方能力与外部服务的模块化集成边界。

代表性 runtime 模块：

- `apps/agent-runtime/src/native-runtime`：持久化状态、快照、工具、turn、审批和命令分发
- `apps/agent-runtime/src/session.ts`：Agent SDK session 包装与权限回调
- `apps/agent-runtime/src/gateway.ts`：面向当前模型路由的 Anthropic 兼容 gateway
- `apps/agent-runtime/src/chat-runtime.ts`：聊天路由设置与 provider readiness

核心目录：

- `apps/macos-app`：原生 macOS 应用
- `apps/agent-runtime`：TypeScript GeeAgent runtime 与 Agent SDK 集成
- `config/*`：路由与模块配置
- `examples/agent-packs/*`：示例 agent pack

## 快速开始

### 前置要求

- macOS 15+
- 支持 Swift 6.1 的 Xcode
- Node.js 和 npm

### 构建原生应用

```bash
swift build --package-path apps/macos-app --scratch-path apps/macos-app/.swift-build
```

### 构建并启动原生工作台应用

```bash
bash apps/macos-app/script/build_and_run.sh
```

这个命令会构建 TypeScript runtime 并启动原生 macOS 应用。

### 运行 runtime 测试

```bash
npm run test --prefix apps/agent-runtime
swift test --package-path apps/macos-app --scratch-path apps/macos-app/.swift-build
```

## 贡献说明

欢迎贡献。为了让仓库保持清晰、专业、易审阅，建议遵循以下约定：

- 优先提交目标明确、边界清晰的 PR
- 不要提交机器相关文件、密钥、缓存文件和本地规划资料
- 如果修改影响到路由、任务生命周期、工作台快照或模块边界，请在 PR 中说明
- 修改 runtime 行为时，尽量补充对应测试

如果你扩展了运行时能力，最好同时说明由哪个 TypeScript 模块定义契约、由哪个 UI 界面消费它。

## 许可证

MIT
