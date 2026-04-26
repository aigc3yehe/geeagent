#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="GeeAgentMac"
BUNDLE_ID="com.geeagent.GeeAgentMac"
MIN_SYSTEM_VERSION="15.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
SWIFT_BUILD_DIR="$ROOT_DIR/.swift-build"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
SOURCE_RESOURCES="$ROOT_DIR/Resources"
SOURCE_GEARS="$ROOT_DIR/Gears"
REPO_ROOT="$(cd "$ROOT_DIR/../.." && pwd)"
AGENT_RUNTIME="$REPO_ROOT/apps/agent-runtime"
SOURCE_CONFIG="$REPO_ROOT/config"
SDK_CLI="$AGENT_RUNTIME/node_modules/@anthropic-ai/claude-agent-sdk-darwin-arm64/claude"
ROOT_BACKGROUND="$REPO_ROOT/bg.png"

stop_running_app_processes() {
  quit_bundle_id "io.geeagent.desktop"
  terminate_process_name "$APP_NAME"
  terminate_process_pattern "[g]eeagent_desktop_shell"
  terminate_process_pattern "[i]o.geeagent.desktop/runtime/native-runtime/index.mjs snapshot"
  terminate_process_pattern "[i]o.geeagent.desktop/runtime/native-runtime/index.mjs serve"
  terminate_process_pattern "$REPO_ROOT/apps/agent-runtime/dist/native-runtime/index.mjs snapshot"
  terminate_process_pattern "$REPO_ROOT/apps/agent-runtime/dist/native-runtime/index.mjs serve"
  terminate_process_pattern "$REPO_ROOT/apps/agent-runtime/dist/native-runtime/index.js snapshot"
  terminate_process_pattern "$REPO_ROOT/apps/agent-runtime/dist/native-runtime/index.js serve"
  terminate_process_pattern "$REPO_ROOT/apps/agent-runtime/src/native-runtime/index.ts serve"
  terminate_process_pattern "$REPO_ROOT/apps/agent-runtime/dist/index.js"
  terminate_process_pattern "$REPO_ROOT/apps/agent-runtime/node_modules/@anthropic-ai/claude-agent-sdk"
}

quit_bundle_id() {
  local bundle_id="$1"
  /usr/bin/osascript >/dev/null 2>&1 <<APPLESCRIPT || true
try
  tell application id "$bundle_id" to quit
end try
APPLESCRIPT
}

terminate_process_name() {
  local name="$1"
  pkill -x "$name" >/dev/null 2>&1 || true
}

terminate_process_pattern() {
  local pattern="$1"
  local pids
  pids="$(pgrep -f "$pattern" 2>/dev/null || true)"
  if [ -z "$pids" ]; then
    return 0
  fi
  while IFS= read -r pid; do
    if [ -n "$pid" ] && [ "$pid" != "$$" ]; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
  done <<<"$pids"
}

run_swiftpm_command() {
  local output_file
  local command_status
  output_file="$(mktemp -t geeagent-swiftpm.XXXXXX)"

  set +e
  "$@" >"$output_file" 2>&1
  command_status=$?
  set -e

  if [ "$command_status" -eq 0 ]; then
    cat "$output_file"
    rm -f "$output_file"
    return 0
  fi

  if grep -q "unknown build description" "$output_file"; then
    echo "SwiftPM cache was invalid. Removing $SWIFT_BUILD_DIR and retrying once..." >&2
    rm -rf "$SWIFT_BUILD_DIR"
    rm -f "$output_file"
    "$@"
    return $?
  fi

  cat "$output_file" >&2
  rm -f "$output_file"
  return "$command_status"
}

capture_swiftpm_command() {
  local output_file
  local command_status
  output_file="$(mktemp -t geeagent-swiftpm.XXXXXX)"

  set +e
  "$@" >"$output_file" 2>&1
  command_status=$?
  set -e

  if [ "$command_status" -eq 0 ]; then
    cat "$output_file"
    rm -f "$output_file"
    return 0
  fi

  if grep -q "unknown build description" "$output_file"; then
    echo "SwiftPM cache was invalid. Removing $SWIFT_BUILD_DIR and retrying once..." >&2
    rm -rf "$SWIFT_BUILD_DIR"
    rm -f "$output_file"
    "$@"
    return $?
  fi

  cat "$output_file" >&2
  rm -f "$output_file"
  return "$command_status"
}

stop_running_app_processes

npm run build --prefix "$AGENT_RUNTIME"
run_swiftpm_command swift build --package-path "$ROOT_DIR" --scratch-path "$SWIFT_BUILD_DIR"
BUILD_BIN_DIR="$(capture_swiftpm_command swift build --package-path "$ROOT_DIR" --scratch-path "$SWIFT_BUILD_DIR" --show-bin-path)"
BUILD_BINARY="$BUILD_BIN_DIR/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
if [ -d "$SOURCE_RESOURCES" ]; then
  cp -R "$SOURCE_RESOURCES"/. "$APP_RESOURCES"/
fi
if [ -d "$SOURCE_GEARS" ]; then
  cp -R "$SOURCE_GEARS" "$APP_RESOURCES/Gears"
fi
mkdir -p "$APP_RESOURCES/agent-runtime/native-runtime"
cp "$AGENT_RUNTIME/dist/native-runtime/index.mjs" "$APP_RESOURCES/agent-runtime/native-runtime/index.mjs"
if [ -f "$SDK_CLI" ]; then
  mkdir -p "$APP_RESOURCES/agent-runtime/claude-sdk"
  cp "$SDK_CLI" "$APP_RESOURCES/agent-runtime/claude-sdk/claude"
  chmod +x "$APP_RESOURCES/agent-runtime/claude-sdk/claude"
fi
if [ -d "$SOURCE_CONFIG" ]; then
  mkdir -p "$APP_RESOURCES/agent-runtime/config"
  cp "$SOURCE_CONFIG"/model-routing.toml "$APP_RESOURCES/agent-runtime/config/model-routing.toml"
  cp "$SOURCE_CONFIG"/chat-runtime.toml "$APP_RESOURCES/agent-runtime/config/chat-runtime.toml"
fi
if [ -f "$ROOT_BACKGROUND" ] && [ ! -f "$APP_RESOURCES/bg.png" ]; then
  cp "$ROOT_BACKGROUND" "$APP_RESOURCES/bg.png"
fi
chmod +x "$APP_BINARY"

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
