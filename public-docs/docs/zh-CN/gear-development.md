# Gear 开发

## 状态与日期

文档日期：2026-05-01。

状态：Gear Platform V1 公开开发标准。本文同时记录当前实现状态和目标架构。当前已经实现的能力会明确写成“当前”；尚未完全落地但已经确定方向的内容会写成“目标”或“V1 标准”。

本文面向 GeeAgent 的开源协作者、Gear 开发者，以及需要理解 GeeAgent 内置 app / 挂件系统边界的人。它不是营销文档，也不是远期市场蓝图；它是第一版可落地的平台化 Gear 标准。

## 目的

Gear 是 GeeAgent 的可选内置 app 和首页挂件平台。它的目标不是继续把每个 app 的业务代码塞进主工作台，而是形成一个小型、本地优先、可复制安装的 app 生态。

核心目标：

- 一个 gear 是一个独立 package。
- 一个 gear 可以被复制、导入、默认启用、更新或删除；V1 catalog 不提供关闭 gear 的 UI。
- 删除 gear 文件夹后，重启 GeeAgent 就不再看到这个 gear。
- 把符合标准的 gear 文件夹放到用户数据目录后，重启或刷新后就能看到这个 gear。
- 一个损坏、缺失、策略阻止、未安装完成的 gear 不能破坏 GeeAgent chat、task、settings、runtime startup 或其他 gears。
- 一个 gear 通过 `gear.json` 声明名称、描述、开发者、封面、版本、入口、依赖、权限和未来 agent capability。
- GeeAgent 负责发现、校验、安装准备、默认启用、打开窗口、展示挂件和连接未来 agent bridge。
- Gear 自己负责业务逻辑、资源、数据、依赖说明和可被调用的能力声明。
- 未来 root agent 通过统一控制协议调用 gear，而不是把 gear-specific pseudo-tool 直接塞进 agent runtime。

V1 要保持实用，不做过度复杂的平台设计。V1 的重点是本地复制 / 导入、bundled gears、依赖预检和首次安装、默认启用、native macOS 体验，以及未来 `gear.invoke` 接入准备。V1 catalog 不展示关闭入口；策略级禁用属于内部保护状态，不是普通用户操作。V1 不包含远程市场、支付、评分、评论、远程自动更新或强制开发者签名。

## 名词定义

- `Gear`：GeeAgent 中可选安装、默认启用的本地 app 或挂件 package。
- `Gear app`：可以从 Gears 页面打开的完整应用。复杂 gear 应该打开独立 macOS 窗口，而不是嵌在 GeeAgent 主窗口里。
- `Gear widget`：显示在 Home 上的小型信息组件，例如 BTC 价格、CPU / 内存监控。
- `Gear package`：一个以 gear id 命名的文件夹，里面包含 `gear.json`、README、资源、脚本、setup 元数据、源码或 app 文件。
- `GearHost`：GeeAgent 内部负责发现、校验、导入、依赖准备、打开 gear、管理状态、暴露能力列表的平台管理层。
- `GearKit`：GearHost、第一方 native gears 和未来 adapter 共享的稳定 contract。它不应该包含具体 app 业务概念。
- `gear.json`：Gear manifest。它是 package 的最小发现文件，也是 catalog 展示、依赖准备和未来 agent capability 的声明入口。
- `Dependency preflight`：打开或启用 gear 前检查依赖是否存在、版本是否满足、权限是否允许的过程。
- `Capability`：gear 在 manifest 里声明的可被未来 root agent 调用的能力。capability 是声明，不是单独的全局 agent tool。
- `Codex plugin projection`：GeeAgent 生成的 Codex-compatible package 和 Gee MCP export bridge，让 Codex 可以发现并调用被明确导出的 GeeAgent capabilities。它是 Gear 的导出视图，不替代 Gear package、native Gear UI、GearHost 或 GeeAgent runtime 语义。

## 当前实现状态

当前活跃 macOS app 路径是：

```text
apps/macos-app/
```

当前 GearKit 代码位于：

```text
apps/macos-app/Sources/GearKit/
├── GearCapabilityRecord.swift
├── GearDependencyManifest.swift
├── GearKind.swift
├── GearManifest.swift
└── ModuleDisplayMode.swift
```

当前 GearHost 代码位于：

```text
apps/macos-app/Sources/GearHost/
├── GearDependencyPreflight.swift
├── GearPreparationService.swift
├── GearRecordMapping.swift
├── GearHost.swift
├── GearNativeWindowDescriptor.swift
└── GearRegistryCompatibility.swift
```

当前 bundled gear package skeleton 位于：

```text
apps/macos-app/Gears/
├── media.library/
├── hyperframes.studio/
├── media.generator/
├── smartyt.media/
├── twitter.capture/
├── bookmark.vault/
├── wespy.reader/
├── app.icon.forge/
├── btc.price/
└── system.monitor/
```

当前第一方 native gear 的主要实现仍然由 host 编译：

```text
apps/macos-app/Sources/GeeAgentMac/Modules/MediaLibrary/
apps/macos-app/Sources/GeeAgentMac/Modules/HyperframesStudio/
apps/macos-app/Sources/GeeAgentMac/Modules/MediaGenerator/
apps/macos-app/Sources/GeeAgentMac/Modules/SmartYTMedia/
apps/macos-app/Sources/GeeAgentMac/Modules/TwitterCapture/
apps/macos-app/Sources/GeeAgentMac/Modules/BookmarkVault/
apps/macos-app/Sources/GeeAgentMac/Modules/WeSpyReader/
apps/macos-app/Sources/GeeAgentMac/Modules/AppIconForge/
apps/macos-app/Sources/GeeAgentMac/Views/Content/HomeWidgetsView.swift
```

当前已经具备的能力：

- `GearKit` / `GearHost` 文件边界已经存在，当前仍保持单 SwiftPM executable target。
- bundled gear packages 已经移出主 app source，位于 `apps/macos-app/Gears`。
- 可以从 bundled resources 和用户 Application Support 扫描 `gear.json`。
- 无效 manifest 文件夹会降级为 Gears catalog 中的安装异常，而不是让应用崩溃。
- folder name 必须匹配 manifest id，否则显示为安装异常。
- Gear 默认启用；内部保留策略禁用状态，但 V1 catalog 不提供用户关闭入口。
- 有 dependency preflight 和 setup snapshot model。
- `hyperframes.studio` 已经具备 Node、npm、Hyperframes、FFmpeg、FFprobe 的依赖计划。
- Gears catalog 已经有检查、安装中、失败、打开等状态。
- 第一方 `media.library` 和 `hyperframes.studio` 已经可以作为 native window 打开。
- `media.generator` 是当前第一方 Gear app。它提供原生媒体生成界面，图片生成通过全局 Xenodia 渠道执行，并向 agent 暴露列出模型、创建生成任务、读取任务状态的结构化能力。
- 已经有第一版 V1 host bridge surface：`gee.app.openSurface`、渐进式 Gear capability disclosure 和统一 Gear invocation。
- `bookmark.vault` 是当前第一方 Gear app。它把任意文本或 URL 保存到 `gear-data/bookmark.vault`，媒体 URL 使用与 `smartyt.media` 同一类 `yt-dlp` 元数据能力，Twitter/X 推文 URL 先走嵌入元数据路径，其他网站则回退到基础网页元数据 fetch。
- `wespy.reader` 是当前第一方 Gear app。它封装 MIT 许可的 WeSpy Python package，把微信公众号文章、微信公众号专辑和通用文章页面抓取成 Markdown 优先的本地 task 文件。
- `app.icon.forge` 是当前第一方 Gear app。它把一张本地源图转换为 macOS app 图标 package，包含圆角安全区渲染、`AppIcon.icns`、`AppIcon.iconset`、`AppIcon.appiconset` 和 1024px 预览图。
- `telegram.bridge` 是当前第一方 Gear。它提供原生 Telegram Bridge 界面、基于 GearHost/Keychain 的 push-only Telegram 投递、面向 Codex 远控和 GeeAgent 直连对话的 worker polling service，以及 Gee direct 消息的 Phase 3 channel ingress。Codex export 已对 status/list/send push capabilities 启用；信道创建仍保留在 Gee 原生设置流程里，因为 bot token 绑定和目标确认属于本地配置步骤。
- 在完整 SDK/MCP tool exposure 完成前，过渡期的 `host_action_intents` 可以让第一方 runtime turn 把 native Gear actions 交回 GeeAgentMac 顺序执行。
- 外部 Codex 调用现在通过生成的 `geeagent-codex` plugin 和 Gee MCP server 创建 shared-store external invocations。GeeAgentMac 会轮询该队列，并把 `gee_invoke_capability` / `gee_open_surface` 通过 runtime 使用的同一 GearHost bridge 执行，然后 Codex 通过 `gee_get_invocation` 读取结果。已导出的内置能力包括低风险的 `media.generator` 模型/任务查询、仅面向明确用户请求的高风险 `media.generator/media_generator.create_task` 图片任务或 batch 创建、`media.library` 视图过滤/文件夹聚焦和明确本地文件导入、仅面向明确用户请求的高风险 `app.icon.forge/app_icon.generate` 图标 package 生成、中风险的 `bookmark.vault/bookmark.save` Gear-owned bookmark 写入，以及中风险的 `telegram.bridge/telegram_push.send_message` 已配置信道 Telegram push 投递。
- `btc.price` 和 `system.monitor` 已经作为 Home widgets 的方向存在。

