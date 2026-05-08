# Gee 基础开发

## 状态

占位入口。

本节将记录 GeeAgent 基础开发流程、项目结构、构建设置、runtime 启动、验证方式，以及常见贡献规则。

## 当前规则

当系统行为发生变化时，需要同步更新英文、简体中文、日文三种公开文档中相关的表述。

当 Gear 或 capability 行为发生变化时，也需要检查 Codex plugin projection、Gee MCP export schema、生成的 skills、生成的 capability reference 文件或 plugin metadata 是否需要同步更新。如果一次实质性 Gear 改动不需要更新 Codex export，应在工作总结里明确说明。

## Runtime Context Spine

GeeAgent 的 runtime context spine 是当前减少重复 prompt 历史、同时保持产品行为不变的演进方向。GeeAgent 会把完整 conversation transcript 和 runtime events 保留为本地事实来源。目标模型侧路径是优先使用 active SDK session lineage，并把 context projection 保留给旧会话、SDK lineage 丢失、跨引擎移交和 budget telemetry 场景。

当前第一段改造只做到每个 live SDK session 注入一次 runtime bootstrap 指令，因此 same-run continuation 不再重复携带完整 GeeAgent runtime prompt。后续阶段会把普通多轮 workspace continuation 迁到持久化 SDK lineage，并将大型工具结果总结或转为本地 artifact 引用，同时完整输出继续保留在 GeeAgent history 中。

## Runtime Foundation

GeeAgent 的 runtime foundation 来自 Phase 3 Runtime Workbench，现在会在 Phase 4 产品深化阶段继续演进。当前方向是让 conversation、task、tool、approval、Gear、artifact 和 context-budget 等界面，都成为同一个 append-only runtime event truth 的投影。

Phase 3 不标记为完成。GeeAgent 已经具备一个经过验证的 runtime-trust slice，包括稳定 run identity、same-run continuation、typed transcript events、严格 Gear evidence、有边界的 artifact/context 处理、replay projection、run-state classification，以及由 golden replay tests 加 macOS projection tests 覆盖的最小 inspector projection。这套 foundation 会在 Phase 4 的实际产品使用中继续修正和深化。

## Phase 4 产品深化

Phase 4 是一个宽泛的产品深化阶段。GeeAgent 会在实际使用中持续优化和丰富整个系统，包括 agent 系统和 Gear 两大模块。这个阶段的工作应由 dogfood 证据、用户工作流、可靠性缺口和产品机会驱动，而不是由狭窄的 runtime-only checklist 驱动。

Assistant 文本现在开始通过 transcript event 以 live delta 的形式进入前端，而不是只在最终完成后一次性出现。Tool 和 Gear completion 失败时必须保留真实的 failed 或 degraded run state；GeeAgent 不能切换到另一条执行路径，也不能把没有完成的 runtime continuation 伪装成 completed。

Workspace chat 现在可以把本地图片、文件和文件夹引用作为结构化 input attachments 提交。完整 Chat 页面和 Home focused chat composer 支持选择文件/文件夹、窗口级拖放本地 file URLs，以及把粘贴的图片暂存为本地 PNG 引用并显示紧凑缩略图。发送后，transcript 会在 user message 上保留紧凑附件 chip，显示类型、状态、可用时的大小和本地路径检查入口；Chat inspector 也会显示附件来源、解析后的路径、访问范围、图片尺寸、限制、错误信息和 `fallback_attempted`。Runtime 会把这些附件记录在 user message 和 transcript event 上，保持 `fallback_attempted: false`，把 attachment manifest 暴露给 active run，并在 scoped-root 和 byte-limit 校验后把 ready 的 PNG/JPEG/GIF/WebP 图片作为 SDK image content block 发送，同时通过本地 gateway 保留为 OpenAI-compatible image parts；文件夹则通过同一轮里的有边界目录快照/列表工具检查，而不是把本地路径或媒体内容塞进普通 chat 文本。Replay projection 会保留 user message 的附件 id 和状态，并把目录快照证据显示为正常的 tool invocation/result 行。对于截图对比文件夹的任务，agent 会自己读图、列出引用文件夹、再对比两边结构；不会使用专门的截图对比工具。普通图片理解和图片文字提取会优先使用模型 vision context；普通 image-only turn 会使用 no-tool chat profile，因此除非用户要求工具级验证，或把图片和本地文件/文件夹上下文一起使用，否则 OCR、文件系统读取和 metadata 探测不可用。图片失败后的短续试消息会继续携带上一张尚未成功处理的 ready image attachment。当配置的 backend model 不支持 vision 时，gateway 会在联系 upstream 前返回 `model_unsupported_multimodal`，不会丢弃图片，也不会尝试 OCR fallback。

