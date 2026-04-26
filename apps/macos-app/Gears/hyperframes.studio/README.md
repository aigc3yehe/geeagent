# Hyperframes Studio Gear Package

`hyperframes.studio` is an atmosphere gear for HTML-to-video project creation,
timeline editing, rendering, and review.

Current implementation status:

- Manifest and dependency plan live in this folder.
- Native Swift shell implementation is currently compiled from
  `Sources/GeeAgentMac/Modules/HyperframesStudio/`.
- Runtime dependencies are declared in `gear.json` and prepared on open through
  the gear dependency service.
- The target package standard is to keep all gear-specific source, assets,
  setup files, and private dependencies under this folder.

Expected package layout:

```text
hyperframes.studio/
├── gear.json
├── README.md
├── assets/
├── setup/
├── scripts/
└── src/
```