当前主要缺口：

- 第一方 gear 的业务逻辑仍在主 app source tree 中。
- Gear package 文件夹还不是完整实现边界。
- 第三方 gear import 还没有落地。
- 面向所有 Gear capabilities 的完整 agent-runtime SDK/MCP tool injection 还没有完成。
- 外部 Codex 覆盖范围仍然有意保持很窄。只有显式设置 `exports.codex.enabled: true` 的 capability 对 Codex 可见；更多 provider 生成、下载、导入、用户文件和高副作用能力会保持隐藏或显式禁用，直到它们的 approval、artifact 和 failure 语义完成端到端审计。
- `telegram.bridge` 仍需要生产 daemon 管理和更完整的设置体验打磨，但当前 bridge 已包含原生 GearHost push 投递、Keychain token lookup、push-channel 创建、worker polling、Codex remote commands 和 Phase 3 直连对话入口。
- `GearKit` / `GearHost` 还没有拆成独立 SwiftPM targets。

## 目标架构

目标架构分四层：

```text
GeeAgentMac main app
        |
        v
GearHost
        |
        v
GearKit
        |
        v
Gear Packages
```

## GeeAgentMac Main App

GeeAgentMac main app 负责主工作台，不负责 gear 业务。

职责：

- 主 workspace shell、Home、chat、tasks、settings、side rail 和 app chrome。
- 打开 Gears catalog。
- 向 GearHost 查询有哪些 gears，以及每个 gear 的状态。
- 请求 GearHost 准备和打开某个 gear。
- 承载 GearHost adapter 提供的 gear window 或 Home widget surface。

非职责：

- 不放 gear 业务逻辑。
- 不在 `WorkbenchStore` 中放 gear dependency recipe。
- 不直接理解第三方 gear 的内部文件。
- 不在 agent runtime 中实现 gear-specific tools。

## GearHost

GearHost 是 Gear 平台管理层，建议用 Swift 实现，因为它要直接处理 macOS 文件系统、Application Support、window、process、permission 和 native UI 集成。

职责：

- 发现 bundled 和 user-installed gear folders。
- 解码并校验 `gear.json`。
- 合并 bundled gear 和用户 gear 记录。
- 管理默认启用和策略阻止状态。
- 跟踪 install / preparation state。
- 执行 dependency preflight 和 setup。
- 导入 `.geegear.zip` 或 gear folder。
- 把 open request 路由到正确 adapter。
- 提供 Home widget records。
- 向未来 agent bridge 提供 ready + policy-allowed capability declarations。
- 保存每个 gear 的 setup logs 和 status snapshots。

GearHost 不应该知道 Eagle 文件夹结构、Hyperframes 项目内部模型、BTC 价格格式等具体业务细节。这些属于 gear 自己。

## GearKit

GearKit 是稳定共享 contract。它由 GearHost、第一方 native gears 和未来 adapter 使用。

V1 内容：

- `GearManifest`
- `GearKind`
- `GearEntry`
- `GearDependencyPlan`
- `GearDependencyItem`
- `GearPreparationState`
- `GearCapability`
- `GearPermission`
- `GearRecord`
- `GearAppAdapter`
- `GearWidgetAdapter`
- `GearProcessAdapter`
- `GearWebViewAdapter`

GearKit 不应该包含 app-specific 概念。例如 Eagle folders、media duration filter、Hyperframes project template、BTC display formatting 都不属于 GearKit。

## Gear Packages

每个 gear 拥有一个文件夹。删除这个文件夹后，重启或刷新 registry 后 gear 消失。把有效 package 复制到用户 gear 目录后，重启或刷新 registry 后 gear 出现。

开发期 bundled gears 的目标目录：

```text
apps/macos-app/Gears/<gear-id>/
```

迁移期间 registry 会兼容旧资源目录命名：

```text
gears/
Gears/
```

实际用户安装目录：

```text
~/Library/Application Support/GeeAgent/gears/<gear-id>/
```

Gear 用户数据目录：

```text
~/Library/Application Support/GeeAgent/gear-data/<gear-id>/
```

Gear 日志目录：

```text
~/Library/Application Support/GeeAgent/gear-data/<gear-id>/logs/
```

V1 package layout：

```text
<gear-id>/
├── gear.json
├── README.md
├── assets/
├── setup/
├── scripts/
├── data/
└── src/ or app/
```

Package 规则：

- 文件夹名称必须等于 `gear.json.id`。
- `gear.json` 必须存在。
- 可交付 gear 必须包含 `README.md`。
- 只有 `gear.json` 的文件夹是 manifest stub，不是完整可交付 gear。
- package 文件被视为 app code 和 static resources。
- 可变用户数据必须写到 `gear-data/<gear-id>/`。
- 一个 gear 不能读取另一个 gear 的私有 package 文件。
- 一个 gear 不能写 GeeAgent source folders。
- 一个 gear 不能把业务数据写进 `WorkbenchStore`。

## 语言与 Runtime 策略

V1 支持多种实现方式，但必须明确不同方式的安全性和适用范围。

Host、GearHost、GearKit 应该使用 Swift。

原因：

- GeeAgent 是 native macOS app。
- Gear window、菜单、键盘快捷键、drag/drop、Quick Look、Finder handoff、permissions 和 accessibility 都需要原生体验。
- Gear 需要和 macOS Application Support、process supervision、window lifecycle、sandbox / permissions 贴近集成。

第一方 native gear UI 应该使用 Swift、SwiftUI 和 AppKit。

适用范围：

- `media.library`
- `hyperframes.studio`
- 需要 Quick Look、Finder、native video / image preview、drag/drop、菜单、键盘快捷键的复杂 app。

第三方 AA-style gear 分享在 V1 应优先使用：

- `webview`：GeeAgent 在 native window shell 中承载 package 内的本地 UI 文件。
- `external_process`：GeeAgent 启动并监督本地进程，通过 stdio-json 或本地协议通信。

原因：

- 用户可以把 gear folder 或 `.geegear.zip` 复制 / 导入到 Application Support。
- GeeAgent 不应该在 V1 动态编译并加载任意 Swift source 到主进程。
- 外部进程比 in-process arbitrary code 更容易停止、记录日志、超时和隔离。

第三方 native Swift plugin 应该放到后续签名 bundle 或 XPC 路线，而不是 V1 默认能力。

