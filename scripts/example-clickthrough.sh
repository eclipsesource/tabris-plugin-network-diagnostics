#!/usr/bin/env bash
# Drives the built example app on a booted simulator through idb (Facebook's
# iOS debug bridge): installs and launches the app, runs a diagnosis, cancels a
# second one, disposes the object during a third, opens the share sheet, and
# checks what the accessibility tree shows after every step. Tabris exposes
# widget texts as accessibility labels (widget ids are not exposed), so every
# element is located by its visible text. Screenshots and accessibility dumps
# land in /tmp/claude; the exit code is 0 only when every check passed.
set -euo pipefail

USAGE="usage: example-clickthrough.sh <path-to.app> <simulator-udid>"
APP_PATH="${1:?$USAGE}"
UDID="${2:?$USAGE}"
LOG_DIR="/tmp/claude"
RUN_ID="$(date '+%Y%m%d_%H%M%S')"
FAILURES=0
STEP=0

mkdir -p "$LOG_DIR"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist")"

tree() {
    idb ui describe-all --udid "$UDID" 2>/dev/null
}

labels() {
    tree | jq -r '.[] | (.AXLabel // empty), (.AXValue // empty)'
}

capture() {
    STEP=$((STEP + 1))
    local name="$1"
    xcrun simctl io "$UDID" screenshot "$LOG_DIR/example-step-$STEP-$name-$RUN_ID.png" > /dev/null
    tree > "$LOG_DIR/example-step-$STEP-$name-$RUN_ID.json"
    echo "captured step $STEP ($name)"
}

wait_for() {
    local pattern="$1" timeout="${2:-60}" waited=0
    until labels | grep -qE -- "$pattern"; do
        if [[ "$waited" -ge "$timeout" ]]; then
            return 1
        fi
        sleep 1
        waited=$((waited + 1))
    done
}

check() {
    local description="$1" pattern="$2"
    if labels | grep -qE -- "$pattern"; then
        echo "PASS: $description"
    else
        echo "FAIL: $description (no label matches /$pattern/)"
        FAILURES=$((FAILURES + 1))
    fi
}

tap_button() {
    local label="$1"
    local center
    center="$(tree | jq -r --arg label "$label" \
        '.[] | select(.type == "Button" and .AXLabel == $label) | "\((.frame.x + .frame.width / 2) | floor) \((.frame.y + .frame.height / 2) | floor)"' \
        | head -n 1)"
    if [[ -z "$center" ]]; then
        echo "FAIL: button \"$label\" not found"
        FAILURES=$((FAILURES + 1))
        return 1
    fi
    # shellcheck disable=SC2086
    idb ui tap --udid "$UDID" $center
    echo "tapped \"$label\""
}

wait_until_button_enabled() {
    local label="$1" timeout="${2:-15}" waited=0
    until [[ "$(tree | jq -r --arg label "$label" '.[] | select(.type == "Button" and .AXLabel == $label) | .enabled' | head -n 1)" == "true" ]]; do
        if [[ "$waited" -ge "$timeout" ]]; then
            return 1
        fi
        sleep 1
        waited=$((waited + 1))
    done
}

type_into_field_containing() {
    local existing="$1" text="$2"
    local center
    center="$(tree | jq -r --arg existing "$existing" \
        '.[] | select((.type == "TextField" or .type == "TextArea") and ((.AXValue // "") | tostring | contains($existing))) | "\((.frame.x + .frame.width / 2) | floor) \((.frame.y + .frame.height / 2) | floor)"' \
        | head -n 1)"
    if [[ -z "$center" ]]; then
        echo "FAIL: text field containing \"$existing\" not found"
        FAILURES=$((FAILURES + 1))
        return 1
    fi
    # shellcheck disable=SC2086
    idb ui tap --udid "$UDID" $center
    sleep 1
    idb ui text --udid "$UDID" "$text"
    # Dismiss the software keyboard so it does not cover the buttons below.
    idb ui key --udid "$UDID" 40 2> /dev/null || true
    sleep 1
    echo "typed \"$text\" into the field containing \"$existing\""
}

# Taps a button, then waits for a settlement-counter change; retries the tap once
# if nothing settled, working around idb's occasional silently-dropped taps.
tap_and_await_settlement() {
    local label="$1" expected="$2" timeout="${3:-90}"
    tap_button "$label"
    if wait_for "$expected" "$timeout"; then
        return 0
    fi
    echo "retrying \"$label\" (no settlement matched /$expected/ yet)"
    tap_button "$label"
    wait_for "$expected" "$timeout"
}

echo "== install and launch $BUNDLE_ID on $UDID"
xcrun simctl bootstatus "$UDID" -b > /dev/null
xcrun simctl install "$UDID" "$APP_PATH"
xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID"
wait_for '^Run diagnostics$' 30 || { echo "FAIL: app did not show the Run button"; exit 1; }
capture launched

echo "== the launch-time self-check proves dispose() rejects an in-flight diagnose()"
check "dispose mid-run self-check rejected with code disposed" \
    'self-check: dispose mid-run rejected with code disposed'

echo "== 1. full run with the default targets"
tap_and_await_settlement "Run diagnostics" 'last: resolved: ' 90 \
    || echo "FAIL: first run did not resolve within 90 s"
capture first-run-finished
check "promise resolved with a verdict" 'last: resolved: '
check "every stage finished" '^● HTTP probe$'
check "interfaces rendered" '^lo0'
check "ping section shows 1.1.1.1" '^1\.1\.1\.1'
check "http section shows apple.com" 'https://www\.apple\.com — HTTP [0-9]{3} in [0-9]+ ms'
check "dns servers section filled" 'apple\.com: (noError|nameError|serverFailure|timed out|failed)'

echo "== 2. cancel a run (blackhole host makes it last at least the 3 s hard timeout)"
type_into_field_containing "1.1.1.1" ", 192.0.2.1"
tap_button "Run diagnostics"
wait_until_button_enabled "Cancel" 10 || echo "FAIL: Cancel never became enabled"
tap_and_await_settlement "Cancel" 'last: rejected \(cancelled\)' 15 \
    || echo "FAIL: cancel did not reject the promise"
capture cancelled
check "run rejected with code cancelled" 'last: rejected \(cancelled\)'

echo "== 3. dispose the object during a run"
tap_button "Run diagnostics"
wait_until_button_enabled "Cancel" 10 || echo "FAIL: Cancel never became enabled (run 3)"
tap_and_await_settlement "Recreate object" 'last: rejected \(disposed\)' 15 \
    || echo "FAIL: dispose did not reject the promise"
capture disposed
check "run rejected with code disposed" 'last: rejected \(disposed\)'

echo "== 4. share sheet"
tap_button "Share JSON"
sleep 3
capture share-sheet
check "share sheet visible" '^(Copy|AirDrop|Close|Cancel|Messages|Mail|Notes|Print|Save to Files|Edit Actions)'

echo "== result: $FAILURES failure(s); evidence in $LOG_DIR/example-step-*-$RUN_ID.*"
[[ "$FAILURES" -eq 0 ]]
