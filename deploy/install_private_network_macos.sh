#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-nanobot-gateway}"
REPO_PATH="${REPO_PATH:-$HOME/storage/nanobot}"
CONFIG_PATH="${CONFIG_PATH:-$HOME/.nanobot/config.json}"
BUILD_DIR="${BUILD_DIR:-${TMPDIR:-/tmp}/nanobot-private-network-build}"
SKIP_SERVICE_RESTART="${SKIP_SERVICE_RESTART:-0}"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_AGENTS_DIR/${SERVICE_NAME}.plist"
LABEL="${SERVICE_NAME}"

write_step() {
  printf '\n==> %s\n' "$1"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Command not found: $1" >&2
    exit 1
  }
}

write_step "Checking prerequisites"
[ -d "$REPO_PATH" ] || { echo "Repo path not found: $REPO_PATH" >&2; exit 1; }
[ -f "$REPO_PATH/pyproject.toml" ] || { echo "pyproject.toml not found under repo path: $REPO_PATH" >&2; exit 1; }
[ -f "$CONFIG_PATH" ] || { echo "Config file not found: $CONFIG_PATH" >&2; exit 1; }
require_cmd uv
require_cmd launchctl

write_step "Stopping launch agent if it exists"
launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true

write_step "Checking current nanobot version"
if command -v nanobot >/dev/null 2>&1; then
  echo "Current nanobot command: $(command -v nanobot)"
  nanobot --version || true
else
  echo "nanobot command not currently found in PATH"
fi

write_step "Building wheel from local source"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
uv build --wheel --out-dir "$BUILD_DIR" "$REPO_PATH"
WHEEL_PATH="$(ls -t "$BUILD_DIR"/nanobot_ai-*.whl | head -n 1)"
[ -n "$WHEEL_PATH" ] || { echo "Wheel build did not produce a nanobot wheel under: $BUILD_DIR" >&2; exit 1; }
echo "Built wheel: $WHEEL_PATH"

write_step "Uninstalling current uv tool install of nanobot-ai"
uv tool uninstall nanobot-ai || true

write_step "Installing nanobot-ai from built wheel"
uv tool install "$WHEEL_PATH"

write_step "Verifying local installation"
NANOBOT_CMD="$(command -v nanobot)"
echo "New nanobot command: $NANOBOT_CMD"
"$NANOBOT_CMD" --version

write_step "Running direct gateway smoke test with explicit config"
"$NANOBOT_CMD" gateway --config "$CONFIG_PATH" >/dev/null 2>&1 &
SMOKE_PID=$!
sleep 8
if ! kill -0 "$SMOKE_PID" >/dev/null 2>&1; then
  wait "$SMOKE_PID" || true
  echo "Smoke test failed: nanobot gateway exited early" >&2
  exit 1
fi
kill "$SMOKE_PID" >/dev/null 2>&1 || true
wait "$SMOKE_PID" 2>/dev/null || true
sleep 2

write_step "Writing launch agent plist"
mkdir -p "$LAUNCH_AGENTS_DIR"
cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$NANOBOT_CMD</string>
        <string>gateway</string>
        <string>--config</string>
        <string>$CONFIG_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>WorkingDirectory</key>
    <string>$HOME</string>
    <key>StandardOutPath</key>
    <string>$HOME/.nanobot/service-logs/${SERVICE_NAME}.out.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.nanobot/service-logs/${SERVICE_NAME}.err.log</string>
</dict>
</plist>
EOF
mkdir -p "$HOME/.nanobot/service-logs"

if [ "$SKIP_SERVICE_RESTART" != "1" ]; then
  write_step "Loading launch agent"
  launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
  launchctl enable "gui/$(id -u)/$LABEL"
  launchctl kickstart -k "gui/$(id -u)/$LABEL"
  sleep 6

  write_step "Checking service status"
  launchctl print "gui/$(id -u)/$LABEL"
fi

write_step "Done"
echo "LaunchAgent: $PLIST_PATH"
echo "Repo: $REPO_PATH"
echo "Config: $CONFIG_PATH"