Gear 内部的数据处理可以使用 TypeScript、Python、CLI、wasm、本地模型或其他 runtime，但必须通过 manifest 声明入口、依赖和权限。

## Manifest V1

最小 V1 manifest：

```json
{
  "schema": "gee.gear.v1",
  "id": "aa.cool.gear",
  "name": "Cool Gear",
  "description": "A useful local gear.",
  "developer": "AA",
  "version": "0.1.0",
  "category": "Utilities",
  "kind": "app",
  "entry": {
    "type": "external_process",
    "command": "scripts/start.sh",
    "protocol": "stdio-json"
  },
  "permissions": [],
  "dependencies": {
    "install_strategy": "on_open",
    "items": []
  },
  "agent": {
    "enabled": false,
    "capabilities": []
  }
}
```

必填字段：

- `schema`
- `id`
- `name`
- `description`
- `developer`
- `version`
- `kind`
- `entry`

推荐字段：

- `category`
- `icon`
- `cover`
- `homepage`
- `license`
- `platforms`
- `permissions`
- `dependencies`
- `agent.capabilities`

迁移期间 V1 应接受现有 `kind`：

- `atmosphere`：完整 app surface，可从 catalog 打开。
- `widget`：Home 上的小型挂件。

V1 新文档推荐标准化为：

- `app`
- `widget`

`category` 可以表达产品分类，例如：

- `Atmosphere`
- `Media`
- `Utilities`
- `Monitoring`
- `Creative`

`kind` 决定运行和呈现方式，`category` 只用于 catalog 组织。

## Entry Standard

V1 entry types：

- `native`：第一方或 host-known native adapter。
- `widget`：Home widget adapter。
- `external_process`：由 GearHost 启动和监督的本地进程。
- `webview`：在 native WebView shell 中加载 package 内本地文件。

`native` 示例：

```json
{
  "entry": {
    "type": "native",
    "native_id": "media.library"
  }
}
```

`widget` 示例：

```json
{
  "entry": {
    "type": "widget",
    "widget_id": "btc.price"
  }
}
```

`external_process` 示例：

```json
{
  "entry": {
    "type": "external_process",
    "command": "scripts/start.sh",
    "protocol": "stdio-json",
    "health_timeout_seconds": 20
  }
}
```

`webview` 示例：

```json
{
  "entry": {
    "type": "webview",
    "root": "app/index.html",
    "allow_remote_content": false
  }
}
```

V1 不应该继续添加 entry type，除非真实 gear 需要且 GearHost 已有对应 adapter。

## Dependency Standard

依赖策略是 global-first。

规则：

- 如果系统里已有兼容全局依赖，gear 直接使用。
- 如果必需依赖缺失，在用户打开该 gear 时触发 setup flow。
- 不在 GeeAgent 启动时安装依赖。
- 不为策略阻止的 gear 运行依赖安装。
- 依赖安装失败只影响当前 gear。
- global installer 会改变用户开发环境，必须对用户可见。
- gear-local installer 只能写 gear package 或 gear-data 允许的位置。

依赖 manifest 示例：

```json
{
  "dependencies": {
    "install_strategy": "on_open",
    "items": [
      {
        "id": "node",
        "kind": "runtime",
        "scope": "global",
        "required": true,
        "detect": {
          "command": "node",
          "args": ["--version"],
          "min_version": "22.0.0"
        },
        "installer": {
          "type": "recipe",
          "id": "brew.install.node"
        }
      },
      {
        "id": "ffmpeg",
        "kind": "binary",
        "scope": "global",
        "required": true,
        "detect": {
          "command": "ffmpeg",
          "args": ["-version"]
        },
        "installer": {
          "type": "recipe",
          "id": "brew.install.ffmpeg"
        }
      }
    ]
  }
}
```

支持的 dependency kinds：

- `binary`：可执行 helper 或 CLI。
- `framework`：native framework 或 dylib bundle。
- `model`：本地模型、embedding index 或 inference asset。
- `data`：seed database、lookup table、templates 或 static content。
- `runtime`：external process gear 需要的语言或 runtime。

支持的 dependency scopes：

- `global`：从系统环境或已知安装位置解析，缺失时可通过用户可见 setup flow 安装。
- `gear_local`：相对 gear folder 解析，只为当前 gear 准备。

支持的 installer types：

- `recipe`：运行 host-known install recipe，例如 Homebrew install、npm global install 或官方安装器引导。
- `script`：运行 gear-local installer script。
- `archive`：解压 gear-local archive 到声明 target。
- `none`：声明依赖必须已经存在，不自动安装。

Installer 要求：

- 必须 idempotent。
- 重复运行不能破坏 gear。
- `gear_local` installer 不得写出当前 gear 边界，临时目录除外。
- `global` installer 必须通过用户可见 flow 展示动作、日志、失败和重试。
- 需要网络的 installer 必须声明 `network.download`。

## First-Run Install Flow

当用户打开或启用 gear 且必需依赖缺失时，GeeAgent 不应该立即失败，而应该为这个 gear 进入 setup flow。

状态机：

```text
installed -> checking -> ready
installed -> checking -> needs_setup
needs_setup -> installing -> ready
needs_setup -> installing -> install_failed
install_failed -> installing -> ready
policy_blocked -> checking/installing only after policy changes
```

状态含义：

- `invalid`：manifest 或 package 无效。
- `installed`：package 可发现，manifest 有效，但尚未确认依赖 ready。
- `disabled`：内部或策略禁用。V1 catalog 不提供用户禁用按钮。
- `checking`：dependency 或 permission preflight 正在运行。
- `needs_setup`：必需依赖缺失或版本不兼容。
- `installing`：setup 正在进行。
- `ready`：可以打开或渲染。
- `install_failed`：setup 失败，其他功能继续工作。
- `blocked`：策略或权限阻止使用。

Gears catalog 按钮含义：

- `Open`：gear 已 ready，可以启动。
- `Checking...`：preflight 正在运行。
- `Install Dependencies`：缺少依赖且可安装。
- `Installing...`：正在安装，按钮不可重复触发。
- `Retry Install`：上一次安装失败，点击重试。
- V1 catalog 不展示 `Enable` / `Disabled` 用户操作。Gear 默认启用；无法使用时展示 blocked、installing 或 failed 状态。

Home widget 使用同一套依赖流。依赖缺失的 widget 不应该在 Home 上显示破损卡片，而应该在 Gears catalog 显示 installing 或 failed 状态。

## Import And Install Standard

V1 支持两种本地安装输入：

- Gear folder。
- `.geegear.zip`。

安装目标：

```text
~/Library/Application Support/GeeAgent/gears/<gear-id>/
```

导入流程：

- 用户选择 folder 或 `.geegear.zip`。
- 如果是 zip，先解压到 temporary directory。
- 拒绝 path traversal。
- 拒绝多个 top-level packages。
- 校验 `gear.json`。
- 确认 folder name 等于 manifest `id`。
- 检查 schema、version、platforms 和 entry type。
- 如果同 ID 已存在，询问 replace / update / cancel。
- 原子复制到 Application Support。
- 刷新 GearHost registry。
- 在 Gears catalog 展示状态。

V1 不需要远程 marketplace。V1 必须先把本地分享做好：AA 开发一个 gear 后，可以把文件夹或 `.geegear.zip` 发给其他人；其他人复制到用户数据目录或执行导入，就能安装。

## Permission Standard

V1 permission 必须显式且尽量少。

推荐 permission IDs：

- `filesystem.read.user_selected`
- `filesystem.write.user_selected`
- `filesystem.read.gear_storage`
- `filesystem.write.gear_storage`
- `network.download`
- `network.api`
- `process.spawn`
- `shell.execute`
- `camera`
- `microphone`
- `automation.apple_events`

规则：

