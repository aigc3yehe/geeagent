# Gear 开发

## 状态与日期

文档日期：2026-04-26。

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
├── btc.price/
└── system.monitor/
```

当前第一方 native gear 的主要实现仍然由 host 编译：

```text
apps/macos-app/Sources/GeeAgentMac/Modules/MediaLibrary/
apps/macos-app/Sources/GeeAgentMac/Modules/HyperframesStudio/
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
- 已经有第一版 V1 host bridge surface：`gee.app.openSurface`、渐进式 Gear capability disclosure 和统一 Gear invocation。
- 在完整 SDK/MCP tool exposure 完成前，过渡期的 `host_action_intents` 可以让第一方 runtime turn 把 native Gear actions 交回 GeeAgentMac 顺序执行。
- `btc.price` 和 `system.monitor` 已经作为 Home widgets 的方向存在。

当前主要缺口：

- 第一方 gear 的业务逻辑仍在主 app source tree 中。
- Gear package 文件夹还不是完整实现边界。
- 第三方 gear import 还没有落地。
- 面向所有 Gear capabilities 的完整 agent-runtime SDK/MCP tool injection 还没有完成。
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

## Agent Control Bridge

Gear 不定义完整 agent protocol。agent runtime 负责控制协议、权限语义、run events、approval flow 和 continuation semantics。

当前 V1 已经实现第一版 native Gee host bridge surface：

- `gee.app.openSurface` 按 id 打开 Gee surface 或 Gear window，例如 `media.library`。
- `gee.gear.listCapabilities` 用渐进式披露方式暴露已启用 Gear capabilities。
- `gee.gear.invoke` 通过统一 host bridge 调用一个已声明的 Gear capability。
- `host_action_intents` 允许一次 runtime turn 返回 native actions，由 GeeAgentMac 按顺序执行。这是完整 SDK/MCP tool exposure 普及到每次模型回合前的当前过渡路径，例如用户要求媒体库只展示视频文件。
- 过渡期内，第一方媒体库的直接请求可以把视频、图片、PNG 等扩展名过滤路由到 `media.filter`，而不是进入编码循环。
- 通过 `media.filter` 设置的媒体库筛选会作为 active filters 体现在原生 UI 中。用户可以通过 `All` 或 `Clear filters` 回到完整媒体视图。

Gear 执行结果是结构化数据，不是最终文案。Gear capability、native adapter 或过渡期 router 可以返回状态变化、数量、artifacts、warnings 和 errors，但不能硬编码最终展示给用户的完成句子。一次 turn 内所有 Gear actions 执行完成后，GeeAgent 必须把这些结构化结果交回当前 active agent/LLM，由 agent 根据结果和用户语言生成最终回复。如果 LLM continuation 无法运行，GeeAgent 应展示明确的 pending 或 failure 状态，而不是伪造一条硬编码成功文案。

必须使用渐进式披露。agent 应先请求 `detail: "summary"`，再针对一个 `gear_id` 请求 `detail: "capabilities"`，最后针对一个 `capability_id` 请求 `detail: "schema"`，再执行调用。GeeAgent 不应默认把所有 Gear capability schema 一次性灌进模型上下文。

当前调用形态：

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

`hyperframes.studio`：

- 目标是创作型 gear，依赖 Node、npm、Hyperframes、FFmpeg 和 FFprobe。
- 必须使用 dependency preflight 和 setup snapshot。
- 依赖失败只影响 Hyperframes gear。
- 业务逻辑和项目数据不能进入主 app store。

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
- `gear.invoke` adapter surface。
- `media.library` 初始 capability execution。
- 接入 agent runtime 前由 phase-2 runtime council review。

验收：

- Agent 只能看到 ready + policy-allowed capabilities。
- policy-blocked / failed / installing / invalid gears 对 agent 不可见。
- 不增加 gear-specific pseudo-tools。

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
