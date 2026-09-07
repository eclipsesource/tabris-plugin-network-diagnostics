#!/usr/bin/env bash
# Runs the whole test suite on a freshly created, uniquely named iOS simulator
# with isolated build artefacts, retrying only on tooling crashes, and always
# deleting the simulator and artefacts afterwards.
set -euo pipefail

PACKAGE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="/tmp/claude"
SIM_NAME="NetDiagTests-$(date +%s)-$(uuidgen | cut -c1-8)"
DERIVED_DATA="/tmp/dd-$SIM_NAME"
RESULT_BUNDLE="/tmp/result-$SIM_NAME.xcresult"
MAX_ATTEMPTS=3
RETRY_DELAY_SECONDS=20
SIM_UDID=""

mkdir -p "$LOG_DIR"

cleanup() {
    if [[ -n "$SIM_UDID" ]]; then
        xcrun simctl shutdown "$SIM_UDID" 2>/dev/null || true
        xcrun simctl delete "$SIM_UDID" 2>/dev/null || true
    fi
    rm -rf "$DERIVED_DATA" "$RESULT_BUNDLE"
}
trap cleanup EXIT

RUNTIME=$(xcrun simctl list runtimes -j \
    | jq -r '[.runtimes[] | select(.platform == "iOS" and .isAvailable)] | sort_by(.version) | last | .identifier')
DEVICE_TYPE=$(xcrun simctl list runtimes -j \
    | jq -r --arg runtime "$RUNTIME" \
        '.runtimes[] | select(.identifier == $runtime) | .supportedDeviceTypes[] | select(.name | test("^iPhone")) | .identifier' \
    | head -n 1)
if [[ -z "$RUNTIME" || -z "$DEVICE_TYPE" ]]; then
    echo "No available iOS runtime with an iPhone device type" >&2
    exit 1
fi

SIM_UDID=$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME")
echo "Created simulator $SIM_NAME ($SIM_UDID) as $DEVICE_TYPE on $RUNTIME"
xcrun simctl bootstatus "$SIM_UDID" -b

SCHEME=$(cd "$PACKAGE_DIR" && xcodebuild -list -json 2>/dev/null \
    | jq -r '.workspace.schemes // .project.schemes | map(select(endswith("-Package"))) | first // empty')
if [[ -z "$SCHEME" ]]; then
    SCHEME="NetworkDiagnostics"
fi

is_infrastructure_failure() {
    grep -Eq 'Early unexpected exit|CoreSimulatorService|Unable to boot|Failed to boot|Test runner never began executing tests|Lost connection to the test manager|timed out waiting for|xcodebuild.*(crash|SIGSEGV)' "$1"
}

has_test_failures() {
    grep -Eq 'Test Case .* failed|with [1-9][0-9]* failures?|\*\* TEST FAILED \*\*' "$1"
}

has_compile_errors() {
    grep -Eq '(error: |\*\* BUILD FAILED \*\*)' "$1"
}

for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
    LOG_FILE="$LOG_DIR/xcodebuild-test-$(date '+%Y%m%d_%H%M%S').log"
    rm -rf "$RESULT_BUNDLE"
    echo "Attempt $attempt/$MAX_ATTEMPTS: xcodebuild test -scheme $SCHEME (log: $LOG_FILE)"
    if (cd "$PACKAGE_DIR" && xcodebuild test \
            -scheme "$SCHEME" \
            -destination "platform=iOS Simulator,id=$SIM_UDID" \
            -derivedDataPath "$DERIVED_DATA" \
            -resultBundlePath "$RESULT_BUNDLE" \
            2>&1 | tee "$LOG_FILE"); then
        echo "All tests passed on $SIM_NAME"
        exit 0
    fi
    if has_test_failures "$LOG_FILE"; then
        echo "Tests failed - fix the code, not the tooling (see $LOG_FILE)" >&2
        exit 65
    fi
    if has_compile_errors "$LOG_FILE" && ! is_infrastructure_failure "$LOG_FILE"; then
        echo "Build failed - fix the code (see $LOG_FILE)" >&2
        exit 65
    fi
    if is_infrastructure_failure "$LOG_FILE" && [[ "$attempt" -lt "$MAX_ATTEMPTS" ]]; then
        echo "Tooling failure detected, retrying in ${RETRY_DELAY_SECONDS}s" >&2
        sleep "$RETRY_DELAY_SECONDS"
        continue
    fi
    echo "xcodebuild failed without a recognised cause (see $LOG_FILE)" >&2
    exit 1
done
echo "Gave up after $MAX_ATTEMPTS tooling failures" >&2
exit 1
