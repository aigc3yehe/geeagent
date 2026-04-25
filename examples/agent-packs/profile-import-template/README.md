# profile-import-template

This directory is a complete `Agent Definition v2` template that can be copied, renamed, edited locally, and then imported through GeeAgent's `Agents` page.

## Required files

- `agent.json`
- `identity-prompt.md`
- `soul.md`
- `playbook.md`
- one visual asset referenced by `agent.json`

## How to customize

1. Copy this folder to a new location on your machine.
2. Edit `agent.json`:
   - change `id`, `name`, `tagline`, and `version`
   - keep `identity_prompt_path` pointed at `identity-prompt.md`
   - keep `soul_path` and `playbook_path` pointed at the layered context files unless you rename them
   - update `appearance` if you want a different image, video, or Live2D bundle
3. Edit `identity-prompt.md`, `soul.md`, and `playbook.md` with your agent definition.
4. Optionally edit `tools.md`, `memory.md`, and `heartbeat.md`.
5. Replace `appearance/hero.png` with your own image if you stay on `static_image`.

## Switching appearance kinds

- `static_image`
  - point `appearance.asset_path` at an image inside this folder, for example `appearance/hero.png`
- `video`
  - change `kind` to `video`
  - point `appearance.asset_path` at a local video such as `appearance/loop.mp4`
- `live2d`
  - change `kind` to `live2d`
  - point `appearance.bundle_path` at either:
    - a `*.model3.json` file
    - or a folder inside this pack that contains the `*.model3.json`

## What GeeAgent currently recognizes for Live2D

For import validation:

- GeeAgent accepts `appearance.bundle_path` pointing at:
  - a `*.model3.json` file
  - or a folder that contains the `*.model3.json`
- the referenced Live2D files must stay inside the package root
- the package can be imported from either a folder or a `.zip`

For runtime loading:

- the standard Cubism resources referenced from `model3.json` can live next to the model, including:
  - textures
  - `*.motion3.json`
  - `*.exp3.json`
  - physics files
  - pose files

For motion and expression discovery in GeeAgent:

- `model3.json -> FileReferences -> Motions`
  - the `Idle` group is treated as `poses`
  - other motion groups are treated as `actions`
- optional `*.vtube.json` files in the same bundle folder
  - `FileReferences.IdleAnimation` is treated as the default pose
  - `FileReferences.IdleAnimationWhenTrackingLost` is treated as a fallback pose
  - `Hotkeys[*].File = *.motion3.json`
    - `Action = ChangeIdleAnimation`, looping motions, or files matching the idle/fallback pose are treated as `poses`
    - other motion files are treated as `actions`
  - `Hotkeys[*].File = *.exp3.json` is treated as an `expression`
- recursive scan fallback
  - any additional `*.motion3.json` files found in the bundle are added as `actions`
  - any additional `*.exp3.json` files found in the bundle are added as `expressions`

In the current UI this roughly maps to:

- `poses`: long-lived idle/stance changes
- `actions`: one-shot motions
- `expressions`: temporary state / expression changes

Recommended Live2D package layout:

```text
appearance/
  model/
    character.model3.json
    textures/
    motions/
    expressions/
    character.vtube.json        # optional
```

## Importing from GeeAgent

- Import either the full folder or a `.zip` created from the full folder.
- Do not zip only the files inside the folder. Zip the folder itself so GeeAgent can preserve the package root correctly.
