# Gee Basic Development

## Status

Placeholder entry.

This section will document basic GeeAgent development workflows, project structure, build setup, runtime startup, verification, and common contribution rules.

## Current Rule

When system behavior changes, update related public documentation in English, Simplified Chinese, and Japanese.

When Gear or capability behavior changes, also check whether the Codex plugin projection, Gee MCP export schema, generated skills, generated capability reference files, or plugin metadata need to change. If no Codex export update is needed for a substantial Gear change, say so in the work summary.

## Runtime Context Spine

GeeAgent's runtime context spine is the current direction for reducing repeated prompt history while preserving product behavior. GeeAgent keeps the full conversation transcript and runtime events as local truth. The target model-facing path is active SDK session lineage, with context projection reserved for old sessions, lost SDK lineage, cross-engine handoff, and budget telemetry.

In the current first slice, GeeAgent injects the runtime bootstrap instructions once per live SDK session, so same-run continuations do not repeat the full GeeAgent runtime prompt. Later slices will move normal multi-turn workspace continuation onto persisted SDK lineage and summarize or reference large tool results through local artifacts while keeping full output in GeeAgent history.

## Runtime Foundation

GeeAgent's runtime foundation comes from the Phase 3 Runtime Workbench and now carries forward inside Phase 4 product deepening. The active direction is to make conversation, task, tool, approval, Gear, artifact, and context-budget surfaces projections over one append-only runtime event truth.

Phase 3 is not marked complete. GeeAgent has a validated runtime-trust slice, including stable run identity, same-run continuation, typed transcript events, strict Gear evidence, bounded artifact/context handling, replay projection, run-state classification, and minimum inspector projection covered by golden replay plus macOS projection tests. That foundation continues to be refined during Phase 4 product use.

## Phase 4 Product Deepening

Phase 4 is a broad product-deepening stage. GeeAgent will be improved and enriched through real use across the whole system, including both the agent system and the Gear modules. Work in this stage should be driven by dogfood evidence, user workflows, reliability gaps, and product opportunities rather than a narrow runtime-only checklist.

Assistant text now starts moving through transcript events as live deltas instead of only appearing after final completion. Tool and Gear completion failures must preserve the real failed or degraded run state. GeeAgent must not switch to another execution path or make an unfinished runtime continuation look completed.

Workspace chat can now submit local image, file, and folder references as structured input attachments. The full Chat surface and the Home focused chat composer accept picked files and folders, window-level drag-and-drop file URLs, and pasted images staged as local PNG references with compact thumbnails. After send, the transcript keeps compact attachment chips on the user message with kind, status, size when available, and local path inspection; the Chat inspector also shows attachment provenance, resolved paths, access scope, image dimensions, limits, errors, and `fallback_attempted`. The runtime records those attachments on the user message and transcript event, keeps `fallback_attempted: false`, exposes the attachment manifest to the active run, sends ready PNG/JPEG/GIF/WebP images as SDK image content blocks after scoped-root and byte-limit validation, preserves them through the local gateway as OpenAI-compatible image parts, and provides a same-run bounded directory snapshot/listing tool for folder inspection instead of stuffing local paths or media into plain chat text. Replay projection keeps the user-message attachment ids and statuses and shows directory snapshot evidence as normal tool invocation/result rows. For screenshot-vs-folder tasks, the agent reads the image, lists the referenced folder, and compares the structures itself; there is no dedicated screenshot comparison tool. Normal image understanding and text extraction use the model's vision context first; ordinary image-only turns use the no-tool chat profile, so OCR, filesystem reads, and metadata probes are unavailable unless the user asks for tool-based verification or combines the image with local file/folder context. Short retry turns after an image failure keep the last unresolved ready image attachment attached to the active run. When the configured backend model is not vision-capable, the gateway returns `model_unsupported_multimodal` before contacting upstream instead of dropping images or attempting OCR fallback.

Settings exposes one default STT service for audio transcription. Chat voice input and the Audio Capture shortcut bar use that same saved provider, currently Local Whisper, Local SenseVoice, or ElevenLabs, and missing local backends fail explicitly instead of falling back to another provider. The Audio Capture bar can be opened from the menu-bar panel or with Control+Option+A / Shift+Command+A. Microphone and system-audio permission failures report the exact macOS authorization state, bundle id, and running app path; permission requests time out instead of leaving the bar stuck in Starting, and stale TCC entries are called out directly.

