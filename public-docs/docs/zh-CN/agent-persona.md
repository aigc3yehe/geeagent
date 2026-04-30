# Agent Persona

## 目的

GeeAgent 不只是一个通用 agent runtime。它在共享运行时之上提供 agent persona 产品层。persona 定义 agent 的身份、行为方式、视觉呈现，以及它可以建议或约束的本地能力。

persona 层必须和运行时执行真相分开。run、session、event、approval、task continuation、tool execution 属于 phase-2 runtime spine。

## 当前状态

当前 persona 系统是基础能力，不是完整的 persona 市场。

- persona definition 可以从本地文件夹或 zip 归档导入。
- 导入后的 persona 会复制到本地 persona workspace。
- active persona 会暴露在 runtime snapshot 中。
- active persona 会影响 SDK system prompt。
- 显式添加的 skill source metadata 可以暴露给 prompt，但不会注入完整 `SKILL.md` 正文。
- persona tool allow-list 会由 native runtime tool dispatcher 强制执行。
- 如果存在视觉资产，persona visual layer 会驱动原生 Home surface。

## Agent Definition v2

当前主要公开格式是 `Agent Definition v2`。

必需包结构：

```text
agent.json
identity-prompt.md
soul.md
playbook.md
appearance/
```

可选文件：

```text
tools.md
memory.md
heartbeat.md
skills/
README.md
LICENSE
```

视觉资源可以缺省。persona 可以完全省略 visual layer，并回退到默认 abstract surface。

## Manifest 字段

`agent.json` 是小型声明式 manifest。它应该引用文件，而不是直接承载长 prompt 文本。

必填字段：

- `definition_version`：必须为 `2`。
- `id`：稳定 persona id。
- `name`：展示名。
- `tagline`：短摘要。
- `identity_prompt_path`：身份层文件路径。
- `soul_path`：声音和人格层文件路径。
- `playbook_path`：行为层文件路径。
- `appearance`：可选视觉定义。
- `source`：通常为 `module_pack` 或 `user_created`。
- `version`：可读版本号。

常见可选字段：

- `tools_context_path`
- `memory_seed_path`
- `heartbeat_path`
- `skills`
- `allowed_tool_ids`

## 分层上下文

GeeAgent 按以下顺序编译 persona context：

- `identity-prompt.md`：角色、职责、任务边界。
- `soul.md`：人格、语气、沟通姿态。
- `playbook.md`：工作规则、自主性姿态、升级和审批行为。
- `tools.md`：本地工具使用提示，如果已声明。
- `memory.md`：初始可移植 memory seed，如果已声明。
- `heartbeat.md`：周期性行为指导，如果已声明。

编译结果会成为 persona 的 runtime `personality_prompt`。

## Skill Sources

GeeAgent 只识别用户显式添加的 skill 文件夹。它不会自动扫描本机所有 agent skill 目录。

Settings 可以添加系统级 skill source 文件夹。系统级 source 对所有 persona 生效，并会在 runtime 构建新 snapshot 或 prompt 时热更新。

Agents 详情页可以添加 persona 级 skill source 文件夹。persona 级 source 只对该 persona 生效。persona 级 skill 列表会在 persona Reload 时刷新。

skill source 可以是一个包含 `SKILL.md` 的单个 skill 文件夹，也可以是一个 collection 文件夹，其直接子文件夹包含 `SKILL.md`。

runtime 只会把 skill metadata 暴露给 active agent prompt，例如 name、description、scope 和 file path。完整 `SKILL.md` 内容不会自动注入。如果 agent 需要完整指令，必须通过正常 runtime file/tool 路径和权限模型检查该 skill 文件。GeeAgent 的 skill metadata 不是 SDK `Skill` 工具注册；当存在 `skill_file_path` 时，agent 应直接读取该文件，而不是调用 SDK skill alias。

skill availability 是上下文，不是安全沙箱。tool execution 仍然由 GeeAgent runtime permissions、approval flow 和 persona `allowed_tool_ids` 控制。

## 视觉层

支持的 persona visual kind：

- `live2d`：引用 Cubism `*.model3.json` bundle descriptor。
- `video`：引用本地循环视频。
- `static_image` 或 `image`：引用图片资源。