- 未声明的高风险能力不能运行。
- 需要下载的 installer 必须声明 `network.download`。
- external process gear 必须声明 `process.spawn`。
- shell script 必须声明 `shell.execute`。
- 高风险权限需要用户确认。
- permission 只表达 Gear 需求，不替代 macOS 系统权限。

## Storage Standard

Package directory：

```text
~/Library/Application Support/GeeAgent/gears/<gear-id>/
```

Mutable data directory：

```text
~/Library/Application Support/GeeAgent/gear-data/<gear-id>/
```

推荐 data layout：

```text
gear-data/<gear-id>/
├── config.json
├── state/
├── cache/
├── logs/
├── projects/
└── exports/
```

规则：

- package directory 保存 manifest、code、static resources、setup files 和 scripts。
- data directory 保存用户数据、状态、缓存、生成结果和 logs。
- 一个 gear 不能写另一个 gear 的 data directory。
- 一个 gear 不能写 GeeAgent source directories。
- package 里的 `data/` 只能作为 seed 或 static data，不应该承载用户运行时状态。

## UIUX Standard

Gear 必须提供 macOS 原生体验。

规则：

- Gear app 应该像 native macOS app，而不是 web page 嵌入主窗口。
- 复杂 app 应该打开自己的独立窗口。
- 优先使用 SwiftUI / AppKit window、menu、keyboard command、system sheet、popover、drag/drop、Quick Look、Finder handoff 和 accessibility patterns。
- WebView gear 也必须被 native shell 承载。
- Home widget 必须轻量，不应该嵌入完整 app navigation。
- 缺少依赖时显示 setup state，不显示破损 UI。
- 组件可以被美化，但行为要符合 macOS 用户预期。
- Gear catalog 不应该堆叠过多容器。优先使用浅层导航、清晰列表、状态 badge 和必要的操作按钮。
- Button group 和 component group 不应依赖父容器边框来表达层级，优先使用就近分组和一致样式表达关系。
- 下拉、弹窗、按钮、slider、context menu 等组件需要自定义视觉质量，但交互模型仍应接近 macOS。

## Provider And Channel Ownership

Provider 和渠道配置属于 GeeAgent 全局基础设施，不属于 Gear 状态。

规则：

- 主 app runtime 负责 provider routing、API key、endpoint URL、readiness check 和 secret storage。
- Gear package 不能在 `gear.json`、package 文件或 `gear-data/<gear-id>/` 中保存 provider API key、长期 token 或渠道 secret。
- Gear 可以声明自己需要某个全局网络能力，例如 Xenodia 图片生成，但必须通过 Gee host/runtime 边界请求已配置好的渠道。
- Xenodia 图片生成作为全局 provider channel 暴露，和 chat routing 属于同一层基础设施。当前渠道包含图片生成和 task retrieval endpoint，后续可以扩展 dedicated storage upload endpoint。
- 生成参考图必须使用全局 Xenodia media channel。没有单独 Xenodia storage API 配置时，本地参考图可以直接通过 Xenodia 图片生成请求的 multipart `image_input` 发送；Gear 不能重新引入七牛或其他 package-local 对象存储。
- 第一方 Gear 可以展示未来 provider 占位，例如视频或音频生成，但在全局 provider 层支持前，不能接入从参考项目复制来的非 Xenodia 供应商。
- Provider 失败必须以结构化错误返回给 active run。Gear UI 可以展示简短状态，但最终用户可见文案仍由 active agent/LLM 生成。

## Agent Control Bridge

Gear 不定义完整 agent protocol。agent runtime 负责控制协议、权限语义、run events、approval flow 和 continuation semantics。

当前 V1 已经实现第一版 native Gee host bridge surface：

- `gee.app.openSurface` 按 id 打开 Gee surface 或 Gear window，例如 `media.library`。
- `gee.gear.listCapabilities` 先以紧凑 summary 暴露已启用 Gear capabilities，包括 capability id 和必填参数。
- `gee.gear.invoke` 通过统一 host bridge 调用一个已声明的 Gear capability。
- phase-2 SDK runtime 已经通过 `gee` MCP bridge tools 把这些控制能力暴露给 active agent：`app_open_surface`、`gear_list_capabilities`、`gear_invoke`。
- MCP Gear tools 会暂停同一个 SDK run，发出 `host_action_intents`，由 GeeAgentMac 执行 native Gear action，再把结构化 host results 返回并恢复同一个 run。如果 agent 检查结果后还需要另一个 Gear 步骤，同样的 pause / execute / resume 循环会继续。
- 如果当前 SDK session 没有暴露 `gee` MCP tools，GeeAgent 必须返回结构化 runtime failure，不能切换到 fallback 执行路径、不能用读源码代替 bridge，也不能声称任务已完成。
- 历史 host-action 控制帧只属于迁移兼容数据。runtime 必须在 transcript projection 前消费或拒绝它们，GeeAgentMac 不能把它们当普通聊天文本展示。可见 chat 应按 transcript event 顺序展示用户文本、类型化的 plan/focus/stage activity 行、有意义的 thinking state、tool invocation/result 行和 assistant 回复。当最终 assistant 回复已经存在时，前面的 work trace 行可以折叠成紧凑的 `Worked` 区域，其中的每一行动作仍然可以单独展开。setup、delegation、同 run Gear pause/resume breadcrumb、finalize，以及模型写出的 `Stage complete:` 进度片段这类低信号 runtime plumbing 不应该被提升成醒目的 thinking 块或 chat 气泡。
- `host_action_intents` 由 active SDK run 的 MCP Gear bridge 创建，并由 GeeAgentMac 按顺序执行。复杂采集或多 Gear 请求必须继续由 agent 通过 MCP bridge 规划。
- 通过 `media.filter` 设置的媒体库筛选会作为 active filters 体现在原生 UI 中。用户可以通过 `All` 或 `Clear filters` 回到完整媒体视图。
- `media.filter`、`media.focus_folder` 和 `media.import_files` 要求媒体库已经获得 macOS 授权。媒体 Gear 应先尝试恢复已保存的 security-scoped access；如果 bookmark 失效或不可读，应回退到已保存的上次媒体库路径，并在需要时让 macOS 显示可见的一次性授权提示。打开 Media Library 窗口不能等待这次恢复完成；窗口应先出现并展示有上限的恢复进度。如果恢复超时前仍无法恢复任何媒体库，Gear action 必须返回带有 `code: "gear.media.authorization_required"` 和 `media.library` 的 `navigate.module` 意图的结构化失败，而不是误报成功。
- Runtime turn 必须在 tool-use 和 tool-result event 到达时增量写入 transcript。GeeAgentMac 应能在 Gear workflow 仍在运行时刷新当前 Chat transcript，让用户逐步看到每一次 bridge 调用，而不是等最终回复出来后一次性看到多张已完成的 tool card。
- Tool request 必须在执行前经过 GeeAgent 的 Tool Boundary Gateway。Gateway 负责规范化参数、校验目标、选择执行 adapter，并在 transcript projection 前规范化结果。这同时适用于 provider 转换来的 tool call、Claude SDK native tool 和 Gear bridge call；只清理 UI 展示是不够的。
- 已聚焦的 runtime stage 可以携带从用户请求或前序结构化结果中提取出的确定性 `capability_args`。当模型遗漏参数时，Tool Boundary Gateway 可以把这些参数合并进匹配的同阶段 Gear invocation；如果参数值冲突，则返回结构化参数错误，而不是静默覆盖。
- 对命中 Gear 的请求，bridge 是优先执行路径。除非用户明确要求调试 GeeAgent 本身，否则 agent 不应检查 GeeAgent 源码、调用 SDK `Skill` alias，或用 Bash 探测产品内部实现。

