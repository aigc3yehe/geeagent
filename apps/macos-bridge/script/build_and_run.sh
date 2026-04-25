#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="GeeAgentMac"
BUNDLE_ID="com.geeagent.GeeAgentMac"
MIN_SYSTEM_VERSION="15.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
SOURCE_RESOURCES="$ROOT_DIR/Resources"
SOURCE_GEARS="$ROOT_DIR/Sources/GeeAgentMac/gears"
REPO_ROOT="$(cd "$ROOT_DIR/../.." && pwd)"
ROOT_BACKGROUND="$REPO_ROOT/bg.png"
RUNTIME_BRIDGE_MANIFEST="$REPO_ROOT/apps/runtime-bridge/Cargo.toml"
RUNTIME_BRIDGE_BIN="$REPO_ROOT/apps/runtime-bridge/target/debug/shell_runtime_bridge"

stop_running_app_processes() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  pkill -f "$APP_RESOURCES/shell_runtime_bridge serve" >/dev/null 2>&1 || true
  pkill -f "$REPO_ROOT/apps/agent-runtime-bridge/dist/index.js" >/dev/null 2>&1 || true
  pkill -f "$REPO_ROOT/apps/agent-runtime-bridge/node_modules/@anthropic-ai/claude-agent-sdk" >/dev/null 2>&1 || true
}

stop_running_app_processes

swift build --package-path "$ROOT_DIR"
BUILD_BINARY="$(swift build --package-path "$ROOT_DIR" --show-bin-path)/$APP_NAME"
cargo build --manifest-path "$RUNTIME_BRIDGE_MANIFEST" --bin shell_runtime_bridge

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$RUNTIME_BRIDGE_BIN" "$APP_RESOURCES/shell_runtime_bridge"
if [ -d "$SOURCE_RESOURCES" ]; then
  cp -R "$SOURCE_RESOURCES"/. "$APP_RESOURCES"/
fi
if [ -d "$SOURCE_GEARS" ]; then
  cp -R "$SOURCE_GEARS" "$APP_RESOURCES/gears"
fi
if [ -f "$ROOT_BACKGROUND" ] && [ ! -f "$APP_RESOURCES/bg.png" ]; then
  cp "$ROOT_BACKGROUND" "$APP_RESOURCES/bg.png"
fi
chmod +x "$APP_BINARY"
chmod +x "$APP_RESOURCES/shell_runtime_bridge"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

open_app() {
  auto_allow_removable_volume_prompt
  /usr/bin/open -n "$APP_BUNDLE"
}

auto_allow_removable_volume_prompt() {
  /usr/bin/osascript >/dev/null 2>&1 <<'APPLESCRIPT' &
set candidateProcesses to {"GeeAgentMac", "SecurityAgent", "CoreServicesUIAgent"}
set promptNeedle to "would like to access files on a removable volume"

tell application "System Events"
  repeat 80 times
    if UI elements enabled then
      repeat with processName in candidateProcesses
        set procName to contents of processName
        if exists process procName then
          tell process procName
            repeat with theWindow in windows
              set windowText to ""
              try
                repeat with theText in static texts of theWindow
                  set windowText to windowText & " " & (value of theText as text)
                end repeat
              end try

              if windowText contains promptNeedle then
                if exists button "Allow" of theWindow then
                  click button "Allow" of theWindow
                  return
                end if
              end if
            end repeat
          end tell
        end if
      end repeat
    end if
    delay 0.25
  end repeat
end tell
APPLESCRIPT
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
