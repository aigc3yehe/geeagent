# Gear Development

## Status And Date

Document date: 2026-05-01.

Status: Gear Platform V1 public development standard. This document records both current implementation state and the target architecture. Implemented behavior is marked as current. Confirmed direction that is not fully implemented yet is described as target state or V1 standard.

This document is for GeeAgent open-source collaborators, Gear developers, and anyone who needs to understand the boundary of GeeAgent's built-in app and widget system. It is not marketing copy and it is not a long-term marketplace roadmap. It is the first practical platform standard for Gears.

## Purpose

Gear is GeeAgent's platform for optional built-in apps and Home widgets. The goal is not to keep adding app-specific business logic to the main workbench. The goal is to create a small, local-first, copy-installable app ecosystem.

Core goals:

- A gear is an independent package.
- A gear can be copied, imported, enabled by default, updated, or removed. The V1 catalog does not expose a user-facing gear disable control.
- If a gear folder is deleted, GeeAgent should stop showing that gear after restart or registry refresh.
- If a valid gear folder is copied into the user data location, GeeAgent should show that gear after restart or registry refresh.
- A broken, missing, policy-blocked, or partially installed gear must not break GeeAgent chat, tasks, settings, runtime startup, or unrelated gears.
- A gear declares its name, description, developer, cover image, version, entry, dependencies, permissions, and future agent capabilities through `gear.json`.
- GeeAgent owns discovery, validation, preparation, default enablement, window opening, widget rendering, and the future agent bridge.
- The gear owns its business logic, resources, data, dependency declarations, and callable capability declarations.
- The future root agent controls gears through one control bridge, not by adding gear-specific pseudo-tools to the agent runtime.

V1 should stay practical. V1 focuses on local copy/import, bundled gears, dependency preflight and first-run setup, default enablement, native macOS UX, and future `gear.invoke` readiness. The V1 catalog does not show a disable affordance. Policy-level disablement is an internal protection state, not a normal user action. V1 does not include a remote marketplace, payments, ratings, reviews, remote automatic updates, or mandatory developer signing.

## Terms

- `Gear`: an optionally installed and default-enabled local app or widget package in GeeAgent.
- `Gear app`: a full application that opens from the Gears catalog. Complex gears should open their own macOS windows instead of being embedded inside the main GeeAgent window.
- `Gear widget`: a small information component displayed on Home, such as BTC price or CPU / memory monitoring.
- `Gear package`: a folder named by gear id containing `gear.json`, README, assets, scripts, setup metadata, source, or app files.
- `GearHost`: the GeeAgent layer that discovers, validates, imports, prepares, opens, and tracks gears. It also exposes the ready capability list to the future agent bridge.
- `GearKit`: the stable shared contract used by GearHost, first-party native gears, and future adapters. It should not contain concrete app business concepts.
- `gear.json`: the gear manifest. It is the minimum discovery file and the declaration source for catalog metadata, dependency setup, and future agent capabilities.
- `Dependency preflight`: the process of checking whether required dependencies exist, versions are compatible, and permissions allow launch before a gear opens or renders.
- `Capability`: a manifest-declared operation that the future root agent may invoke. A capability is a declaration, not a separate global agent tool.
- `Codex plugin projection`: a generated Codex-compatible package and Gee MCP export bridge that lets Codex discover and invoke selected GeeAgent capabilities. It is an export view over Gear, not a replacement for Gear packages, native Gear UI, GearHost, or GeeAgent runtime semantics.

## Current Implementation State

The active macOS app path is:

```text
apps/macos-app/
```

Current GearKit code lives in:

```text
apps/macos-app/Sources/GearKit/
├── GearCapabilityRecord.swift
├── GearDependencyManifest.swift
├── GearKind.swift
├── GearManifest.swift
└── ModuleDisplayMode.swift
```

Current GearHost code lives in:

```text
apps/macos-app/Sources/GearHost/
├── GearDependencyPreflight.swift
├── GearPreparationService.swift
├── GearRecordMapping.swift
├── GearHost.swift
├── GearNativeWindowDescriptor.swift
└── GearRegistryCompatibility.swift
```

Current bundled gear package skeletons live in:

```text
apps/macos-app/Gears/
├── media.library/
├── hyperframes.studio/
├── media.generator/
├── smartyt.media/
├── twitter.capture/
├── bookmark.vault/
├── wespy.reader/
├── btc.price/
└── system.monitor/
```

Current first-party native gear implementations are still compiled by the host:

```text
apps/macos-app/Sources/GeeAgentMac/Modules/MediaLibrary/
apps/macos-app/Sources/GeeAgentMac/Modules/HyperframesStudio/
apps/macos-app/Sources/GeeAgentMac/Modules/MediaGenerator/
apps/macos-app/Sources/GeeAgentMac/Modules/SmartYTMedia/
apps/macos-app/Sources/GeeAgentMac/Modules/TwitterCapture/
apps/macos-app/Sources/GeeAgentMac/Modules/BookmarkVault/
apps/macos-app/Sources/GeeAgentMac/Modules/WeSpyReader/
apps/macos-app/Sources/GeeAgentMac/Views/Content/HomeWidgetsView.swift
```

Current capabilities already present:

