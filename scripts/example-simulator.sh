#!/usr/bin/env bash
# Installs the built example app on the given simulator, launches it, waits, and
# captures evidence: a screenshot and — when idb is installed — the accessibility
# tree as JSON, which carries every on-screen text (Tabris renders console output
# and results as labels). The simulator is addressed by UDID and is never
# booted-from-scratch, shut down or deleted here.
#
# The app is launched detached on purpose: `simctl launch --console` would take
# the JavaScript console down with it when the attached simctl process ends, and
# Tabris does not write console.log output to stdout or the unified log anyway.
set -euo pipefail

USAGE="usage: example-simulator.sh <path-to.app> <simulator-udid> [wait-seconds]"
APP_PATH="${1:?$USAGE}"
UDID="${2:?$USAGE}"
WAIT_SECONDS="${3:-25}"
LOG_DIR="/tmp/claude"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
SCREENSHOT="$LOG_DIR/example-$TIMESTAMP.png"
ACCESSIBILITY_TREE="$LOG_DIR/example-ax-$TIMESTAMP.json"

mkdir -p "$LOG_DIR"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist")"

xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP_PATH"
xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID"

sleep "$WAIT_SECONDS"
xcrun simctl io "$UDID" screenshot "$SCREENSHOT"
if command -v idb > /dev/null 2>&1; then
    idb ui describe-all --udid "$UDID" > "$ACCESSIBILITY_TREE" 2> /dev/null || echo "idb describe-all failed" >&2
fi

echo "BUNDLE_ID=$BUNDLE_ID"
echo "SCREENSHOT=$SCREENSHOT"
echo "ACCESSIBILITY_TREE=$ACCESSIBILITY_TREE"
