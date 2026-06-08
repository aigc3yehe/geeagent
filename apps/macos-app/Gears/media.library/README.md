# Media Library Gear Package

`media.library` is an atmosphere gear for Eagle-compatible local media
management.

Current implementation status:

- Manifest and package metadata live in this folder.
- Native Swift implementation is currently compiled from
  `Sources/GeeAgentMac/Modules/MediaLibrary/`.
- Video hover/live previews keep thumbnails visible until the player has a
  displayable frame, then loop through `AVPlayerLooper` for smoother playback.
  Dynamic showcase still starts every visible video/GIF preview; player setup
  and playback are scheduled after SwiftUI view updates, staggered across a
  short bounded window, and watched for stalled first-frame startup so opening a
  dense video range does not synchronously start every decoder from the render
  pass. Viewport-size and gallery-layout changes such as entering viewer mode
  or switching equal-height / waterfall layout recompute dynamic preview
  visibility even when individual tile frames do not move. Preview loops skip a
  delayed video-track lead-in when a trimmed MP4 has audio from 0s but no video
  frame until later in the timeline. In normal gallery mode, dynamic showcase
  hides autoplaying media cards' on-card labels, badges, star controls, and
  gradient overlays so the preview stays visually clean.
- Video items expose an `Edit Video` action from the tile context menu and the
  inspector, opening the media library's internal native video editor window.
- Viewer mode uses a quiet auto-hiding bottom toolbar that reappears on pointer
  activity, with slightly roomier spacing and rounding for immersive video
  tiles.
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
