# Gee 基础开发

## 状态

占位入口。

本节将记录 GeeAgent 基础开发流程、项目结构、构建设置、runtime 启动、验证方式，以及常见贡献规则。

## 当前规则

当系统行为发生变化时，需要同步更新英文、简体中文、日文三种公开文档中相关的表述。

当 Gear 或 capability 行为发生变化时，也需要检查 Codex plugin projection、Gee MCP export schema、生成的 skills 或 plugin metadata 是否需要同步更新。如果一次实质性 Gear 改动不需要更新 Codex export，应在工作总结里明确说明。

## Runtime Context Spine

GeeAgent 的 runtime context spine 是当前减少重复 prompt 历史、同时保持产品行为不变的演进方向。GeeAgent 会把完整 conversation transcript 和 runtime events 保留为本地事实来源。目标模型侧路径是优先使用 active SDK session lineage，并把 context projection 保留给旧会话、SDK lineage 丢失、跨引擎移交和 budget telemetry 场景。

当前第一段改造只做到每个 live SDK session 注入一次 runtime bootstrap 指令，因此 same-run continuation 不再重复携带完整 GeeAgent runtime prompt。后续阶段会把普通多轮 workspace continuation 迁到持久化 SDK lineage，并将大型工具结果总结或转为本地 artifact 引用，同时完整输出继续保留在 GeeAgent history 中。

## Phase 3 Runtime Workbench

GeeAgent 当前 runtime 主线是 Phase 3 Runtime Workbench。当前方向是让 conversation、task、tool、approval、Gear、artifact 和 context-budget 等界面，都成为同一个 append-only runtime event truth 的投影。

Assistant 文本现在开始通过 transcript event 以 live delta 的形式进入前端，而不是只在最终完成后一次性出现。Tool 和 Gear completion 失败时必须保留真实的 failed 或 degraded run state；GeeAgent 不能切换到另一条执行路径，也不能把没有完成的 runtime continuation 伪装成 completed。

对于 Gear 工作，live SDK run 和 Gee MCP bridge 是必需路径。若 SDK runtime 或 bridge 不可用，GeeAgent 会报告结构化失败，而不是通过另一条 native 路径执行任务。

Host-action completion 现在会在同一个 SDK run 仍然存活时回到该 run。若该 run 已经丢失，GeeAgent 会记录结构化 Gear 结果，并把本轮标记为 failed 或 degraded，而不是再启动一个隐藏的分离 completion turn。

Gear invocation 参数现在会先在 TypeScript runtime 边界完成规范化和校验，再交给 native host 执行。已聚焦的 runtime plan 可以为匹配的 capability 提供确定性阶段参数；缺失或冲突的必填字段仍会作为结构化 tool error 返回，使 active agent run 可以修正调用。

Gear-first runtime plan 也可以包含 model-only stage，例如 Gear 存储工作完成后的联网研究或最终综合解释。当 active stage 没有 Gear focus、也没有 required Gear capability 时，GeeAgent 会在同一个 run 内回到正常的已批准 SDK tool policy，并把这些 SDK tool results 记录为 stage evidence，而不是把它们当作 fallback path。最终结果校验会跟随 active plan stage；如果同一个 run 已经完成前面的 Gear 阶段，research 或 synthesis continuation 不会因为本段没有再次调用 Gear 而被拒绝。

本地 SDK gateway 现在会先应用 `chat-runtime.toml` 中配置的 chat 输出预算和 temperature，再转发给 provider。如果上游 provider 或 model 不可用或超时，GeeAgent 会直接报告失败，而不是重试另一个 provider 或 model。