- `GearKit` and `GearHost` file boundaries exist, while still keeping one SwiftPM executable target.
- Bundled gear packages have moved out of the main app source tree into `apps/macos-app/Gears`.
- `gear.json` scanning from bundled resources and user Application Support.
- Invalid manifest folders degrade into install issues in the Gears catalog instead of crashing the app.
- Folder name must match manifest id or the folder is shown as an install issue.
- Gears are enabled by default. An internal policy-disabled state remains available, but the V1 catalog does not expose a user disable affordance.
- Dependency preflight and setup snapshot model.
- `hyperframes.studio` dependency plan for Node, npm, Hyperframes, FFmpeg, and FFprobe.
- Gears catalog states for checking, installing, failed, and open.
- Native windows for first-party `media.library` and `hyperframes.studio`.
- `media.generator` is a current first-party Gear app. It provides a native media-generation surface, uses the global Xenodia provider channel for image generation, and exposes structured agent capabilities for listing models, creating generation tasks, and reading task state.
- First V1 host bridge surface for `gee.app.openSurface`, progressive Gear capability disclosure, and shared Gear invocation.
- `bookmark.vault` is a current first-party Gear app. It saves arbitrary text or URLs into `gear-data/bookmark.vault`, enriches media URLs through the same `yt-dlp` metadata family used by `smartyt.media`, enriches Twitter/X tweet URLs through an embed metadata path, and falls back to basic web metadata fetch for other sites.
- `wespy.reader` is a current first-party Gear app. It wraps the MIT-licensed WeSpy Python package to fetch WeChat public-account articles, WeChat albums, and general article pages into Markdown-first local task files.
- Transitional host action intents let first-party runtime turns hand native Gear actions back to GeeAgentMac while full SDK/MCP tool exposure is still being completed.
- External Codex calls now use the generated `geeagent-codex` plugin plus the Gee MCP server to create shared-store external invocations. GeeAgentMac polls that queue and drains `gee_invoke_capability` / `gee_open_surface` through the same GearHost bridge used by the runtime, then Codex reads results with `gee_get_invocation`. The first exported built-in capabilities are low-risk `media.generator` model/task queries and `media.library` view filtering/folder focus.
- Home widget direction for `btc.price` and `system.monitor`.

Current gaps:

- First-party gear business logic still lives inside the main app source tree.
- Gear package folders are not yet the full implementation boundary.
- Third-party gear import is not implemented yet.
- Full agent-runtime SDK/MCP tool injection for every Gear capability is not complete yet.
- Broad external Codex coverage is intentionally narrow. Only capabilities with explicit `exports.codex.enabled: true` are visible, and provider-generating, download, import, user-file, and high-side-effect capabilities remain hidden or explicitly disabled until their approval, artifact, and failure semantics are audited end to end.
- `GearKit` and `GearHost` have not been split into separate SwiftPM targets yet.

## Target Architecture

The target architecture has four layers:

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

The main app owns the workbench. It does not own gear business logic.

Responsibilities:

- Main workspace shell, Home, chat, tasks, settings, side rail, and app chrome.
- Open the Gears catalog.
- Ask GearHost which gears exist and what state each gear is in.
- Ask GearHost to prepare and open a gear.
- Host gear windows or Home widget surfaces provided by GearHost adapters.

Non-responsibilities:

- No gear business logic.
- No gear dependency recipe logic in `WorkbenchStore`.
- No direct knowledge of a third-party gear's internal files.
- No gear-specific tools implemented inside the agent runtime.

## GearHost

GearHost is the Gear platform manager. It should be implemented in Swift because it needs direct integration with macOS file system locations, Application Support, windows, processes, permissions, and native UI.

Responsibilities:

- Discover bundled and user-installed gear folders.
- Decode and validate `gear.json`.
- Merge bundled and user gear records.
- Manage default enablement and policy-blocked state.
- Track install and preparation state.
- Run dependency preflight and setup.
- Import `.geegear.zip` files or gear folders.
- Route open requests to the correct adapter.
- Provide Home widget records.
- Provide ready and policy-allowed capability declarations to the future agent bridge.
- Keep per-gear setup logs and status snapshots.

GearHost should not know Eagle folder shapes, Hyperframes project internals, BTC formatting, or other app-specific business details. Those belong to the gear.

## GearKit

GearKit is the stable shared contract used by GearHost, first-party native gears, and future adapters.

V1 contents:

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

GearKit should avoid app-specific concepts. Eagle folders, media duration filters, Hyperframes project templates, and BTC price formatting do not belong in GearKit.

## Gear Packages

Each gear owns one folder. Deleting that folder removes the gear after restart or registry refresh. Copying a valid package into the user gear directory makes the gear appear after restart or registry refresh.

Target development bundled gear location:

```text
apps/macos-app/Gears/<gear-id>/
```

During migration, the registry scans both legacy and current bundled resource directory names:

```text
gears/
Gears/
```

Runtime user-installed gear location:

```text
~/Library/Application Support/GeeAgent/gears/<gear-id>/
```

Gear user data location:

```text
~/Library/Application Support/GeeAgent/gear-data/<gear-id>/
```

Gear log location:

```text
~/Library/Application Support/GeeAgent/gear-data/<gear-id>/logs/
```

V1 package layout:

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

Package rules:

- Folder name must equal `gear.json.id`.
- `gear.json` is required.
- Deliverable gears must include `README.md`.
- A folder containing only `gear.json` is a manifest stub, not a complete deliverable gear.
- Package files are treated as app code and static resources.
- Mutable user data must be written to `gear-data/<gear-id>/`.
- A gear must not read another gear's private package files.
- A gear must not write GeeAgent source folders.
- A gear must not store business data in `WorkbenchStore`.

## Language And Runtime Policy

V1 supports multiple implementation styles, but it must be explicit about their safety and intended use.

Host, GearHost, and GearKit should use Swift.

Reasons:

- GeeAgent is a native macOS app.
- Gear windows, menus, keyboard shortcuts, drag/drop, Quick Look, Finder handoff, permissions, and accessibility should feel native.
- Gear management needs tight integration with macOS Application Support, process supervision, window lifecycle, sandbox, and permissions.

First-party native gear UI should use Swift, SwiftUI, and AppKit.

Applies to:

- `media.library`
- `hyperframes.studio`
- Complex apps that require Quick Look, Finder handoff, native video / image preview, drag/drop, menus, or keyboard shortcuts.

For AA-style third-party sharing, V1 should prefer:

- `webview`: local UI files hosted by GeeAgent in a native window shell.
- `external_process`: a local process started and supervised by GeeAgent through stdio-json or another local protocol.

Reasons:

- Users can copy or import a gear folder or `.geegear.zip` into Application Support.
- GeeAgent should not dynamically compile and load arbitrary Swift source into the main process in V1.
- External processes can be stopped, logged, timed out, and isolated more safely than arbitrary in-process code.

Third-party native Swift plugins should be a later signed bundle or XPC route, not the default V1 capability.

Gear-internal data processing may use TypeScript, Python, CLI tools, wasm, local models, or other runtimes, but the manifest must declare the entry, dependencies, and permissions.

