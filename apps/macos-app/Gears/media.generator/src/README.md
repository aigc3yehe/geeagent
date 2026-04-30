# Source Boundary

The current first-party native implementation is compiled in
`apps/macos-app/Sources/GeeAgentMac/Modules/MediaGenerator`.

The Gear package remains the manifest, asset, setup, and future portable source
boundary. Business logic should move here as the Gear package runtime matures.