The GeeAgentMac main app follows the macOS preferred language by default. Settings > Language can override the main workbench shell to System, English, Simplified Chinese, or Japanese. This applies to GeeAgent-owned main surfaces such as navigation, Home, Chat, Telegram, Tasks/Logs, Automations, the Gears catalog shell, Agents, Settings, Inspector, approval prompts, menu-bar panels, Quick Input, and Audio Capture. Gear-internal screens, Gear manifest text, user messages, assistant replies, runtime logs, provider/model names, file paths, and raw runtime error details remain in their source language.

For Gear work, the live SDK run and Gee MCP bridge are the required path. If the SDK runtime or bridge is not live, GeeAgent reports the structured failure instead of executing the task through an alternate native route.

Native app control is also a shared Gee MCP host path rather than a Gear- or Telegram-specific shortcut. App Chat/runtime can call `native_app_control` (`gee.nativeApp.control`) for supported local macOS apps; V1 exposes Codex Desktop `new_chat_and_send` and returns structured blocked/failed states when the app, permission, target UI element, or send action is unavailable.

Host-action completion now returns to the same SDK run when that run is still alive. If the run is gone, GeeAgent records the structured Gear result and marks the turn as failed or degraded instead of starting a separate hidden completion turn.

Gear invocation arguments are now normalized and validated at the TypeScript runtime boundary before the native host executes a Gear. Focused runtime plans may supply deterministic stage arguments for the matching capability; missing or conflicting required fields still return structured tool errors so the active agent run can correct the call.

Gear-first runtime plans can also include model-only stages, such as current web research or final synthesis after all Gear storage work is done. When the active stage has no Gear focus or required Gear capability, GeeAgent returns to the normal approved SDK tool policy inside the same run and records those SDK tool results as stage evidence instead of treating them as a fallback path. Final-result validation follows the active plan stage, so a research or synthesis continuation is not rejected merely because that segment did not call another Gear after the earlier Gear stages already completed.

The current runtime planning behavior remains adaptive. Ordinary turns use a direct runtime path, light Gear-first turns use the Gear bridge without creating a full deterministic stage plan, and only multi-stage or cross-domain Gear requests enter structured planning. Direct and light turns do not inherit prior stage capsules into the model-facing prompt; detailed runtime events remain available to the transcript, Worked trace, inspector, and replay surfaces instead of being automatically fed back to the model. Conversation previews and final-answer surfaces suppress stage-progress prose such as "Stage complete"; that evidence belongs in Worked and inspector views. New turns also receive a stable `run_id` across transcript events, host actions, approvals, and stage capsules so product projections and replay tooling can group the work without adding more prompt context. Developer replay commands can export a run, reconstruct deterministic projection rows with artifact membership, diagnose malformed event order, and classify run state such as completed, host, tool, approval, session-lost, and event-silence states.

Plain conversational turns, such as greetings, thanks, and small talk without attachments, use a chat-only SDK profile with no shell, file, Gear bridge, or auto-approved tools. Turns that include attachments or ask for local inspection, file work, Gear work, or other actions still use the normal runtime tool policy. The Chat request-error banner is scoped to the active chat send; background Gear or host-action failures remain in their own surfaces or global state instead of appearing as a failure for an unrelated chat message. User-facing run failures use product-level wording, and if the model API fails before the agent can form a reply, GeeAgent may show a fixed configuration, vision-support, timeout, or stopped-run message instead of raw provider JSON. Chat sends show explicit pending activity while the run is active, keep a thinking/reply-wait placeholder visible after runtime or tool activity until assistant chat text arrives, and stream assistant text chunks into the conversation before final completion. While a run is active, the composer Send button becomes Stop so the user can interrupt the active request, mark the run cancelled, clear pending host actions, and start a new message.

The local SDK gateway now applies the configured chat output budget and temperature from `chat-runtime.toml` before forwarding to the provider. If the upstream provider or model is unavailable or times out, GeeAgent reports that failure directly instead of retrying another provider or model.