Gear 执行结果是结构化数据，不是最终文案。Gear capability、native adapter 或过渡期 router 可以返回状态变化、数量、artifacts、warnings 和 errors，但不能硬编码最终展示给用户的完成句子。一次 turn 内所有 Gear actions 执行完成后，GeeAgent 必须把这些结构化结果交回当前 active agent/LLM，由 agent 根据结果和用户语言生成最终回复。如果 LLM continuation 无法运行，GeeAgent 应展示明确的 pending 或 failure 状态，而不是伪造一条硬编码成功文案。

Native host 完成 Gear action 后，可以把简短 summary 和有边界的 `result_json` payload 一起交回 continuation turn。summary 用于快速展示；`result_json` 才是 task id、路径、数量、artifacts、抓取记录和结构化错误的事实来源。大型结果必须保存到 gear data 目录中，并通过路径引用，不能把全部内容直接灌进 agent context。

在 continuation 阶段，GeeAgent 可以把大型 `result_json` 替换为 `result_artifact` 引用。模型侧 payload 会保留 id、status、summary、error、artifact path、hash、byte count 和 token estimate，而完整 JSON 会写入磁盘，供明确需要时再检查。

复杂 Gear 工作必须由 agent 规划，而不是由本地 router 规划。本地 Gear capability 应拆解成小的工具元件，例如保存书签、抓取推文、嗅探媒体、下载媒体、导入文件、附加本地路径。active agent 应先提出计划，调用一个元件，检查结构化结果，再决定下一步。Local router 和 `host_action_intents` 不能预先写死“抓推文、发现媒体、下载视频、导入媒体库、更新书签”这种完整多步 workflow，否则会失去根据中间结果实时纠错的能力。

当 runtime plan 已经锁定阶段焦点时，capability discovery 必须按阶段收窄。GeeAgent 应先请求当前阶段的 focused summary，只有在拿到所需结构化结果之后，才进入后续阶段的 focus set。

阶段推进必须依赖包含已完成 Gear 和 capability 标识的结构化 `result_json` 证据。面向人看的 summary 可以帮助 UI 展示，但不足以把阶段标记为完成。

Gear invocation 也必须按阶段收窄。当 focused runtime stage 处于活动状态时，GeeAgent 会拒绝调用不在该阶段 `required_capabilities` 内的 Gear capability，直到阶段推进或被明确重新规划。

确定性阶段参数属于 runtime plan，而不是 fallback route。它们只能补齐当前阶段声明的 capability invocation，并且会通过规范化后的 tool input 和结构化结果保持可见。

仍然必须使用渐进式披露，但 summary 现在是可调用索引，而不是每次 schema 调用前的固定前奏。agent 应先请求 `detail: "summary"`；如果紧凑记录已经包含所需 capability 且必填参数明确，可以直接调用。只有当可选参数类型或语义不清楚时，才继续请求 `detail: "capabilities"` 或 `detail: "schema"`。GeeAgent 不应默认把所有 Gear capability schema 一次性灌进模型上下文。

当前 host 调用形态：

```json
{
  "tool": "gee.gear.invoke",
  "gear_id": "media.library",
  "capability_id": "media.filter",
  "args": {
    "kind": "video",
    "starred_only": true
  }
}
```

当前 SDK MCP tool 调用形态：

```json
{
  "tool": "mcp__gee__gear_invoke",
  "gear_id": "media.library",
  "capability_id": "media.filter",
  "args": {
    "kind": "video"
  }
}
```

### Codex Plugin Projection

目标是：GeeAgent 里可用的 capability，在安全且被明确导出的情况下，也可以从 Codex 使用。实现模型是生成一个 GeeAgent Codex plugin，让 Codex 通过本地 Gee MCP export server 调用 Gee 能力。

这不是把 Gear 改造成 Codex plugin。Gear 仍然是权威 package、native app/widget、数据、权限、依赖和执行边界。Codex plugin 只是一个可安装导出投影，包含 plugin metadata、MCP configuration，以及指导 Codex 如何调用 Gee bridge 的 skills。

核心导出标准位于 `docs/planning/gee-capability-export-standard-v0.md`。

当前实现状态：agent runtime 已经有基于 manifest 的 export status/list/describe 命令、面向 Codex 的 MCP stdio server、shared-store external invocation queue、本地 `geeagent-codex` plugin generator，以及 home-local install command。生成的 `gee-capabilities` skill 是 Codex 的第一入口：它说明 GeeAgent plugin 是什么，指向生成的 capability index 和每个 Gear 的 reference 文件，并要求在调用前用 live MCP 完成 discovery / describe。install command 默认写入 `~/plugins/geeagent-codex` 并刷新 `~/.agents/plugins/marketplace.json`。`gee_status`、`gee_list_capabilities` 和 `gee_describe_capability` 由 manifest projection 提供。`gee_invoke_capability` 和 `gee_open_surface` 会创建 external invocation，由 GeeAgentMac 通过 live GearHost bridge 执行；`gee_get_invocation` 返回已记录的 status/result。`media.generator/media_generator.create_task` 已导出给明确用户请求的图片生成，包括 `batch_count` 1-4 fan-out，并通过同一队列返回 task 或 batch status/artifact references。`telegram.bridge/telegram_push.send_message` 已导出给已配置的 push-only Telegram 信道，并返回真实 Telegram delivery metadata 或结构化 failed/degraded 状态。如果 GeeAgentMac 没有运行或无法清空队列，Codex 会收到带 `fallback_attempted: false` 的 pending/failed/blocked/degraded 结构化结果；stale `running` invocation 会降级并返回手动重试指引，不会自动重试。MCP server 不会执行 Gear 业务逻辑，也不会运行 fallback scripts。

目标 Codex-facing package 结构：

```text
geeagent-codex/
├── .codex-plugin/
│   └── plugin.json
├── .mcp.json
├── skills/
│   └── gee-capabilities/
│       ├── SKILL.md
│       └── references/
│           ├── capability-index.md
│           └── <gear-id>.md
└── assets/
```

目标 Gee MCP export tools：

- `gee_status`
- `gee_list_capabilities`
- `gee_describe_capability`
- `gee_invoke_capability`
- `gee_open_surface`
- `gee_get_invocation`

生成的 plugin package 包含 `.codex-plugin/plugin.json`、`.mcp.json`、`skills/gee-capabilities/SKILL.md`、`references/capability-index.md` 和每个 Gear 的生成 reference 文件。references 是离线方向性快照；`.mcp.json` 会让 Codex 调用 `native-runtime codex-mcp`；已安装 Gear 的可用性仍然来自 MCP server 的实时数据，而不是静态 plugin metadata。

只有 ready、enabled、policy-allowed、export-eligible 的 Gear capabilities 对 Codex 可见。disabled、failed、installing、invalid、blocked 或明确未导出的 Gear 对 Codex 不可见。Export bridge 不能为每个 Gear feature 创建一个 Codex tool，不能复制 Gear 业务逻辑，不能保存 provider secrets，也不能调用 package-local fallback scripts。

Codex 发起的调用是 external invocation。它们会记录 caller metadata、normalized input、structured results、artifact references，以及 failure 或 recovery reasons。它们不会变成隐藏的 GeeAgent chat turn。如果 GeeAgent、GearHost、目标 Gear、provider channel、permission 或 live bridge 不可用，Codex 会收到带真实原因的 structured pending、failed、blocked 或 degraded result。

Gear capabilities 可以在 `gear.json` 的 `agent.capabilities[].exports.codex` 下声明 Codex export policy。如果某个 capability 在 GeeAgent native surface 之外不安全或没有意义，应明确把 Codex export 标成 disabled，并写明原因。

当 Gear、capability、result shape、artifact、permission、provider requirement、dependency behavior 或 failure code 发生变化时，维护者必须检查 Codex plugin projection、Gee MCP export schema、生成的 skills 和 plugin metadata 是否也需要更新。如果一次实质性 Gear 改动不影响 Codex export，最终工作总结应明确说明。

