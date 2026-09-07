#!/usr/bin/env bash
# Builds the example app for the iOS Simulator against the plugin checked out
# one directory up. Cordova refuses to install a plugin that lives in a parent
# directory of the app, so the example is copied to a temporary directory first
# and the "../" in config.xml is rewritten — the same approach as build.fish in
# the older Tabris plugin repositories. The rewritten spec points at a staging
# directory holding the unpacked `npm pack` tarball of the plugin rather than at
# the checkout: Cordova copies a directory spec wholesale (including .git and the
# SwiftPM .build tree), while the tarball contains exactly what the published
# package ships. Cordova does not accept a tarball path as a spec, hence the
# unpacking step.
set -euo pipefail

EXAMPLE_APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$EXAMPLE_APP_DIR")"
WORK_DIR="$(mktemp -d)"
PLUGIN_STAGE="$WORK_DIR/plugin"

echo "EXAMPLE_APP_DIR: $EXAMPLE_APP_DIR"
echo "PLUGIN_DIR:      $PLUGIN_DIR"
echo "WORK_DIR:        $WORK_DIR"

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
tabris build ios --emulator --debug --verbose

APP_NAME="$(sed -n 's:.*<name>\(.*\)</name>.*:\1:p' cordova/config.xml | head -n 1)"
APP_PATH="$WORK_DIR/example/build/cordova/platforms/ios/build/emulator/$APP_NAME.app"
test -d "$APP_PATH"
mkdir -p /tmp/claude
printf '%s\n' "$APP_PATH" > /tmp/claude/netdiag-example-app-path.txt
echo "APP_PATH=$APP_PATH"
