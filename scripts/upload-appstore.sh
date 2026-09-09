#!/usr/bin/env bash
# Validates an ipa against App Store Connect and, unless --validate-only is
# given, uploads it. A developer-machine tool: the app-specific password comes
# out of gopass. The GitHub workflow does not use this script — it calls altool
# with the organisation's secrets instead, because a CI runner has no password
# store and should never reach for a personal one.
#
#   APPLE_ID=… GOPASS_ENTRY=… upload-appstore.sh <path-to.ipa> [--validate-only]
#
# The password is read at call time and handed to altool through the
# environment, so it stays out of the process list and the logs. The Apple ID
# and the gopass path are inputs rather than defaults on purpose: they identify
# a person, not this project.
#
# Validation always runs first, because a build number App Store Connect has
# accepted can never be reused.
set -euo pipefail

USAGE="usage: APPLE_ID=… GOPASS_ENTRY=… upload-appstore.sh <path-to.ipa> [--validate-only]"
IPA="${1:?$USAGE}"
VALIDATE_ONLY="${2:-}"
APPLE_ID="${APPLE_ID:?APPLE_ID must name the Apple ID with App Store Connect access}"
GOPASS_ENTRY="${GOPASS_ENTRY:?GOPASS_ENTRY must be the gopass path of the app-specific password}"

if [[ -n "$VALIDATE_ONLY" && "$VALIDATE_ONLY" != "--validate-only" ]]; then
    echo "$USAGE" >&2
    exit 2
fi
test -f "$IPA"
command -v gopass > /dev/null || {
    echo "gopass is not installed; it holds the app-specific password" >&2
    exit 1
}

ALTOOL_PASSWORD="$(gopass show -o "$GOPASS_ENTRY")"
export ALTOOL_PASSWORD

# altool exits 0 even when it fails, so its exit status cannot be trusted and
# the JSON payload decides: a product-errors key means failure, and output that
# is not parseable JSON counts as one too. Its human-readable progress log,
# including the delivery UUID, still reaches the terminal on stderr.
altool() {
    local output
    output="$(xcrun altool "$1" --type ios --file "$IPA" \
        --username "$APPLE_ID" --password '@env:ALTOOL_PASSWORD' \
        --output-format json)" || true

    if ! jq -e . > /dev/null 2>&1 <<< "$output"; then
        echo "altool $1 returned no parseable result:" >&2
        printf '%s\n' "$output" >&2
        return 1
    fi
    if jq -e 'has("product-errors")' > /dev/null <<< "$output"; then
        jq -r '."product-errors"[] | "  \(.code): \(.message)"' <<< "$output" >&2
        return 1
    fi
    echo "  no errors reported"
}

echo "== validating $IPA"
altool --validate-app

if [[ "$VALIDATE_ONLY" == "--validate-only" ]]; then
    echo "== --validate-only given, not uploading"
    exit 0
fi

echo "== uploading $IPA"
altool --upload-app