当前没有公开的文本 fallback directive 用于 Gear 执行。历史 directive
形态记录可以为了迁移安全被规范化，但新的 agent turn 必须使用 MCP
Gear bridge。缺少 bridge tools、参数非法或存在过期 pending host actions
时，都必须以结构化原因失败，不能重放副作用，也不能把部分工作说成完成。

规则：

- 只有 `ready + policy-allowed` gears 暴露 capabilities。
- `policy-blocked`、`invalid`、`installing`、`install_failed`、`blocked` gears 不对 agent 可见。
- capabilities 在 `gear.json` 中声明。
- Gear adapter 负责校验 `capability_id` 和 `args`。
- Gear adapter 返回结构化结果。执行后的最终自然语言回复由当前 active agent/LLM 负责。
- 不为每个 gear 功能增加一个全局 pseudo-tool。
- root agent 只能通过统一 bridge 进入 gear surface。
- 第一方 Gear 业务逻辑留在 Gear adapter 边界内，不进入 generic runtime glue。

Capability 示例：

```json
{
  "agent": {
    "enabled": true,
    "capabilities": [
      {
        "id": "media.filter",
        "title": "Filter media",
        "description": "Change visible media by folder, type, star state, duration, or search text.",
        "input_schema": {
          "type": "object",
          "properties": {
            "folder_name": { "type": "string" },
            "kind": { "type": "string", "enum": ["all", "image", "video"] },
            "extensions": { "type": "array", "items": { "type": "string" } },
            "starred_only": { "type": "boolean" },
            "minimum_duration_seconds": { "type": "number" },
            "search_text": { "type": "string" }
          }
        },
        "examples": [
          "只展示视频",
          "只展示标星图片",
          "只展示时长大于 3 分钟的 mp4 文件"
        ]
      }
    ]
  }
}
```

## First-Party Gear Migration

第一方 gears 应逐步迁移到真实 package boundary。

`media.library`：

- 目标是完整独立的 Eagle-compatible local media manager。
- package 内包含 manifest、README、assets、setup metadata、storage notes 和未来 capability declarations。
- Native Swift 实现可以在迁移期继续 host-compiled，但业务边界必须从主 app 里抽离。
- 文件夹、筛选、星标、Quick Look、Finder、视频 / gif hover playback、动态展示等行为属于 media gear，不属于主 workbench。
- Agent capabilities 包括 `media.filter`、`media.focus_folder` 和 `media.import_files`。当当前用户明确要求导入本地文件时，`media.import_files` 可由 GeeAgent root-agent 对话和 Codex 对话触发。它会把本地媒体路径导入已授权的媒体库，能在可能时恢复已保存的访问授权，并为多 Gear 工作流返回 item proof。新导入文件会出现在 `imported_items`；重复文件会作为幂等成功返回 `action: "import_noop"`、`existing_items` 和 `duplicate_paths`；源文件不存在时通过 `missing_paths` 报告；不支持的文件通过 `unsupported_paths` 报告。如果没有任何可用的已导入或已存在媒体条目，它会返回带 `code: "gear.media.no_supported_files"` 的结构化失败，而不是用 `imported_count: 0` 伪装成功。如果授权缺失，它会把可读路径保留为 `pending_paths`，打开 Media Library 界面，并返回结构化失败交给 active agent/LLM 解释。

`hyperframes.studio`：

- 目标是创作型 gear，依赖 Node、npm、Hyperframes、FFmpeg 和 FFprobe。
- 必须使用 dependency preflight 和 setup snapshot。
- 依赖失败只影响 Hyperframes gear。
- 业务逻辑和项目数据不能进入主 app store。

`media.generator`：

- 目标是从 Dailystarter 生成器模块改造来的 native media generation Gear。
- Gear 优先支持图片生成，走全局 Xenodia 渠道。当前启用模型是 `nano-banana-pro` 和 `gpt-image-2`；`image-2` 会作为 `gpt-image-2` 的用户侧别名被接受。
- Nano Banana Pro 暴露 `n=1`、`async`、`response_format=url`、`aspect_ratio`、`resolution`、`output_format` 和参考图。GPT Image-2 暴露 `n=1`、`async`、`response_format=url`、`aspect_ratio`、`resolution` 和参考图；不要为 GPT Image-2 发送 `output_format` 或 `nsfw_checker`。
- 多张生图使用 Gear 级 `batch_count`，范围 1 到 4。Gee 会为每张图创建一个持久化的 Xenodia `n=1` 子任务，用同一个 `batch_id` 聚合，并在原生任务列表中用一条 batch row 和结果网格展示。
- 参考图数量按模型限制：Nano Banana Pro 最多 8 个，GPT Image-2 最多 16 个。Local reference 必须是 JPEG、PNG 或 WebP，并且单个文件不超过 30MB。
- 视频和音频生成目前作为产品界面与 capability 占位存在，但 V1 不能接入参考项目里的非 Xenodia 供应商。在 Xenodia-backed endpoint 经全局 provider 渠道提供前，它们应返回结构化 unsupported-category 结果。
- 参考图上传不能使用参考项目里的七牛。Local reference 应走 Xenodia request，或后续由主 app runtime 管理的全局 Xenodia storage upload endpoint。
- Task state 写入 `~/Library/Application Support/GeeAgent/gear-data/media.generator/tasks/<task-id>/task.json`。Batch row 是多个子任务记录上的投影，不替代 task 存储路径。当前 batch task record 使用 schema version 2；这次 schema 切换可以清空旧 task history。
- 生成结果应尽可能缓存到 `~/Library/Application Support/GeeAgent/gear-data/media.generator/tasks/<task-id>/outputs/`。预览和下载优先使用 Gear-owned 本地 artifact，同时保留远端 URL 作为降级 fallback。
- 可复用 Quick Prompts 写入 `~/Library/Application Support/GeeAgent/gear-data/media.generator/quick-prompts.json`；用户可以在原生 Gear UI 中新增、编辑、删除和重置。
- 来自粘贴 URL 和本地文件的最近参考图写入 `~/Library/Application Support/GeeAgent/gear-data/media.generator/image-history.json`。History sheet 复用这些参考图，不再打开文件选择器；生成结果保留在 task record 和 output cache 中，不再自动进入参考图 history。
- Async task polling 必须在 Gear 打开或重新加载历史时恢复 `running` / `queued` 任务。轮询应把 Xenodia `success` 视为完成、`fail` 视为失败，并从 normalized `result` payload 读取生成 URL。
- Xenodia 图片生成是长任务：create、multipart 和 task-status 请求必须使用至少 30 分钟的 timeout 下限。status 请求超时时，本地 task 应保持 `running` 并继续轮询，不能在供应商仍在生成时标记为 failed。
- 原生 Generate 按钮必须在 task row 本地入队后继续可用于新 prompt。Provider 创建、结果缓存和轮询都作为后台 task state 继续，不能长期占用创建控件。
- 原生任务工作台支持状态筛选、模型筛选、搜索、收藏结果、本地缓存标记、Finder 定位、大图预览、复制 URL、用户选择位置下载、按任务 Apply 回填 prompt/model/parameters/references、单独复用为参考图，以及带确认的任务历史删除。
- Agent capabilities 是 `media_generator.list_models`、`media_generator.create_task` 和 `media_generator.get_task`。`media_generator.create_task` 可以由 GeeAgent root-agent 对话和 Codex 对话触发；多图请求用 `batch_count` 1-4，同时 provider `n` 保持 1；每个 capability 都返回结构化 task 或 batch/model 数据，由 active agent/LLM 生成最终回复。

`smartyt.media`：