## Manifest V1

Minimal V1 manifest:

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

Required fields:

- `schema`
- `id`
- `name`
- `description`
- `developer`
- `version`
- `kind`
- `entry`

Recommended fields:

- `category`
- `icon`
- `cover`
- `homepage`
- `license`
- `platforms`
- `permissions`
- `dependencies`
- `agent.capabilities`

During migration, V1 should accept existing `kind` values:

- `atmosphere`: a full app surface that can be opened from the catalog.
- `widget`: a small Home widget.

The recommended future wording is:

- `app`
- `widget`

`category` can express product grouping, such as:

- `Atmosphere`
- `Media`
- `Utilities`
- `Monitoring`
- `Creative`

`kind` determines runtime and presentation behavior. `category` is only for catalog organization.

## Entry Standard

V1 entry types:

- `native`: first-party or host-known native adapter.
- `widget`: Home widget adapter.
- `external_process`: local process supervised by GearHost.
- `webview`: local files rendered in a native WebView shell.

`native` example:

```json
{
  "entry": {
    "type": "native",
    "native_id": "media.library"
  }
}
```

`widget` example:

```json
{
  "entry": {
    "type": "widget",
    "widget_id": "btc.price"
  }
}
```

`external_process` example:

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

`webview` example:

```json
{
  "entry": {
    "type": "webview",
    "root": "app/index.html",
    "allow_remote_content": false
  }
}
```

V1 should not add more entry types unless a real gear requires them and GearHost has the corresponding adapter.

## Dependency Standard

The dependency strategy is global-first.

Rules:

- If a compatible global dependency already exists, the gear uses it.
- If a required dependency is missing, setup is triggered when the user opens that gear.
- Dependencies are not installed at GeeAgent startup.
- Dependency installers do not run for policy-blocked gears.
- Dependency failure affects only the current gear.
- Global installers mutate the user's developer environment and must be visible to the user.
- Gear-local installers may only write inside allowed gear package or gear-data locations.

Dependency manifest example:

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

Supported dependency kinds:

- `binary`: executable helper or CLI.
- `framework`: native framework or dylib bundle.
- `model`: local model, embedding index, or inference asset.
- `data`: seed database, lookup table, templates, or static content.
- `runtime`: language or runtime required by an external process gear.

Supported dependency scopes:

- `global`: resolved from the system environment or known install locations and installed through a user-visible setup flow when missing.
- `gear_local`: resolved relative to the gear folder and prepared only for that gear.

Supported installer types:

- `recipe`: host-known install recipe such as Homebrew install, npm global install, or guided official installer.
- `script`: gear-local installer script.
- `archive`: expands a gear-local archive into the declared target.
- `none`: declares that the dependency must already be present.

Installer requirements:

- Must be idempotent.
- Running twice must not break the gear.
- `gear_local` installers must not write outside the gear boundary except temporary files.
- `global` installers must show action, logs, failure, and retry through a user-visible flow.
- Installers that require network access must declare `network.download`.

## First-Run Install Flow

When the user opens or enables a gear and required dependencies are missing, GeeAgent should not immediately fail the open action. It should enter the setup flow for that gear.

State machine:

```text
installed -> checking -> ready
installed -> checking -> needs_setup
needs_setup -> installing -> ready
needs_setup -> installing -> install_failed
install_failed -> installing -> ready
policy_blocked -> checking/installing only after policy changes
```

State meanings:

- `invalid`: manifest or package invalid.
- `installed`: package discoverable and manifest valid, but dependencies have not been confirmed ready.
- `disabled`: disabled internally or by policy. The V1 catalog does not provide a user disable button.
- `checking`: dependency or permission preflight is running.
- `needs_setup`: required dependency missing or incompatible.
- `installing`: setup is running.
- `ready`: can open or render.
- `install_failed`: setup failed and unrelated features keep working.
- `blocked`: policy or permission prevents use.

Gears catalog button meanings:

- `Open`: gear is ready and can launch.
- `Checking...`: preflight is running.
- `Install Dependencies`: dependencies are missing and setup can run.
- `Installing...`: setup is running and the button must not trigger another install.
- `Retry Install`: previous install failed and clicking retries.
- The V1 catalog does not show user-facing `Enable` / `Disabled` actions. Gears are enabled by default; unavailable gears surface blocked, installing, or failed states instead.

Home widgets use the same dependency flow. A widget with missing dependencies should not render a broken Home card. It should show installing or failed state in the Gears catalog.

## Import And Install Standard

V1 supports two local install inputs:

- Gear folder.
- `.geegear.zip`.

Install target:

```text
~/Library/Application Support/GeeAgent/gears/<gear-id>/
```

Import flow:

- User selects a folder or `.geegear.zip`.
- If the input is a zip, extract it into a temporary directory first.
- Reject path traversal.
- Reject multiple top-level packages.
- Validate `gear.json`.
- Ensure folder name equals manifest `id`.
- Check schema, version, platforms, and entry type.
- If the same ID already exists, ask replace / update / cancel.
- Copy into Application Support atomically.
- Refresh GearHost registry.
- Show status in the Gears catalog.

V1 does not need a remote marketplace. V1 must make local sharing work first: AA can build a gear, send a folder or `.geegear.zip` to another person, and that person can install it by copying it into the user data directory or running `Import Gear...`.

## Permission Standard

V1 permissions must be explicit and minimal.

Recommended permission IDs:

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

Rules:

- Undeclared high-risk capabilities must not run.
- Installers that download files must declare `network.download`.
- External process gears must declare `process.spawn`.
- Shell scripts must declare `shell.execute`.
- High-risk permissions require user confirmation.
- Manifest permissions describe gear needs. They do not replace macOS system permissions.

## Storage Standard

Package directory:

```text
~/Library/Application Support/GeeAgent/gears/<gear-id>/
```

Mutable data directory:

```text
~/Library/Application Support/GeeAgent/gear-data/<gear-id>/
```

Recommended data layout:

```text
gear-data/<gear-id>/
├── config.json
├── state/
├── cache/
├── logs/
├── projects/
└── exports/
```

Rules:

