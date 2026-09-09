#!/usr/bin/env bash
# Builds the example app against the plugin checked out one directory up.
#
#   build.sh              iOS Simulator, debug, developer console on  -> APP_PATH=
#   build.sh --app-store  device, release, developer console off      -> IPA_PATH=
#
# Cordova refuses to install a plugin that lives in a parent directory of the
# app, so the example is copied to a temporary directory first and the "../" in
# config.xml is rewritten — the same approach as build.fish in the older Tabris
# plugin repositories. The rewritten spec points at a staging directory holding
# the unpacked `npm pack` tarball of the plugin rather than at the checkout:
# Cordova copies a directory spec wholesale (including .git and the SwiftPM
# .build tree), while the tarball contains exactly what the published package
# ships. Cordova does not accept a tarball path as a spec, hence the unpacking
# step.
set -euo pipefail

APP_STORE_BUILD=false
if [[ "${1:-}" == "--app-store" ]]; then
    APP_STORE_BUILD=true
elif [[ -n "${1:-}" ]]; then
    echo "usage: build.sh [--app-store]" >&2
    exit 2
fi

EXAMPLE_APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$EXAMPLE_APP_DIR")"
WORK_DIR="$(mktemp -d)"
PLUGIN_STAGE="$WORK_DIR/plugin"

# config.xml carries placeholders for both: the Tabris native runtime reads
# EnableDeveloperConsole out of the bundled config.xml at startup, and the
# cordova-ios fork reads ios-CFBundleVersion at prepare time. The build number
# is a timestamp so every upload gets a fresh one without touching the version.
BUILD_NUMBER="$(date +%y%m%d%H%M)"
if [[ "$APP_STORE_BUILD" == true ]]; then
    VARIABLES="EXAMPLE_DEVELOPER_CONSOLE=false,EXAMPLE_BUILD_NUMBER=$BUILD_NUMBER"
else
    VARIABLES="EXAMPLE_DEVELOPER_CONSOLE=true,EXAMPLE_BUILD_NUMBER=$BUILD_NUMBER"
fi

echo "EXAMPLE_APP_DIR: $EXAMPLE_APP_DIR"
echo "PLUGIN_DIR:      $PLUGIN_DIR"
echo "WORK_DIR:        $WORK_DIR"
echo "VARIABLES:       $VARIABLES"

PACK_FILENAME="$(cd "$PLUGIN_DIR" && npm pack --json --pack-destination "$WORK_DIR" | jq -er 'if length == 1 then .[0].filename else error("npm pack produced \(length) tarballs") end')"
PLUGIN_TARBALL="$WORK_DIR/$PACK_FILENAME"
echo "PLUGIN_TARBALL:  $PLUGIN_TARBALL"
test -f "$PLUGIN_TARBALL"
mkdir -p "$PLUGIN_STAGE"
tar -xzf "$PLUGIN_TARBALL" -C "$PLUGIN_STAGE" --strip-components=1
echo "PLUGIN_STAGE:    $PLUGIN_STAGE ($(du -sh "$PLUGIN_STAGE" | cut -f 1))"

cp -R "$EXAMPLE_APP_DIR" "$WORK_DIR/example"
rm -rf "$WORK_DIR/example/build" "$WORK_DIR/example/node_modules"
cd "$WORK_DIR/example"

sed -i '' "s#spec=\"\\.\\./\"#spec=\"$PLUGIN_STAGE\"#" cordova/config.xml
test "$(grep -c "spec=\"$PLUGIN_STAGE\"" cordova/config.xml)" -eq 1
grep -n 'spec=' cordova/config.xml

npm install

APP_NAME="$(sed -n 's:.*<name>\(.*\)</name>.*:\1:p' cordova/config.xml | head -n 1)"
mkdir -p /tmp/claude

if [[ "$APP_STORE_BUILD" == false ]]; then
    tabris build ios --emulator --debug --verbose --variables "$VARIABLES"
    APP_PATH="$WORK_DIR/example/build/cordova/platforms/ios/build/emulator/$APP_NAME.app"
    test -d "$APP_PATH"
    printf '%s\n' "$APP_PATH" > /tmp/claude/netdiag-example-app-path.txt
    echo "APP_PATH=$APP_PATH"
    exit 0
fi

# The release build archives and signs correctly, but Cordova's export step asks
# Xcode for an account with App Store Connect access and fails without one, even
# though the export options request manual signing with an explicit profile. The
# archive is already signed with the distribution identity from build.json, so
# the ipa is assembled from it here; `altool --validate-app` accepts the result.
# See docs/knowledge/tabris-ios-plugins/02_packaging_and_build.md.
tabris build ios --device --release --verbose --variables "$VARIABLES" || true

ARCHIVE="$WORK_DIR/example/build/cordova/platforms/ios/$APP_NAME.xcarchive"
test -d "$ARCHIVE" || {
    echo "no archive at $ARCHIVE — the build failed before archiving" >&2
    exit 1
}
ARCHIVED_APP="$ARCHIVE/Products/Applications/$APP_NAME.app"
codesign --verify --deep --strict "$ARCHIVED_APP"

IPA_PATH="$WORK_DIR/$APP_NAME.ipa"
mkdir -p "$WORK_DIR/ipa/Payload"
ditto "$ARCHIVED_APP" "$WORK_DIR/ipa/Payload/$APP_NAME.app"
(cd "$WORK_DIR/ipa" && zip -qry "$IPA_PATH" Payload)

printf '%s\n' "$IPA_PATH" > /tmp/claude/netdiag-example-ipa-path.txt
echo "BUILD_NUMBER=$BUILD_NUMBER"
echo "IPA_PATH=$IPA_PATH"
