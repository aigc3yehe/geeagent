# Gee Basic Development

## Status

Placeholder entry.

This section will document basic GeeAgent development workflows, project structure, build setup, runtime startup, verification, and common contribution rules.

## Current Rule

When system behavior changes, update related public documentation in English, Simplified Chinese, and Japanese.

When Gear or capability behavior changes, also check whether the Codex plugin projection, Gee MCP export schema, generated skills, or plugin metadata need to change. If no Codex export update is needed for a substantial Gear change, say so in the work summary.

## Runtime Context Spine

GeeAgent's runtime context spine is the current direction for reducing repeated prompt history while preserving product behavior. GeeAgent keeps the full conversation transcript and runtime events as local truth. The target model-facing path is active SDK session lineage, with context projection reserved for old sessions, lost SDK lineage, cross-engine handoff, and budget telemetry.

In the current first slice, GeeAgent injects the runtime bootstrap instructions once per live SDK session, so same-run continuations do not repeat the full GeeAgent runtime prompt. Later slices will move normal multi-turn workspace continuation onto persisted SDK lineage and summarize or reference large tool results through local artifacts while keeping full output in GeeAgent history.

## Phase 3 Runtime Workbench

GeeAgent's current runtime mainline is Phase 3 Runtime Workbench. The active direction is to make conversation, task, tool, approval, Gear, artifact, and context-budget surfaces projections over one append-only runtime event truth.

Assistant text now starts moving through transcript events as live deltas instead of only appearing after final completion. Tool and Gear completion failures must preserve the real failed or degraded run state. GeeAgent must not switch to another execution path or make an unfinished runtime continuation look completed.

For Gear work, the live SDK run and Gee MCP bridge are the required path. If the SDK runtime or bridge is not live, GeeAgent reports the structured failure instead of executing the task through an alternate native route.

Host-action completion now returns to the same SDK run when that run is still alive. If the run is gone, GeeAgent records the structured Gear result and marks the turn as failed or degraded instead of starting a separate hidden completion turn.

Gear invocation arguments are now normalized and validated at the TypeScript runtime boundary before the native host executes a Gear. Focused runtime plans may supply deterministic stage arguments for the matching capability; missing or conflicting required fields still return structured tool errors so the active agent run can correct the call.

Gear-first runtime plans can also include model-only stages, such as current web research or final synthesis after all Gear storage work is done. When the active stage has no Gear focus or required Gear capability, GeeAgent returns to the normal approved SDK tool policy inside the same run and records those SDK tool results as stage evidence instead of treating them as a fallback path. Final-result validation follows the active plan stage, so a research or synthesis continuation is not rejected merely because that segment did not call another Gear after the earlier Gear stages already completed.

The local SDK gateway now applies the configured chat output budget and temperature from `chat-runtime.toml` before forwarding to the provider. If the upstream provider or model is unavailable or times out, GeeAgent reports that failure directly instead of retrying another provider or model.