- Package directory stores manifest, code, static resources, setup files, and scripts.
- Data directory stores user data, state, caches, generated output, and logs.
- A gear must not write another gear's data directory.
- A gear must not write GeeAgent source directories.
- `data/` inside the package is only for seed or static data, not runtime user state.

## UIUX Standard

Gears must provide a native macOS experience.

Rules:

- Gear apps should feel like native macOS apps, not web pages embedded inside the main window.
- Complex apps should open their own independent windows.
- Prefer SwiftUI / AppKit windows, menus, keyboard commands, system sheets, popovers, drag/drop, Quick Look, Finder handoff, and accessibility patterns.
- WebView gears must still be hosted by a native shell.
- Home widgets must stay lightweight and must not embed full app navigation.
- Missing dependencies should show setup state, not broken UI.
- Components may be visually customized, but behavior should match macOS user expectations.
- The Gears catalog should avoid excessive nested containers. Prefer shallow navigation, clear lists, state badges, and necessary action buttons.
- Button groups and component groups should not rely on parent container borders to express hierarchy. Prefer proximity and consistent styling.
- Dropdowns, popovers, buttons, sliders, and context menus need custom visual polish while keeping macOS-like interaction models.

## Provider And Channel Ownership

Provider and channel configuration is global GeeAgent infrastructure, not Gear state.

Rules:

- Main app runtime owns provider routing, API keys, endpoint URLs, readiness checks, and secret storage.
- Gear packages must not store provider API keys, long-term tokens, or channel-specific secrets in `gear.json`, package files, or `gear-data/<gear-id>/`.
- A Gear may declare that it needs a global network capability, such as Xenodia image generation, but it must request the configured channel through the Gee host/runtime boundary.
- Xenodia image generation is exposed as a global provider channel alongside chat routing. The channel currently includes image generation and task retrieval endpoints, and may later include a dedicated storage upload endpoint.
- Reference images for generation should use the global Xenodia media channel. When no separate Xenodia storage API is configured, local reference images may be sent directly through the Xenodia image generation request as multipart `image_input`; Gears must not reintroduce Qiniu or another package-local object store.
- First-party Gears may show future provider placeholders, such as video or audio generation, but they must not wire non-Xenodia providers copied from reference projects until the global provider layer supports them.
- Provider failures must return structured errors to the active run. The Gear UI may show a concise state, but final user-facing prose still belongs to the active agent/LLM.

## Agent Control Bridge

Gear does not define the full agent protocol. The agent runtime owns the control protocol, permission semantics, run events, approval flow, and continuation semantics.

Current V1 implements the first host bridge surface for native Gee usage:

- `gee.app.openSurface` opens a Gee surface or Gear window by id, such as `media.library`.
- `gee.gear.listCapabilities` discloses enabled Gear capabilities through a compact summary first, including capability ids and required arguments.
- `gee.gear.invoke` invokes one declared Gear capability through the shared host bridge.
- The phase-2 SDK runtime exposes these controls to the active agent through the `gee` MCP bridge tools `app_open_surface`, `gear_list_capabilities`, and `gear_invoke`.
- MCP Gear tools pause the same SDK run, emit `host_action_intents`, let GeeAgentMac execute the native Gear action, then resume the same run with structured host results. If the agent needs another Gear step after inspecting the result, the same pause / execute / resume loop repeats.
- If the SDK session does not expose the `gee` MCP tools, GeeAgent must report a structured runtime failure instead of switching to a fallback execution path, inspecting source code as a substitute, or claiming the task is complete.
- Legacy host-action control frames are migration-only data. The runtime must consume or reject them before transcript projection, and GeeAgentMac must not show them as normal chat text. Visible chat should render user text, typed plan/focus/stage activity rows, meaningful thinking state, tool invocation/result rows, and assistant replies in transcript event order. Once a final assistant reply exists, earlier work trace rows may collapse into a compact `Worked` section whose rows can still be expanded individually. Low-signal runtime plumbing such as setup, delegation, same-run Gear pause/resume breadcrumbs, finalize markers, and model-authored `Stage complete:` progress fragments should not be promoted into prominent thinking blocks or chat bubbles.
- `host_action_intents` are created by the active SDK run's MCP Gear bridge and are applied by GeeAgentMac in order. Complex capture or multi-Gear requests must stay agent-planned through the MCP bridge.
- Media-library filters set through `media.filter` are visible as active filters in the native UI. The user can return to the full media view through `All` or the `Clear filters` affordance.
- `media.filter`, `media.focus_folder`, and `media.import_files` require an authorized media library. The media Gear should first try to restore saved macOS security-scoped access, then fall back to the saved last-library path and let macOS surface a visible one-time authorization prompt when needed. Opening the Media Library window must not wait on that restore attempt; the window should appear first and show bounded restore progress. If no library can be restored before the restore timeout, Gear actions must return a structured failure with `code: "gear.media.authorization_required"` and a `navigate.module` intent for `media.library` instead of reporting a misleading success.
- Runtime turns must persist tool-use and tool-result events incrementally as they arrive. GeeAgentMac should be able to refresh the active Chat transcript while a Gear workflow is still running, so users see each bridge call appear step by step instead of receiving several completed tool cards only after the final reply.
- Tool requests must pass through GeeAgent's Tool Boundary Gateway before execution. The gateway normalizes arguments, validates the target, chooses the execution adapter, and normalizes results before transcript projection. This applies to provider-converted tool calls, Claude SDK native tools, and Gear bridge calls; UI-only cleanup is not enough.
- Focused runtime stages may carry deterministic `capability_args` extracted from the user's request or prior structured results. The Tool Boundary Gateway may merge those arguments into the matching same-stage Gear invocation when the model omits them, but conflicting values fail as structured argument errors instead of being silently overwritten.
- For Gear-matching requests, the bridge is the preferred execution path. The agent should not inspect GeeAgent source files, call SDK `Skill` aliases, or use Bash to discover product internals unless the user explicitly asks to debug GeeAgent itself.

