# Agent Persona

## Purpose

GeeAgent is not only a generic agent runtime. It supports agent personas as a product layer on top of the shared runtime. A persona defines how an agent is identified, how it should behave, what visual presence it has, and what local capabilities it may recommend or constrain.

The persona layer must remain separate from runtime execution truth. Runs, sessions, events, approvals, task continuation, and tool execution belong to the phase-2 runtime spine.

## Current Status

The current persona system is a foundation, not a finished persona marketplace.

- Persona definitions can be imported from local folders or zip archives.
- Imported personas are copied into a local persona workspace.
- The active persona is exposed in runtime snapshots.
- The active persona affects the SDK system prompt.
- Explicit skill source metadata can be exposed to the prompt without injecting full `SKILL.md` bodies.
- Persona tool allow-lists are enforced by the native runtime tool dispatcher.
- Persona visuals drive the native home surface when visual assets are present.

## Agent Definition v2

The main public format is `Agent Definition v2`.

Required package shape:

```text
agent.json
identity-prompt.md
soul.md
playbook.md
appearance/
```

Optional files:

```text
tools.md
memory.md
heartbeat.md
skills/
README.md
LICENSE
```

Visual resources are optional. A persona may omit the visual layer entirely and fall back to the default abstract surface.

## Manifest Fields

`agent.json` is a small declarative manifest. It should reference files instead of storing long prompt text directly.

Required fields:

- `definition_version`: must be `2`.
- `id`: stable persona id.
- `name`: display name.
- `tagline`: short summary.
- `identity_prompt_path`: path to the identity layer.
- `soul_path`: path to the voice and personality layer.
- `playbook_path`: path to the behavior layer.
- `appearance`: optional visual definition.
- `source`: usually `module_pack` or `user_created`.
- `version`: human-readable version.

Common optional fields:

- `tools_context_path`
- `memory_seed_path`
- `heartbeat_path`
- `skills`
- `allowed_tool_ids`

## Layered Context

GeeAgent compiles persona context in this order:

- `identity-prompt.md`: role, responsibilities, and task boundary.
- `soul.md`: personality, tone, and communication posture.
- `playbook.md`: work rules, autonomy posture, escalation, and approval behavior.
- `tools.md`: local tool-use hints, if declared.
- `memory.md`: initial portable memory seed, if declared.
- `heartbeat.md`: recurring behavioral guidance, if declared.

The compiled result becomes the persona's runtime `personality_prompt`.

## Skill Sources

GeeAgent only recognizes skill folders that the user explicitly adds. It does not automatically scan all local agent skill directories.

Settings can add system-level skill source folders. These sources apply to every persona and are hot-updated when the runtime builds a new snapshot or prompt.

The Agents detail view can add persona-level skill source folders. These sources apply only to that persona. Persona-level skill lists refresh when the persona is reloaded.

A skill source may be either a single skill folder containing `SKILL.md`, or a collection folder whose direct child folders contain `SKILL.md`.

The runtime exposes only skill metadata to the active agent prompt, such as name, description, scope, and file path. Full `SKILL.md` contents are not injected automatically. If the agent needs the full instructions, it must inspect the skill file through the normal runtime file/tool path and permission model. GeeAgent skill metadata is not an SDK `Skill` tool registration; when `skill_file_path` is available, the agent should read that file directly instead of invoking an SDK skill alias.

Skill availability is context, not a security sandbox. Tool execution is still governed by GeeAgent's runtime permissions, approval flow, and persona `allowed_tool_ids`.

## Visual Layer

Supported persona visual kinds:

- `live2d`: references a Cubism `*.model3.json` bundle descriptor.
- `video`: references a local looping video.
- `static_image` or `image`: references an image asset.

The visual layer may declare all three at the same time. GeeAgent applies them in this priority order:

- Live2D;
- video;
- image.

If all persona visual fields are missing, the app uses its default abstract surface.

On the Home surface, GeeAgent can expose a compact visual switcher for the active persona. It shows only the visual modes that have corresponding files, plus the abstract mode. For example, if a persona has Live2D and image assets but no video, the video option is hidden.

The `image` asset is only the image display mode. It is not the Live2D background.

The visual layer may also declare a `global_background`. The global background is rendered as a full-coverage home background behind the persona visual, including Live2D. It supports:

- video;
- image.

The global background priority is video first, then image.

If a Live2D persona does not declare `global_background`, GeeAgent renders Live2D over the default abstract home background.

Live2D personas can expose poses, actions, expressions, viewport position, and scale through the local UI.

## Runtime Influence

Persona influence is intentionally light.

A persona may affect:

- system prompt content;
- explicitly configured skill metadata;
- tool allow-list recommendations and constraints;
- visual presentation;
- local appearance interaction state.

The core runtime prompt still owns Gee's default task boundary. Gee is not coding-first by default: unless the user explicitly asks for code development, bug fixing, refactoring, or code edits, the agent should not satisfy ordinary app control, file management, research, or configuration requests by modifying local project source code. This boundary does not prevent scripts, data-processing helpers, inspection utilities, or temporary automation code when those are necessary implementation details.

A persona must not own:

- run lineage;
- session continuation;
- approval state;
- event truth;
- task persistence;
- provider routing truth;
- host security policy.

## Local Storage

Runtime profiles are stored under the GeeAgent config directory. Persona workspaces are stored under a local `Personas` directory. The active persona id is runtime state, not part of the persona package itself.

Imported profile files remain editable after import. Reload reads the local workspace again and regenerates the runtime profile. If reload fails, the last known good profile remains active.

## Tool Allow-Lists

`allowed_tool_ids` can constrain native runtime tools for a persona.

If the field is omitted, the persona uses workspace defaults. If the field is present, only matching tools are allowed. Patterns may use a trailing `*` prefix match, such as `navigate.*`.

The frontend cannot elevate a persona's non-Gee tool permissions. The native runtime resolves the active persona and enforces the allow-list before execution for ordinary local tools such as shell and file operations.

Gee host-managed bridge tools, such as `gee.app.*` and `gee.gear.*`, are treated as first-party product controls rather than persona-owned generic tools. They bypass persona allow-list filtering, but they still validate enabled gears, declared capabilities, policy state, and arguments inside the Gee host bridge.

## Import, Reload, Delete

Import:

- validate the package;
- copy the full package into the local persona workspace;
- compile layered context;
- generate a normalized runtime profile;
- refresh desktop and CLI surfaces.

Reload:

- re-read the local persona workspace;
- recompile the layered context;
- refresh persona-level skill source metadata;
- keep the previous loaded profile if validation fails.

Delete:

- remove the local workspace;
- remove the generated runtime profile;
- first-party personas cannot be deleted.

## Boundaries

Persona packages are declarative. They should not contain executable scripts, native binaries, application bundles, or machine-specific runtime state.

Current public docs describe the implemented foundation. Persona market distribution, signing, trust metadata, automation heartbeat execution, and broader multi-profile orchestration remain future work.