- 目标是从 SmartYT 参考项目改造来的 native URL media acquisition gear。
- Gear 接收 URL，嗅探媒体 metadata，下载音频、视频或直链图片 artifact，并提取 transcript text。
- V1 使用 `yt-dlp` 处理 metadata、下载和字幕提取，使用 `ffmpeg` / `ffprobe` 支撑媒体转换。
- 转文本应优先走平台字幕快通道。如果没有字幕，Gear 可以在本地安装了 Whisper 等语音工具时降级到本地 speech tooling。如果没有可用 speech backend，Gear 必须返回结构化失败并说明缺少转写后端，不能假装转换已经完成。
- Job state 应写入 `~/Library/Application Support/GeeAgent/gear-data/smartyt.media/`；下载媒体、提取字幕和 transcript text 在 agent call 未提供 `output_dir` 时默认写入 `~/Downloads/SmartYT/<job-id>/`。
- Agent capabilities 是 `smartyt.sniff`、`smartyt.download`、`smartyt.download_now`、`smartyt.transcribe`。`smartyt.download` 面向 UI 排队执行，`smartyt.download_now` 会等到 artifact 真正生成后返回 `output_paths`，供多 Gear 工作流使用。直链图片 URL，包括带图片扩展名或 `format=` query hint 的 Twitter/X 图片 URL，会按图片下载处理，而不是误走视频下载。最终给用户看的自然语言回复由 active agent/LLM 生成。

`twitter.capture`：

- 目标是从 Workbench 参考项目的 Twikit 抓取流程改造来的 native Twitter/X content capture gear。
- Gear 接收单条推文 URL、List URL 加数量限制、或 username / profile URL 加数量限制。
- V1 使用 package-local Python sidecar，位置是 `apps/macos-app/Gears/twitter.capture/scripts/`，依赖 `twikit`。sidecar 需要用户提供已登录 Twitter/X session 的 cookie JSON 文件；GeeAgent 不内置任何账号凭证。
- Task state 和抓取结果写入 `~/Library/Application Support/GeeAgent/gear-data/twitter.capture/tasks/<task-id>/task.json`。
- 原生 UI 可以从这个 Gear-owned task database 中清理全部 Twitter Capture task records。
- 抓取到的 tweet record 包含 id、URL、作者 handle、正文、语言、互动数量、推文时间、reply / retweet 标记，以及可用时的标准化 media metadata。
- 原生 task surface 展示任务创建时间，并格式化为本地时间；结果主卡片不展示推文发布时间。
- Agent capabilities 是 `twitter.fetch_tweet`、`twitter.fetch_list`、`twitter.fetch_user`。每个 capability 都创建 Gear task，把结果保存到文件数据库，并返回结构化 task / result 数据给 active agent/LLM 生成最终回复。
- 缺少 cookies、session 过期、rate limit 或 Twikit 错误必须以结构化 task failure 返回；Gear 不能伪造抓取成功。

`bookmark.vault`：

- 目标是 universal information capture Gear。
- Gear 保存任意 raw content。如果内容包含 URL，会按 Twitter/X 嵌入元数据、`yt-dlp` 媒体元数据、基础网页 fetch 的顺序尝试补充 metadata。
- Bookmark record 写入 `~/Library/Application Support/GeeAgent/gear-data/bookmark.vault/bookmarks/<bookmark-id>/bookmark.json`。
- Agent capability `bookmark.save` 接收 `content` 和可选 `local_media_paths`。多 Gear 工作流在下载并导入媒体后，应把 Media Library 导入后的 item path 写入 `local_media_paths`。

`wespy.reader`：

- 目标是由外部 WeSpy Python package 驱动的 native article reader Gear。
- Gear 接收单篇文章 URL、用于列出文章的微信公众号专辑 URL，或用于批量 Markdown 抓取的微信公众号专辑 URL。
- V1 使用 package-local Python sidecar，位置是 `apps/macos-app/Gears/wespy.reader/scripts/`，并导入用户已安装的 `wespy` package。GeeAgent 不把 WeSpy 源码 vendor 到主 runtime 中。
- Task state 和生成文件路径写入 `~/Library/Application Support/GeeAgent/gear-data/wespy.reader/tasks/<task-id>/task.json`。
- Agent capabilities 是 `wespy.fetch_article`、`wespy.list_album`、`wespy.fetch_album`。每个 capability 都返回结构化 task 数据、文章数量、生成文件路径、文章 metadata 和结构化错误，最终回复由 active agent/LLM 生成。
- 缺少 Python package、网站结构变化、来源页面阻止访问或网络失败必须以结构化 task failure 返回；Gear 不能伪造抓取成功。

`app.icon.forge`：

- 目标是原生 macOS app 图标制作 Gear。
- Gear 接收一张用户选择的本地图，把它居中裁成正方形，在透明 1024px 画布上按圆角安全区渲染，然后导出完整图标 package。
- 生成 artifact 包括 `<name>.icns`、`<name>.iconset`、`<name>.appiconset`、`preview-1024.png` 和 `icon-export.json`。
- Agent capability `app_icon.generate` 接收 `source_path`，以及可选的 `output_dir`、`name`、`content_scale`、`corner_radius_ratio` 和 `shadow`，并返回结构化 artifact 路径与生成规格。
- 该 capability 可通过 GearHost bridge 被 GeeAgent root-agent 对话和 Codex 对话调用。Codex 调用方只能传入用户明确提供的本地路径，并应原样报告 GearHost 返回的 artifact 路径，不能运行 package-local 图片脚本。

信息采集工作流：

- 纯文本直接调用 `bookmark.save`。
- URL metadata capture 先调用 `bookmark.save`；只有当用户要求更深入的 Twitter/media 内容，或 URL 明确指向强媒体内容时，才使用 `twitter.capture` 或 `smartyt.media`。
- 当用户要求 Markdown、文章提取或批量专辑抓取时，微信公众号文章或专辑 URL 应使用 `wespy.reader`；只有用户明确要保存 URL 本身为书签时才使用 `bookmark.save`。
- Twitter/X status URL 默认需要采集媒体，除非用户明确只想保存 metadata 或明确不要下载媒体。需要推文/媒体细节时先用 `twitter.fetch_tweet`，再对每个可下载的视频或图片 URL 调用 `smartyt.download_now`。
- YouTube URL 在默认下载决策前应使用 `smartyt.sniff` 作为轻量时长探测。只有 `duration_seconds` 小于 300 秒时才默认下载；超过 300 秒或时长未知时默认只保存 metadata，除非用户明确要求下载。
- 强媒体采集应对每个 media URL 调用 `smartyt.download_now`，再调用 `media.import_files`，最后调用带 `local_media_paths` 的 `bookmark.save`。
- 如果当前没有已授权媒体库，`media.import_files` 应把下载路径保留为 `pending_paths`，打开 Media Library 界面，并提示用户选择或创建媒体库后再声称导入成功。Bookmark Vault 仍可保存下载路径，以便授权后继续工作流。
- 依赖 `media.import_files` 的 runtime stage 必须要求 `available_count > 0`，或 `imported_items` / `existing_items` 非空，才能声称媒体导入完成。只有 successful invocation 和 `imported_count: 0` 不足以作为完成证明。

`btc.price`：

- 目标是 Home widget。
- 需要轻量、可拖拽、可刷新。
- 网络访问必须声明。
- Widget 不应包含完整 app navigation。

`system.monitor`：

- 目标是 Home widget。
- 显示本地 CPU / memory 等信息。
- 必须保持轻量，避免长期高频采样影响主 app。

## Suggested Directory Upgrade

目标目录：

```text
apps/macos-app/
├── Gears/
│   ├── media.library/
│   ├── hyperframes.studio/
│   ├── smartyt.media/
│   ├── twitter.capture/
│   ├── bookmark.vault/
│   ├── wespy.reader/
│   ├── app.icon.forge/
│   ├── btc.price/
│   └── system.monitor/
└── Sources/
    ├── GearKit/
    ├── GearHost/
    └── GeeAgentMac/
```

迁移原则：

- 先建立 `GearKit` 和 `GearHost` 文件夹边界。
- 初期可以保持一个 SwiftPM target，先让文件结构和 import boundary 清晰。
- 后续再把 `GearKit` / `GearHost` 拆成 SwiftPM target。
- bundled gear packages 移出 `Sources/GeeAgentMac/gears`，迁到 `apps/macos-app/Gears`。
- 主 app 只通过 GearHost 获取 catalog、window 和 widget。