Gear execution results are structured data, not final prose. A Gear capability, native adapter, or transitional router may report state changes, counts, artifacts, warnings, and errors, but it must not hardcode the final user-facing completion sentence. After all Gear actions in a turn finish, GeeAgent must return those structured results to the active agent/LLM, and the agent must compose the final reply in the user's language. If the LLM continuation cannot run, GeeAgent should show a transparent pending or failure state instead of a fake hardcoded success message.

When the native host completes a Gear action, it may pass both a concise summary and a bounded `result_json` payload back to the continuation turn. The summary is for quick display; `result_json` is the source of truth for task ids, paths, counts, artifacts, captured records, and structured errors. Large result payloads should be saved inside the Gear data directory and referenced by path instead of flooding the agent context.

During continuation, GeeAgent may replace a large `result_json` payload with a `result_artifact` reference. The model-facing payload keeps ids, status, summary, error, artifact path, hash, byte count, and token estimate, while the full JSON is stored on disk for explicit follow-up inspection.

Complex Gear work must be agent-planned, not router-planned. Local Gear capabilities should be decomposed into small tool primitives such as save bookmark, fetch tweet, sniff media, download media, import files, and attach local paths. The active agent should create a plan, invoke one primitive, inspect the structured result, and then choose the next primitive. Local routers and `host_action_intents` must not pre-build a full multi-step workflow such as “capture Tweet, discover media, download video, import to Media Library, and update Bookmark” because that prevents result-driven correction.

When a runtime plan has a focused stage, capability discovery is stage-scoped. GeeAgent should request the focused summary for the current stage first, then move to later stage focus sets only after the required structured result exists.

Stage advancement requires structured `result_json` evidence with the completed Gear and capability identifiers. Human-readable summaries may help the UI, but they are not enough to mark a stage complete.

Gear invocation is also stage-scoped. While a focused runtime stage is active, GeeAgent rejects Gear invocations outside that stage's required capability set until the stage advances or is explicitly replanned.

Deterministic stage arguments are part of the runtime plan, not a fallback route. They can only fill the selected stage's declared capability invocation, and they remain visible through normalized tool input and structured results.

Progressive disclosure is still required, but the summary is now an invocation index rather than a forced prelude to every schema call. The agent should first request `detail: "summary"`; if the compact record contains the needed capability and its required arguments are clear, it may invoke directly. It should request `detail: "capabilities"` or `detail: "schema"` only when optional argument types or exact semantics are unclear. GeeAgent should not dump every Gear capability schema into the model context by default.

Current host invocation shape:

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

Current SDK MCP tool shape:

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

The target is that a capability usable in GeeAgent can also be usable from Codex when it is safe and intentionally exported. The implementation model is one generated GeeAgent Codex plugin that points Codex at a local Gee MCP export server.

This does not convert Gears into Codex plugins. Gear remains the authoritative package, native app/widget, data, permission, dependency, and execution boundary. The Codex plugin is only an installable projection containing plugin metadata, MCP configuration, and skills that teach Codex how to call the Gee bridge.

The core export standard lives in `docs/planning/gee-capability-export-standard-v0.md`.

Current implementation status: the agent runtime has manifest-backed export status/list/describe commands, a Codex-facing MCP stdio server, a shared-store external invocation queue, and a local `geeagent-codex` plugin generator. The generator can refresh a local Codex marketplace entry when the caller passes an explicit `marketplace_path`; it does not write marketplace state by default. `gee_status`, `gee_list_capabilities`, and `gee_describe_capability` are backed by manifest projection. `gee_invoke_capability` and `gee_open_surface` create external invocations that GeeAgentMac drains through the live GearHost bridge; `gee_get_invocation` returns the recorded status/result. If GeeAgentMac is not running or cannot drain the queue, Codex gets a pending/failed/blocked/degraded structured result with `fallback_attempted: false`; the MCP server does not execute Gear business logic or run fallback scripts.

Target Codex-facing package shape:

```text
geeagent-codex/
├── .codex-plugin/
│   └── plugin.json
├── .mcp.json
├── skills/
└── assets/
```

Target Gee MCP export tools:

- `gee_status`
- `gee_list_capabilities`
- `gee_describe_capability`
- `gee_invoke_capability`
- `gee_open_surface`
- `gee_get_invocation`

The generated plugin package contains `.codex-plugin/plugin.json`, `.mcp.json`, and `skills/gee-capabilities/SKILL.md`. The `.mcp.json` entry points Codex at `native-runtime codex-mcp`; installed Gear availability remains live data from the MCP server, not static plugin metadata.

Only ready, enabled, policy-allowed, export-eligible Gear capabilities are visible to Codex. Disabled, failed, installing, invalid, blocked, or explicitly non-exported Gears are invisible. The export bridge must not create one Codex tool per Gear feature, duplicate Gear business logic, store provider secrets, or call package-local fallback scripts.

Codex-originated calls are external invocations. They are recorded with caller metadata, normalized input, structured results, artifact references, and failure or recovery reasons. They do not become hidden GeeAgent chat turns. If GeeAgent, GearHost, the intended Gear, a provider channel, a permission, or the live bridge is unavailable, Codex receives a structured pending, failed, blocked, or degraded result with the real reason.

Gear capabilities may declare Codex export policy in `gear.json` under `agent.capabilities[].exports.codex`. A capability that is unsafe or meaningless outside GeeAgent's native surface should mark Codex export as disabled with a reason.

When a Gear, capability, result shape, artifact, permission, provider requirement, dependency behavior, or failure code changes, maintainers must check whether the Codex plugin projection, Gee MCP export schema, generated skills, and plugin metadata also need an update. If a substantial Gear change has no Codex export impact, the final work summary should say so explicitly.

There is no public textual fallback directive for Gear execution. Legacy
directive-shaped records may be normalized for migration safety, but new agent
turns must use the MCP Gear bridge. Missing bridge tools, invalid arguments, or
stale pending host actions must fail with structured reasons instead of
replaying side effects or presenting partial work as complete.

Rules:

- Only `ready + policy-allowed` gears expose capabilities.
- `policy-blocked`, `invalid`, `installing`, `install_failed`, and `blocked` gears are invisible to the agent.
- Capabilities are declared in `gear.json`.
- Gear adapters validate `capability_id` and `args`.
- Gear adapters return structured results. The active agent/LLM owns the final natural-language reply after execution.
- Do not add one global pseudo-tool per gear feature.
- The root agent enters gear surfaces only through the shared bridge.
- First-party Gear business logic remains inside the Gear adapter boundary, not in generic runtime glue.