visual layer 可以同时声明三种资源。GeeAgent 按以下优先级应用：

- Live2D；
- video；
- image。

如果所有 persona visual 字段都缺省，应用会使用默认 abstract surface。

在 Home surface 上，GeeAgent 可以为 active persona 暴露一个紧凑的视觉切换器。它只显示存在对应文件的视觉模式，外加 abstract 模式。例如某个 persona 有 Live2D 和图片资源但没有视频资源时，视频选项会隐藏。

选择 abstract 模式会隐藏 persona visual；如果配置了 global background，则只保留这个背景。没有配置 global background 时，GeeAgent 会显示默认 abstract surface。

`image` 资源只代表图片展示模式，不是 Live2D 背景。

visual layer 还可以声明 `global_background`。global background 会作为全覆盖 Home 背景渲染在 persona visual 后面，包括 Live2D。它支持：

- video；
- image。

global background 的优先级是 video 优先，然后 image。

如果 Live2D persona 没有声明 `global_background`，GeeAgent 会把 Live2D 渲染在默认 abstract Home 背景上。

Live2D persona 可以通过本地 UI 暴露姿势、动作、表情、viewport 位置和缩放。在 Home surface 上，点击可见角色可以触发可用动作或表情变化，并且本地交互层会在 viewport 位置或缩放调整后保持对齐。

## 运行时影响

persona 的影响被刻意保持为轻量。

persona 可以影响：

- system prompt 内容；
- 显式配置的 skill metadata；
- tool allow-list 的建议和约束；
- 视觉展示；
- 本地 appearance 交互状态。

核心 runtime prompt 仍然拥有 Gee 的默认任务边界。Gee 默认不是 coding-first：除非用户明确要求代码开发、修 bug、重构或编辑代码，否则 agent 不应通过修改本地项目源码来完成普通的 app 控制、文件管理、调研或配置请求。这个边界不禁止必要的脚本、数据处理辅助、检查工具或临时自动化代码，它们可以作为任务实现细节使用。

persona 不应该拥有：

- run lineage；
- session continuation；
- approval state；
- event truth；
- task persistence；
- provider routing truth；
- host security policy。

## 本地存储

runtime profile 存储在 GeeAgent config directory 下。persona workspace 存储在本地 `Personas` 目录下。active persona id 是运行时状态，不属于 persona package 本身。

导入后的 profile 文件可以继续编辑。Reload 会重新读取本地 workspace 并生成 runtime profile。如果 reload 失败，最后一次可用的 profile 会保持不变。

## Tool Allow-Lists

`allowed_tool_ids` 可以约束某个 persona 可用的 native runtime tools。

如果字段省略，persona 使用 workspace defaults。如果字段存在，则只允许匹配的工具。pattern 可以使用尾部 `*` 做前缀匹配，例如 `navigate.*`。

frontend 不能提升 persona 的非 Gee 工具权限。对于 shell、file 等普通本地工具，native runtime 会解析 active persona，并在执行前强制检查 allow-list。

`gee.app.*` 和 `gee.gear.*` 这类 Gee host-managed bridge tools 属于第一方产品控制能力，不属于 persona 拥有的通用工具。它们会绕过 persona allow-list，但仍然必须在 Gee host bridge 内校验已启用 gear、已声明 capability、策略状态和参数。

## Import、Reload、Delete

Import：

- 校验 package；
- 复制完整 package 到本地 persona workspace；
- 编译 layered context；
- 生成 normalized runtime profile；
- 刷新 desktop 和 CLI surface。

Reload：

- 重新读取本地 persona workspace；
- 重新编译 layered context；
- 刷新 persona 级 skill source metadata；
- 如果校验失败，保留之前已加载的 profile。

Delete：

- 删除本地 workspace；
- 删除生成的 runtime profile；
- 一方 persona 不能删除。

## 边界

persona package 是声明式的。它不应该包含可执行脚本、原生二进制、应用 bundle，或机器特定的 runtime state。

当前公开文档描述的是已经实现的基础能力。persona market distribution、签名、信任元数据、automation heartbeat execution，以及更广泛的 multi-profile orchestration 仍是未来工作。
