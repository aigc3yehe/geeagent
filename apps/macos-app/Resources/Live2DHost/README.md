# Live2D Host

This directory is served to `PersonaLive2DWebView` via `WKWebView.loadFileURL`. It renders the
active persona's Live2D bundle on the home hero surface.

## Files

- `index.html` — minimal transparent shell. Pointer events are disabled so the SwiftUI launcher
  owns interaction.
- `app.js` — reads `window.geeLive2DConfig` (injected by Swift at `atDocumentStart`) and:
  1. Draws a soft fallback scene on `<canvas id="fallback">` so the hero never blanks out.
  2. Tries to fetch the imported `*.model3.json` and render its first texture as a static preview,
     so imported personas have an immediate visible effect even before the Cubism runtime is
     vendored.
  3. Best-effort loads local runtime scripts from this folder and, if `window.geeLive2DBootstrap`
     or `window.LAppDelegate` becomes available, hands control over to the real Live2D runtime.

`window.geeLive2DConfig` contains:

- `modelUrl` — a `file://` URL pointing at the imported `*.model3.json`. Use this when handing the
  model to Cubism (XHR/fetch resolve cleanly because the host page is already on a `file://`
  origin rooted at a common ancestor that contains both `Live2DHost/` and the persona bundle).
- `modelPath` — the raw POSIX path. Provided for code that needs to do its own I/O.
- `debug` — boolean flag, reserved.
- `README.md` — this file.

## Adding the Cubism runtime

The Cubism Core and Cubism Web Framework are third-party licensed and **intentionally not
tracked in this repo**. To enable real Live2D rendering locally:

1. Obtain a Cubism SDK build (see <https://www.live2d.com/en/sdk/download/>).
2. Copy the following into this directory without renaming:
   - `cubismcore.min.js`
   - your built runtime, which should either:
     - define `window.geeLive2DBootstrap(config, host)` and return an object with optional
       `pause()`, `resume()`, and `stop()` methods, or
     - define `window.LAppDelegate` with `initialize()` / `run(modelUrl)` compatibility.
   - Any runtime dependencies the SDK requires (for example `Framework.js` and sample glue files).
3. Drop the resulting files into `apps/macos-app/Resources/Live2DHost/` — `app.js` will try to
   load the known script names automatically on startup.

Ship-gate: do not check vendored SDK files into this repo until legal has reviewed the
redistribution terms for our release. The repo-default experience therefore stays on the
texture-preview fallback until those files are provided locally.

## Persona asset layout

Personas store their Live2D bundles under:

```
~/Library/Application Support/GeeAgent/Personas/<personaId>/live2d/<bundle-uuid>/
    ├── *.model3.json
    └── ... (textures, motions, expressions, ...)
```

The `*.model3.json` path is what ends up in `AgentProfile.appearance = Live2D { bundle_path }`.
`app.js` reads that path from `window.geeLive2DConfig.modelUrl`.

## WebKit file-URL sandbox

`PersonaLive2DWebView` calls `loadFileURL(_:allowingReadAccessTo:)` with a directory that is the
deepest common ancestor of (a) the app's `Live2DHost/` directory and (b) the persona's
`live2d/<bundle-uuid>/` directory. Without that widening, WebKit would refuse all cross-directory
reads from the file:// origin and Cubism's relative fetches (textures, motions, physics, expression
files) would silently fail. See `PersonaLive2DWebView.Coordinator.readAccessRoot(hostDir:bundleDir:)`
and its tests for the contract.