Capability example:

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
          "Show only videos",
          "Show only starred images",
          "Show mp4 files longer than 3 minutes"
        ]
      }
    ]
  }
}
```

## First-Party Gear Migration

First-party gears should gradually move into real package boundaries.

`media.library`:

- Target: complete Eagle-compatible local media manager.
- Package includes manifest, README, assets, setup metadata, storage notes, and future capability declarations.
- Native Swift implementation may remain host-compiled during migration, but the business boundary must move out of the main app.
- Folder management, filtering, starring, Quick Look, Finder handoff, video / gif hover playback, and live presentation mode belong to the media gear, not the main workbench.
- Agent capabilities include `media.filter`, `media.focus_folder`, and `media.import_files`. `media.import_files` imports local media paths into the authorized media library, restores saved access when possible, and returns item proof for multi-Gear workflows. New files appear in `imported_items`; duplicate files are treated as idempotent success with `action: "import_noop"`, `existing_items`, and `duplicate_paths`; source files that cannot be found appear in `missing_paths`; unsupported files appear in `unsupported_paths`. If no supported imported or existing media item is available, the capability returns structured failure with `code: "gear.media.no_supported_files"` instead of reporting success with `imported_count: 0`. If authorization is missing, it keeps readable paths as `pending_paths`, opens the Media Library surface, and returns a structured failure for the active agent/LLM to explain.

`hyperframes.studio`:

- Target: creative gear requiring Node, npm, Hyperframes, FFmpeg, and FFprobe.
- Must use dependency preflight and setup snapshots.
- Dependency failure affects only Hyperframes.
- Business logic and project data must not enter the main app store.

`media.generator`:

- Target: native media generation Gear adapted from the Dailystarter generator module.
- The Gear supports image generation first through the global Xenodia channel. The current enabled models are `nano-banana-pro` and `gpt-image-2`.
- Nano Banana Pro exposes `n=1`, `async`, `response_format=url`, `aspect_ratio`, `resolution`, `output_format`, and reference images. GPT Image-2 exposes `n=1`, `async`, `response_format=url`, `aspect_ratio`, `resolution`, and reference images; do not send `output_format` or `nsfw_checker` for GPT Image-2.
- Reference image limits are model-specific: Nano Banana Pro allows up to 8 total inputs, and GPT Image-2 allows up to 16 total inputs. Local references must be JPEG, PNG, or WebP and 30MB or smaller.
- Video and audio generation are present as product surfaces and capability placeholders, but V1 must not connect the reference project's non-Xenodia providers. They should return structured unsupported-category results until Xenodia-backed endpoints are available through the global provider channel.
- Reference image upload must not use Qiniu from the reference project. Local references should flow through the Xenodia request or a future global Xenodia storage upload endpoint owned by the main app runtime.
- Task state belongs in `~/Library/Application Support/GeeAgent/gear-data/media.generator/tasks/<task-id>/task.json`.
- Generated results should be cached under `~/Library/Application Support/GeeAgent/gear-data/media.generator/tasks/<task-id>/outputs/` when possible. Preview and download should prefer the Gear-owned local artifact while preserving the remote URL as a fallback.
- Reusable quick prompts belong in `~/Library/Application Support/GeeAgent/gear-data/media.generator/quick-prompts.json`; users can add, edit, delete, and reset them from the native Gear UI.
- Recent reference images from pasted URLs and local files belong in `~/Library/Application Support/GeeAgent/gear-data/media.generator/image-history.json`. The History sheet reuses those references without opening a file picker; generated results remain in task records and output caches instead of being added to reference history automatically.
- Async task polling must resume for `running` or `queued` tasks when the Gear opens or reloads history. Polling should treat Xenodia `success` as completed, `fail` as failed, and read generated URLs from the normalized `result` payload.
- Xenodia image generation is long-running: create, multipart, and task-status requests must use a minimum 30-minute timeout floor. A timed-out status request should keep the local task `running` and continue polling instead of marking the task failed while the provider is still generating.
- The native task workbench supports status filters, model filters, search, starred results, local-cache badges, Finder reveal, large preview, URL copy, user-chosen download, task Apply that restores prompt/model/parameters/references, separate reuse-as-reference, and confirmed task-history deletion.
- Agent capabilities are `media_generator.list_models`, `media_generator.create_task`, and `media_generator.get_task`. Each returns structured task/model data for the active agent/LLM to summarize.

`smartyt.media`:

- Target: native URL media acquisition gear adapted from the SmartYT reference project.
- The Gear accepts a URL, sniffs media metadata, downloads audio, video, or direct image artifacts, and extracts transcript text.
- V1 uses `yt-dlp` for metadata, downloads, and subtitle extraction, and `ffmpeg` / `ffprobe` for media conversion support.
- Transcript extraction should prefer platform subtitles first. If no subtitle is available, the Gear may fall back to local speech tooling such as Whisper when installed. If no speech backend is available, the Gear must return a structured failure that explains the missing transcription backend instead of pretending the conversion completed.
- Job state belongs in `~/Library/Application Support/GeeAgent/gear-data/smartyt.media/`, while downloaded media, extracted subtitles, and transcript text default to `~/Downloads/SmartYT/<job-id>/` unless an agent call provides an explicit `output_dir`.
- Agent capabilities are `smartyt.sniff`, `smartyt.download`, `smartyt.download_now`, and `smartyt.transcribe`. `smartyt.download` queues work for the app UI, while `smartyt.download_now` blocks until artifacts exist and returns `output_paths` for multi-Gear workflows. Direct image URLs, including Twitter/X image URLs with an image extension or a `format=` query hint, are treated as image downloads instead of video downloads. The active agent/LLM owns the final user-facing reply.

`twitter.capture`:

- Target: native Twitter/X content capture gear adapted from the Workbench reference project's Twikit capture flow.
- The Gear accepts one Tweet URL, one List URL plus a limit, or one username / profile URL plus a limit.
- V1 uses a package-local Python sidecar under `apps/macos-app/Gears/twitter.capture/scripts/` and the `twikit` library. The sidecar requires a user-provided authenticated Twitter/X cookie JSON file; GeeAgent does not bundle credentials.
- Task state and captured results belong in `~/Library/Application Support/GeeAgent/gear-data/twitter.capture/tasks/<task-id>/task.json`.
- The native UI may clear all saved Twitter Capture task records from that Gear-owned task database.
- Captured tweet records include ids, URLs, author handles, text, language, counts, tweet timestamps, reply / retweet flags, and normalized media metadata when available.
- The native task surface should display the task creation time, formatted in local time. It should not display tweet publish timestamps in the main result card.
- Agent capabilities are `twitter.fetch_tweet`, `twitter.fetch_list`, and `twitter.fetch_user`. Each capability creates a Gear task, stores the result in the file database, and returns structured task/result data for the active agent/LLM to summarize.
- Missing cookies, expired sessions, rate limits, or Twikit failures must be returned as structured task failures. The Gear must not fake successful capture.

`bookmark.vault`:

- Target: universal information capture Gear.
- The Gear saves arbitrary raw content. If the content contains a URL, it enriches metadata through Twitter/X embed metadata, `yt-dlp` media metadata, or basic web fetch in that order.
- Bookmark records belong in `~/Library/Application Support/GeeAgent/gear-data/bookmark.vault/bookmarks/<bookmark-id>/bookmark.json`.
- Agent capability `bookmark.save` accepts `content` and optional `local_media_paths`. Multi-Gear workflows should pass Media Library imported item paths when a URL's related media has been downloaded and imported.

`wespy.reader`:

- Target: native article reader Gear powered by the external WeSpy Python package.
- The Gear accepts a single article URL, a WeChat public-account album URL for listing, or a WeChat album URL for batch Markdown capture.
- V1 uses a package-local Python sidecar under `apps/macos-app/Gears/wespy.reader/scripts/` and imports the user's installed `wespy` package. GeeAgent does not vendor the WeSpy source into the main runtime.
- Task state and generated file paths belong in `~/Library/Application Support/GeeAgent/gear-data/wespy.reader/tasks/<task-id>/task.json`.
- Agent capabilities are `wespy.fetch_article`, `wespy.list_album`, and `wespy.fetch_album`. Each capability returns structured task data, article counts, generated file paths, article metadata, and structured errors for the active agent/LLM to summarize.
- Missing Python packages, changed site structure, blocked source pages, and network failures must be returned as structured task failures. The Gear must not fake successful article capture.

Information capture workflow:

- Pure text should go straight to `bookmark.save`.
- URL metadata capture should save through `bookmark.save`; use `twitter.capture` or `smartyt.media` only when the user asks for deeper Twitter/media content or when the URL strongly implies media acquisition.
- WeChat public-account article or album URLs should use `wespy.reader` when the user asks for Markdown, article extraction, or batch album capture; use `bookmark.save` only when the user asks to save the URL itself as a bookmark.
- Twitter/X status URLs default to media acquisition unless the user explicitly asks to save metadata only or not to download media. Use `twitter.fetch_tweet` for tweet/media details when needed, then use `smartyt.download_now` for each downloadable video or image URL.
- YouTube URLs should use `smartyt.sniff` as the lightweight duration probe before default download decisions. Default download is allowed only when `duration_seconds` is below 300 seconds; longer or unknown-duration videos should be saved as metadata unless the user explicitly asks to download.
- Strong media acquisition should use `smartyt.download_now` for each media URL, then `media.import_files`, then `bookmark.save` with `local_media_paths`.
- If no media library is authorized, `media.import_files` should preserve downloaded paths as `pending_paths`, open the Media Library surface, and ask the user to choose or create a library before claiming import succeeded. Bookmark Vault may still keep the downloaded paths so the workflow can resume after authorization.
- Runtime stages that depend on `media.import_files` should require `available_count > 0` or non-empty `imported_items` / `existing_items` before claiming media import completed. A bare successful invocation with `imported_count: 0` is not enough proof.

`btc.price`:

- Target: Home widget.
- Must be lightweight, draggable, and refreshable.
- Network access must be declared.
- Widget must not contain full app navigation.

`system.monitor`:

- Target: Home widget.
- Shows local CPU / memory and similar information.
- Must stay lightweight and avoid high-frequency sampling that harms the main app.

## Suggested Directory Upgrade

Target directory:

```text
apps/macos-app/
├── Gears/
│   ├── media.library/
│   ├── hyperframes.studio/
│   ├── smartyt.media/
│   ├── twitter.capture/
│   ├── bookmark.vault/
│   ├── wespy.reader/
│   ├── btc.price/
│   └── system.monitor/
└── Sources/
    ├── GearKit/
    ├── GearHost/
    └── GeeAgentMac/
