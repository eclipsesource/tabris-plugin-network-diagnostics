# Tabris.js Network Diagnostics Plugin Example

## Build for the simulator

```bash
./build.sh
```

Copies the example to a temporary directory, rewrites the plugin reference
`spec="../"` to the absolute plugin path (Cordova cannot install a plugin from
a parent directory) and runs `tabris build ios --emulator --debug`. The last
output line is `APP_PATH=<path to the built .app>`.

`config.xml` holds placeholders for the developer console and the build number,
which the script fills in through `tabris build --variables`. Build the example
with this script rather than the Tabris CLI directly, or those two preferences
reach the app unresolved.

## Build for the App Store and upload

```bash
./build.sh --app-store
APPLE_ID=… GOPASS_ENTRY=… ../scripts/upload-appstore.sh "<IPA_PATH>"
```

Signs with the distribution profile named in `cordova/build.json`, turns the
developer console off, and stamps `CFBundleVersion` with a `yymmddHHMM`
timestamp so `version` in `config.xml` need not change between uploads. The last
two output lines are `BUILD_NUMBER=` and `IPA_PATH=`.

The ipa is assembled from the signed archive rather than by `xcodebuild
-exportArchive`, which needs an Xcode account with App Store Connect access even
for manual signing — see
`../docs/knowledge/tabris-ios-plugins/02_packaging_and_build.md`.

`upload-appstore.sh` always validates before uploading and reads the
app-specific password from gopass. Pass `--validate-only` to stop after
validation.

## Install and launch on a simulator

```bash
../scripts/example-simulator.sh "<APP_PATH>" <simulator-udid>
```

Installs the app, launches it with the console attached and writes the console
log and a screenshot to `/tmp/claude/`.

## Targets are remembered

The five target fields are written to `localStorage` on every change and read
back at startup, so testing against hosts on your own LAN does not mean typing
them in again. `../scripts/example-clickthrough.sh` uninstalls the app before it
starts, so an earlier run's edits cannot leak into the next one.
