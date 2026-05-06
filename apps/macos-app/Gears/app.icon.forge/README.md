# App Icon Forge

Native macOS Gear for turning one source image into icon packages.

macOS app icon output:

- `AppIcon.icns`
- `AppIcon.iconset`
- `AppIcon.appiconset`
- `preview-1024.png`
- `icon-export.json`

The renderer centers and crops the input image to a square, draws it inside a
rounded macOS-style safe area, leaves transparent canvas padding, and generates
the standard icon sizes used by `iconutil` and Xcode.

Gear list icon output:

- `assets/icon.png`
- `preview-780x580.png`
- `gear-icon.json`

The simple Gear icon spec is `gee.gear.icon.v1`: a 780x580 PNG tile at
`assets/icon.png`, referenced from `gear.json` as `"icon": "assets/icon.png"`.
It is currently intended only for the Gears catalog/list surface, whose display
slot is a horizontal tile rather than a square app icon.
