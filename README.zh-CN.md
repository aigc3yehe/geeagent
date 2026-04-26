<p align="center">
  <img src="gee-nyko.png" alt="GeeAgent icon" width="112" style="border-radius: 24px;" />
</p>

<h1 align="center">GeeAgent</h1>

<p align="center"><strong>让Agent与众不同</strong></p>

<p align="center">
  <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white" />
  <img alt="Swift 6.1" src="https://img.shields.io/badge/Swift-6.1-FA7343?logo=swift&logoColor=white" />
  <img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-Native_UI-0A84FF?logo=swift&logoColor=white" />
  <img alt="AppKit" src="https://img.shields.io/badge/AppKit-macOS_Framework-1F6FEB" />
  <img alt="TypeScript Agent Runtime" src="https://img.shields.io/badge/TypeScript-Agent_Runtime-3178C6?logo=typescript&logoColor=white" />
  <img alt="MIT License" src="https://img.shields.io/badge/License-MIT-green.svg" />
</p>

<p align="center">
  <a href="README.md">English</a> | <a href="README.ja.md">日本語</a>
</p>

GeeAgent 是一个轻量的 macOS AI 工作台，面向 agent persona、本地应用辅助，以及 AI 视觉创作。

它不是一个试图吞下所有工作流的庞大全能 agent。GeeAgent 希望保持足够轻、足够近：像一个原生桌面伙伴，帮助用户处理日常任务、文件、本地应用、创意规划、AI 生图、AI 生视频、剪辑和发布。

GeeAgent 背后有一个很朴素的寄托：让 Agent 与众不同，让它们拥有自己的存在感、记忆、审美和帮助人的方式。

## 为什么是 GeeAgent

很多 agent 工具仍然从一个空白聊天框开始。GeeAgent 想问一个不同的问题：如果 agent 不只是提示词窗口，而是一种长期存在的创作人格，会发生什么？

GeeAgent 围绕三件事展开：

- **Agent Persona**：agent 应该拥有稳定的身份、声音、视觉存在、边界感和工具姿态。Persona 不是装饰，它是人和 AI agent 建立信任、记忆、审美与协作关系的方式。
- **Gear**：有用的 agent 能力不应该全部塞进一个单体应用。Gear 是可选的本地应用、组件和能力包，未来可以发展为开放的桌面应用市场。
- **轻量聚焦**：GeeAgent 应该简单、快速、可读。它能处理日常本地工作，但会特别偏向 AI 视觉创作：图片、视频、片段、发布流程和创作者运营。

<p align="center">
  <img src="ui.png" alt="GeeAgent UI preview" />
</p>

## Agent Persona

GeeAgent 将 persona 作为一等产品层。一个 persona 可以定义 agent 如何说话、关心什么、如何呈现、偏好哪些技能，以及允许使用哪些工具。

长期方向上，persona 会和 agent 演员协议连接起来。到那个阶段，persona 不只是本地皮肤或提示词文件，而是更深层 actor record 的可读界面：身份、能力、创作历史、授权规则、署名关系和经济参与。桌面 agent 会成为用户体验、导演、信任和调度这个 actor 的地方。

这对创意 AI 尤其重要。AI 角色、AI 演员、AI 助手和 AI 协作者如果要跨故事、视频、工具和市场持续出现，就不能只是一段提示词。它们需要连续性。

## Gear：开放应用市场

GeeAgent 的 Gear 系统，是走向开放本地应用市场的路径。

一个 Gear 可以是原生应用、Home 组件、本地工具界面，或能力包。Gear 应该保持可选：缺失、禁用、损坏或未安装的 Gear，都不应该影响主工作台运行。

目标是务实而适合创作者：

- 安装或复制小型本地工具，而不是让核心应用越来越臃肿
- 将具体应用逻辑保留在 Gear 边界内
- 只向 agent 暴露已声明的能力
- 为第三方创作者围绕媒体、自动化、发布和本地工作流构建工具保留路径

GeeAgent 应该像一个小型创作工作台，而不是一座插件迷宫。

## 为视觉创作者而生

GeeAgent 主要面向两个强场景。

第一，它帮助用户完成本地应用辅助：文件、命令、任务状态、审批、设置，以及那些 agent 能看到流程时会更容易完成的小型桌面工作。

第二，它针对 AI 视觉生产进行优化。产品方向会特别重视：

- AI 生图与提示词迭代
- AI 生视频与镜头规划
- 片段选择、剪辑与打包
- 短片、社交视频和视觉资产的发布流程
- 能保持风格、审美和角色一致性的 persona 创作 agent

GeeAgent 应该有能力，但不沉重。它最好的形态，是一个为 AI 创作者准备的紧凑创作驾驶舱。

## 给建设者

GeeAgent 还很早，这也是它有趣的地方。它离地面还很近，后来加入的人仍然可以影响它的语言、习惯和扩展文化。

代码库有两个主要中心：原生 macOS 工作台，以及 TypeScript runtime。围绕它们，persona 和 Gear 是最重要的两扇门：前者让 agent 拥有连续性和存在感，后者让创作者拥有小而专注的工具。

如果你想参与，最好的贡献往往不需要宏大：让一个流程更清楚，让一个创作工具更容易抵达，让一个 persona 更容易被理解，或者让一个本地任务更安全地交给 agent。

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

欢迎贡献，尤其是这些方向：

- persona package、视觉存在和创意 agent 设计
- 面向本地工具、媒体流程和创作者实用工具的 Gear 开发
- 原生 macOS 交互、无障碍体验和桌面质感
- runtime 可靠性、任务继续、审批和可观察执行

请尽量保持 PR 聚焦，不要提交本地密钥、缓存或机器相关文件。

## 许可证

MIT

## 公开文档

公开文档会比 README 走得更深，但它不应该把项目变成一堆实现细节。它更像 GeeAgent 的几条长期线索：当产品继续生长时，哪些东西不该丢。

[公开文档](https://aigc3yehe.github.io/geeagent/) | [Agent Persona](https://aigc3yehe.github.io/geeagent/?doc=docs/zh-CN/agent-persona.md) | [Gear 开发](https://aigc3yehe.github.io/geeagent/?doc=docs/zh-CN/gear-development.md) | [Gee 基础开发](https://aigc3yehe.github.io/geeagent/?doc=docs/zh-CN/gee-basic-development.md)
