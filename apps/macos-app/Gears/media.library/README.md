# Media Library Gear Package

`media.library` is an atmosphere gear for Eagle-compatible local media
management.

Current implementation status:

- Manifest and package metadata live in this folder.
- Native Swift implementation is currently compiled from
  `Sources/GeeAgentMac/Modules/MediaLibrary/`.
- Video hover/live previews keep thumbnails visible until the player has a
  displayable frame, then loop through `AVPlayerLooper` for smoother playback.
- Video items expose an `Edit Video` action from the tile context menu and the
  inspector, opening the media library's internal native video editor window.
- The target package standard is to move the gear implementation, assets, setup
  files, and private dependencies under this folder so deleting this folder fully
  removes the app after restart.

Expected package layout:

```text
media.library/
├── gear.json
├── README.md
├── assets/
├── setup/
├── scripts/
└── src/
```

This gear currently has no external dependency install plan.