对于 Gear 工作，live SDK run 和 Gee MCP bridge 是必需路径。若 SDK runtime 或 bridge 不可用，GeeAgent 会报告结构化失败，而不是通过另一条 native 路径执行任务。

Host-action completion 现在会在同一个 SDK run 仍然存活时回到该 run。若该 run 已经丢失，GeeAgent 会记录结构化 Gear 结果，并把本轮标记为 failed 或 degraded，而不是再启动一个隐藏的分离 completion turn。

Gear invocation 参数现在会先在 TypeScript runtime 边界完成规范化和校验，再交给 native host 执行。已聚焦的 runtime plan 可以为匹配的 capability 提供确定性阶段参数；缺失或冲突的必填字段仍会作为结构化 tool error 返回，使 active agent run 可以修正调用。

Gear-first runtime plan 也可以包含 model-only stage，例如 Gear 存储工作完成后的联网研究或最终综合解释。当 active stage 没有 Gear focus、也没有 required Gear capability 时，GeeAgent 会在同一个 run 内回到正常的已批准 SDK tool policy，并把这些 SDK tool results 记录为 stage evidence，而不是把它们当作 fallback path。最终结果校验会跟随 active plan stage；如果同一个 run 已经完成前面的 Gear 阶段，research 或 synthesis continuation 不会因为本段没有再次调用 Gear 而被拒绝。

当前 runtime planning 行为仍然是弹性的。普通 turn 走 direct runtime path；轻量 Gear-first turn 会使用 Gear bridge，但不会创建完整 deterministic stage plan；只有多阶段或跨领域 Gear 请求才进入 structured planning。Direct 和 light turn 不会把历史 stage capsule 注入 model-facing prompt；详细 runtime events 会留在 transcript、Worked trace、inspector 和 replay surface 中，而不是自动回灌给模型。会话预览和最终答案表面会抑制 `Stage complete` 这类阶段进度文案；这些证据应留在 Worked 和 inspector 视图中。新的 turn 也会在 transcript event、host action、approval 和 stage capsule 中使用稳定的 `run_id`，让产品投影和 replay 工具能按同一轮工作分组，而不增加 prompt 上下文。开发者 replay 命令可以导出某个 run、重建带 artifact 归属的确定性 projection rows、诊断异常事件顺序，并分类 completed、host、tool、approval、session-lost 和 event-silence 等运行状态。

没有附件的问候、感谢和闲聊等纯对话 turn 会使用 chat-only SDK profile，不暴露 shell、file、Gear bridge 或自动批准工具。包含附件，或明确要求本地检查、文件操作、Gear 操作及其他动作的 turn，仍会使用正常 runtime tool policy。Chat 的 request-error banner 只对应当前 chat send；后台 Gear 或 host-action 失败会留在各自界面或全局状态中，不会显示成无关聊天消息的失败。面向用户的 run 失败会使用产品级文案；如果模型 API 在 agent 能组织回复前就失败，GeeAgent 可以直接显示固定的配置、vision 支持、超时或已停止文案，而不是暴露原始 provider JSON。Chat 发送后会在 run 活跃期间持续显示明确的 pending activity；runtime 或工具活动出现后，如果 assistant chat 文本还没到，会继续保留 thinking/reply-wait 占位；assistant 文本 chunk 会在最终完成前流式进入 conversation。run 活跃时 composer 的 Send 按钮会变成 Stop，用户可以中断当前请求、把 run 标记为 cancelled、清空等待中的 host actions，并开始新的消息。

本地 SDK gateway 现在会先应用 `chat-runtime.toml` 中配置的 chat 输出预算和 temperature，再转发给 provider。如果上游 provider 或 model 不可用或超时，GeeAgent 会直接报告失败，而不是重试另一个 provider 或 model。