```

Migration principles:

- Establish `GearKit` and `GearHost` folder boundaries first.
- The first implementation may keep a single SwiftPM target while making file structure and import boundaries clear.
- Later, split `GearKit` and `GearHost` into SwiftPM targets.
- Move bundled gear packages from `Sources/GeeAgentMac/gears` to `apps/macos-app/Gears`.
- The main app should obtain catalog, window, and widget surfaces only through GearHost.

## Implementation Phases

## Phase 0: Boundary Freeze

Goal: prevent new gear business logic from entering the main app.

Deliverables:

- Record existing gear entry points.
- Mark legacy host-compiled adapters.
- Do not add gear business state to `WorkbenchStore`.
- Do not add gear-specific pseudo-tools.

Acceptance:

- New features land inside the gear package, GearHost, or GearKit boundary.
- The main app calls only generic gear APIs.

## Phase 1: Extract GearKit And GearHost

Goal: make the module boundary real in the file structure.

Deliverables:

- Create `Sources/GearKit`.
- Create `Sources/GearHost`.
- Move manifest, dependency, preparation, and registry types.
- Keep current behavior unchanged.
- Add public APIs for scan, list, prepare, open, widget records, and capability records. Policy-disable APIs may remain as internal protection mechanisms, but they are not V1 catalog actions.

Acceptance:

- `swift build` passes.
- Gears catalog behavior stays the same.
- Deleting an unrelated gear does not break app startup.
- Invalid `gear.json` still appears as an install issue.

## Phase 2: Move Bundled Gear Packages

Goal: make development gear packages structurally independent.

Deliverables:

- Create `apps/macos-app/Gears`.
- Move `media.library`, `hyperframes.studio`, `btc.price`, and `system.monitor` package skeletons.
- Update SwiftPM resource copy.
- Registry supports the new bundled root.
- Old root remains compatible during migration.

Acceptance:

- Bundled gears still appear in the catalog.
- If a package is deleted, that gear disappears or shows a clear install issue.
- Merge behavior for same-ID packages in user Application Support is explicit.

## Phase 3: Migrate First-Party Native Gear Boundaries

Goal: make first-party native gear boundaries clear.

Deliverables:

- Register `media.library` adapter in GearHost.
- Register `hyperframes.studio` adapter in GearHost.
- Register Home widgets through widget adapters.
- README explains which parts are still host-compiled during migration.
- Move gear-specific state out of generic stores.

Acceptance:

- The main app does not directly open the MediaLibrary window.
- The main app does not directly know Hyperframes dependency recipes.
- GearHost owns prepare and open.

## Phase 4: Import Local Gear

Goal: support AA-style local sharing.

Deliverables:

- Add `Import Gear...` to the Gears catalog.
- Folder import.
- `.geegear.zip` import.
- Manifest validation.
- Atomic copy into Application Support.
- Same-ID conflict handling.
- Invalid package issue UI.

Acceptance:

- A valid folder import appears in the catalog.
- A valid zip import appears in the catalog.
- An invalid package does not crash and shows an issue.
- Duplicate IDs offer replace / update / cancel.

## Phase 5: Dependency Setup UX

Goal: make dependency setup trustworthy, visible, and recoverable.

Deliverables:

- Setup details sheet.
- Global environment mutation warning.
- Live setup logs.
- Retry install.
- Manual setup message for unsupported installers.
- Per-gear setup snapshot persistence.

Acceptance:

- Opening a dependency-missing gear changes the button to `Checking...`, then `Installing...` or `Retry`.
- Policy-blocked gear does not run setup.
- Failed setup only affects that gear.
- Logs are saved under `gear-data/<gear-id>/logs/`.

## Phase 6: External Process And WebView Entry

Goal: make third-party gears usable without dynamic Swift loading.

Deliverables:

- `external_process` adapter.
- `webview` adapter for local files.
- Process lifecycle supervision.
- Timeout and stop behavior.
- stdout / stderr logs.
- Startup health protocol.

Acceptance:

- A sample AA gear can be copied or imported and opened.
- Process exit is surfaced as gear launch failure.
- V1 WebView gear loads only local package files.

## Phase 7: Agent Control Bridge

Goal: expose ready gear capabilities through one bridge.

Deliverables:

- GearHost provides ready and policy-allowed capability list.
- `gear.invoke` adapter surface plus the SDK `gee` MCP bridge tools.
- Initial `media.library` capability execution.
- Same-run pause / execute / resume continuation between the SDK runtime and GeeAgentMac host actions.

Acceptance:

- Agent sees only ready and policy-allowed capabilities.
- Policy-blocked, failed, installing, or invalid gears are invisible to the agent.
- No gear-specific pseudo-tools are added.
- Missing MCP bridge tools or invalid Gear arguments fail explicitly; GeeAgent does not use fallback task execution to hide runtime issues.

## Quality Gates

Every phase must satisfy:

- `swift build` passes in `apps/macos-app`.
- Gears catalog still opens.
- Missing gear does not break main app startup.
- Invalid `gear.json` appears as an install issue.
- Policy-blocked gear does not run dependency setup.
- Policy-blocked gear does not expose capabilities.
- Gear-specific data does not enter `WorkbenchStore`.
- Gear UI follows native macOS experience.
- Public docs are updated in English, Simplified Chinese, and Japanese.
- Gear capability changes check the Codex plugin projection and update export metadata, MCP schema, generated skills, or plugin metadata when needed.

Package and import phases must also satisfy:

- Path traversal is rejected.
- Folder name must match manifest id.
- Duplicate ID has explicit user choice.
- Import is atomic or rolls back cleanly.
- Dependency failure has per-gear logs.

## Non-Goals For V1

V1 does not include:

- Remote marketplace.
- Payments, ratings, reviews.
- Mandatory developer signing.
- Automatic remote update.
- Cross-gear private API.
- Background daemons.
- Dynamic Swift source loading from user-copied folders.
- One agent tool per gear feature.
- Silent dependency installation at app startup.

## Developer Workflow

Recommended local gear development flow:

- Create a `<gear-id>/` folder.
- Add `gear.json`.
- Add `README.md`.
- Add `assets/`, `setup/`, `scripts/`, `src/`, or `app/`.
- Declare entry, permissions, dependencies, and agent capabilities.
- During development, place it under `apps/macos-app/Gears/<gear-id>/`.
- For distribution, package it as a folder or `.geegear.zip`.
- The user copies it to `~/Library/Application Support/GeeAgent/gears/<gear-id>/` or imports it through `Import Gear...`.
- GearHost scan makes it appear in the Gears catalog.
- Opening or enabling it runs dependency preflight.
- Once ready, it opens an app window or renders a Home widget.

Minimal shareable package:

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

Minimal `.geegear.zip` should extract into one top-level folder:

```text
aa.cool.gear.geegear.zip
└── aa.cool.gear/
    ├── gear.json
    └── README.md
```

## Immediate Recommendation

Start with Phase 1 and Phase 2.

Do not start with marketplace, signing, remote update, or the full agent bridge. The most valuable next step is to make the local module boundary real:

- Extract `GearKit` and `GearHost` directories.
- Move bundled gear packages to `apps/macos-app/Gears`.
- Centralize native and widget adapter registration in GearHost.
- Keep current user behavior unchanged while making the package boundary explicit.

This gives GeeAgent a credible platform base without overbuilding the ecosystem: gears become independent, optional, manageable, copy-installable, and ready for future agent control.