## Implementation Phases

## Phase 0: Boundary Freeze

目标：阻止新的 gear 业务继续进入主 app。

交付：

- 记录当前 gear 入口。
- 标记 legacy host-compiled adapters。
- 禁止在 `WorkbenchStore` 增加 gear business state。
- 禁止新增 gear-specific pseudo-tools。

验收：

- 新功能必须落在 gear package、GearHost 或 GearKit 边界中。
- 主 app 只调用通用 gear API。

## Phase 1: Extract GearKit And GearHost

目标：让模块边界在文件结构上真实存在。

交付：

- 创建 `Sources/GearKit`。
- 创建 `Sources/GearHost`。
- 移动 manifest、dependency、preparation、registry 类型。
- 保留当前行为不变。
- 添加 public API：scan、list、prepare、open、widget records、capability records；策略禁用 API 作为内部保护能力保留，不作为 V1 catalog 操作。

验收：

- `swift build` 通过。
- Gears catalog 行为不变。
- 删除无关 gear 不影响 app startup。
- invalid `gear.json` 仍显示为 install issue。

## Phase 2: Move Bundled Gear Packages

目标：让开发期 gear packages 在结构上独立。

交付：

- 创建 `apps/macos-app/Gears`。
- 移动 `media.library`、`hyperframes.studio`、`btc.price`、`system.monitor` package skeletons。
- 更新 SwiftPM resource copy。
- registry 支持新的 bundled root。
- 迁移期间兼容旧 root。

验收：

- bundled gears 仍出现在 catalog。
- 删除某个 package 后，该 gear 不出现或显示明确 install issue。
- 用户 Application Support 中的同 ID package 合并逻辑明确。

## Phase 3: Migrate First-Party Native Gear Boundaries

目标：让第一方 native gears 的业务边界清楚。

交付：

- `media.library` adapter 注册到 GearHost。
- `hyperframes.studio` adapter 注册到 GearHost。
- Home widgets 通过 widget adapter 注册。
- README 写清哪些部分仍是 host-compiled migration。
- Gear-specific state 从 generic store 移出。

验收：

- 主 app 不直接打开 MediaLibrary window。
- 主 app 不直接知道 Hyperframes dependency recipe。
- GearHost 负责 prepare 和 open。

## Phase 4: Import Local Gear

目标：支持 AA-style 本地分享。

交付：

- Gears catalog 增加 `Import Gear...`。
- 支持 folder import。
- 支持 `.geegear.zip` import。
- manifest validation。
- atomic copy into Application Support。
- same ID conflict handling。
- invalid package issue UI。

验收：

- 有效 folder import 后出现在 catalog。
- 有效 zip import 后出现在 catalog。
- 无效 package 不崩溃并显示 issue。
- duplicate ID 提供 replace / update / cancel。

## Phase 5: Dependency Setup UX

目标：让 dependency service 可信、可见、可恢复。

交付：

- Setup details sheet。
- Global environment mutation warning。
- Live setup logs。
- Retry install。
- Unsupported installer 的 manual setup message。
- Per-gear setup snapshot persistence。

验收：

- 打开缺依赖 gear 时按钮变成 `Checking...`，随后变成 `Installing...` 或 `Retry`。
- policy-blocked gear 不运行 setup。
- failed setup 只影响当前 gear。
- logs 保存到 `gear-data/<gear-id>/logs/`。

## Phase 6: External Process And WebView Entry

目标：让第三方 gears 在不动态加载 Swift 的情况下可用。

交付：

- `external_process` adapter。
- `webview` adapter for local files。
- process lifecycle supervision。
- timeout and stop behavior。
- stdout / stderr logs。
- startup health protocol。

验收：

- 一个 sample AA gear 可以被复制 / 导入并打开。
- process exit 会显示为 gear launch failure。
- V1 WebView gear 只加载 package 内本地文件。

## Phase 7: Agent Control Bridge

目标：通过单一 bridge 暴露 ready gear capabilities。

交付：

- GearHost 提供 ready / policy-allowed capability list。
- `gear.invoke` adapter surface，以及 SDK `gee` MCP bridge tools。
- `media.library` 初始 capability execution。
- SDK runtime 与 GeeAgentMac host actions 之间的 same-run pause / execute / resume continuation。

验收：

- Agent 只能看到 ready + policy-allowed capabilities。
- policy-blocked / failed / installing / invalid gears 对 agent 不可见。
- 不增加 gear-specific pseudo-tools。
- 缺少 MCP bridge tools 或 Gear 参数非法时必须明确失败；GeeAgent 不使用 fallback task execution 掩盖 runtime 问题。

## Quality Gates

每个 phase 完成前必须满足：

- `swift build` 在 `apps/macos-app` 通过。
- Gears catalog 仍能打开。
- 缺失 gear 不破坏主 app startup。
- 无效 `gear.json` 显示为 install issue。
- policy-blocked gear 不运行依赖安装。
- policy-blocked gear 不暴露 capabilities。
- Gear-specific data 不进入 `WorkbenchStore`。
- Gear UI 遵守 macOS native experience。
- public docs 同步更新英文、简体中文、日文。
- Gear capability 变化必须检查 Codex plugin projection，并在需要时同步更新 export metadata、MCP schema、生成的 skills 或 plugin metadata。

Package / import phase 还必须满足：

- path traversal 被拒绝。
- folder name 必须匹配 manifest id。
- duplicate ID 有明确用户选择。
- import 要么原子成功，要么干净回滚。
- dependency failure 有 per-gear logs。

## Non-Goals For V1

V1 不做：

- Remote marketplace。
- Payments、ratings、reviews。
- Mandatory developer signing。
- Automatic remote update。
- Cross-gear private API。
- Background daemons。
- Dynamic Swift source loading from user-copied folders。
- One agent tool per gear feature。
- 在 app startup 静默安装依赖。

## Developer Workflow

开发一个本地 gear 的推荐流程：

- 创建 `<gear-id>/` 文件夹。
- 添加 `gear.json`。
- 添加 `README.md`。
- 添加 `assets/`、`setup/`、`scripts/`、`src/` 或 `app/`。
- 声明 entry、permissions、dependencies 和 agent capabilities。
- 在开发期放入 `apps/macos-app/Gears/<gear-id>/`。
- 在实际分发时打包成 folder 或 `.geegear.zip`。
- 用户复制到 `~/Library/Application Support/GeeAgent/gears/<gear-id>/` 或通过 `Import Gear...` 导入。
- GearHost scan 后出现在 Gears catalog。
- 用户启用或打开时执行 dependency preflight。
- ready 后打开 app window 或渲染 Home widget。

最小可分享 package：

```text
aa.cool.gear/
├── gear.json
├── README.md
├── assets/
│   └── icon.png
├── scripts/
│   └── start.sh
└── app/
    └── index.html
```

最小 `.geegear.zip` 应该解压出单一 top-level folder：

```text
aa.cool.gear.geegear.zip
└── aa.cool.gear/
    ├── gear.json
    └── README.md
```

## Immediate Recommendation

下一步应从 Phase 1 和 Phase 2 开始。

不要先做 marketplace、signing、remote update 或完整 agent bridge。最有价值的下一步是让本地模块边界变成真实结构：

- 抽出 `GearKit` 和 `GearHost` 目录。
- 把 bundled gear packages 移到 `apps/macos-app/Gears`。
- 在 GearHost 中集中 native / widget adapter registration。
- 保持当前用户行为不变，同时让 package boundary 明确。

这样 GeeAgent 可以在不过度设计生态的前提下，先获得可信的平台基础：gear 独立、可选、可管理、可复制安装，并且未来可以自然接入 agent 控制协议。
