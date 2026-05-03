# App Icon Forge

Native macOS Gear for turning one source image into a complete app icon package:

- `AppIcon.icns`
- `AppIcon.iconset`
- `AppIcon.appiconset`
- `preview-1024.png`
- `icon-export.json`

The renderer centers and crops the input image to a square, draws it inside a
rounded macOS-style safe area, leaves transparent canvas padding, and generates
the standard icon sizes used by `iconutil` and Xcode.
