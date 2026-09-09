#!/usr/bin/env bash
# Validates an ipa against App Store Connect and, unless --validate-only is
# given, uploads it. Validation runs first every time: it costs nothing and a
# build number that App Store Connect has accepted can never be reused.
#
#   APPLE_ID=… GOPASS_ENTRY=… upload-appstore.sh <path-to.ipa> [--validate-only]
#
# The app-specific password is read from gopass at call time and handed to
# altool through the environment, so it stays out of the process list, the shell
# history and any log. The Apple ID and the gopass path are inputs rather than
# defaults on purpose: they identify a person, not this project.
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

altool_with_password() {
    ALTOOL_PASSWORD="$(gopass show -o "$GOPASS_ENTRY")" \
        xcrun altool "$1" -t ios -u "$APPLE_ID" -p '@env:ALTOOL_PASSWORD' -f "$IPA"
}

echo "== validating $IPA"
altool_with_password --validate-app

if [[ "$VALIDATE_ONLY" == "--validate-only" ]]; then
    echo "== --validate-only given, not uploading"
    exit 0
fi

echo "== uploading $IPA"
altool_with_password --upload-app
