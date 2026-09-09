# 02 — Packaging, `plugin.xml` and the build

## Repository layout (identical in all three reference plugins)

```
plugin.xml                 Cordova plugin descriptor — the single source of truth
package.json               npm/Cordova metadata (id, platforms, keywords)
www/<Type>.js              JavaScript proxy, one file per native type
src/ios/<Type>.swift       native implementation
src/ios/Tabris-BridgingHeader.h
docs/<name>.md             JS API documentation (openidconnect)
example/                   standalone Tabris.js app that consumes the plugin
  package.json             { "dependencies": { "tabris": "nightly" } }
  cordova/config.xml       references the plugin by relative path (spec="../")
  src/app.js
  build.fish               copies example to a temp dir, rewrites "../" to an absolute path, `tabris build ios`
.npmignore                 excludes example/, project/, .idea/, .vscode/, .github
```

## `plugin.xml` — the elements that matter

```xml
<plugin xmlns="http://apache.org/cordova/ns/plugins/1.0"
        id="tabris-plugin-smb2" version="3.1.0">

  <engines><engine name="cordova" version=">=3.8.0" /></engines>

  <!-- 1. JS proxy + the global it is exposed as -->
  <js-module src="www/SMBClient.js" name="SMBClient">
    <clobbers target="es.SMBClient" />
  </js-module>

  <platform name="ios">
    <!-- 2. register the Objective-C class name with the Tabris runtime -->
    <config-file target="*TabrisPlugins.plist" parent="classes">
      <array>
        <string>SMBClient</string>
      </array>
    </config-file>

    <!-- 3. Swift needs a bridging header that imports the framework -->
    <header-file src="src/ios/Tabris-BridgingHeader.h" type="BridgingHeader"/>
    <source-file src="src/ios/SMBClient.swift" />

    <!-- 4. third-party dependencies via CocoaPods -->
    <podspec>
      <pods use-frameworks="true">
        <pod name="AMSMB2" spec="~> 2.7" />
      </pods>
    </podspec>
  </platform>
</plugin>
```

Notes:
- `<clobbers target="es.SMBClient" />` puts the class on the global `es` namespace, so app code writes
  `new es.SMBClient()` — no `require`. All three plugins use the `es.` prefix.
- `<config-file target="*TabrisPlugins.plist" parent="classes">` is the registration hook described in
  `01_architecture.md`. The generated file looks like:
  ```xml
  <dict><key>classes</key><array><string>CordovaPluginBridge</string></array></dict>
  ```
- One plugin may register **several** types: Diamond lists four (`AddDiamondButton`,
  `AddDiamondWorkflow`, `DiamondLibrary`, `DeviceCheck`) with four `<js-module>` entries.
- `<js-module>` may sit inside `<platform name="ios">` (Diamond) or at plugin level (SMB2, OIDC).
  Platform level is correct for an iOS-only plugin; plugin level also works because the plugin
  declares `"platforms": ["ios"]` in `package.json`.
- Every `.swift` file needs its own `<source-file>` entry. OIDC lists four.
- Objective-C files need `<header-file>` **and** `<source-file>` entries (Diamond lists both for each).

## Bridging header

Cordova has no notion of Swift, so the bridging header is what makes the framework visible.
It is identical in all three plugins:

```objc
#import <Tabris/Tabris.h>
```

`Tabris/Tabris.h` is an umbrella header — it pulls in `BasicObject`, `Widget`, `Control`,
`JSFunctionValue`, `ArrayBuffer`, `Console`, `LogEntry`, `TabrisContext`, the type-safe
`NSDictionary` getters, `TypeConverter`, `ObjectRegistry`, `FloatingViewController` and
`PublicTypes.h` (the `ConsoleEntryType` / `LogLevel` enums).

Only **one** bridging header can exist per Xcode target. Cordova's `type="BridgingHeader"` merges
plugin-supplied headers, which is why every plugin can ship the same one-line file.

## Swift build settings — the `add-swift-support.js` hook

Cordova's generated project has no `SWIFT_VERSION`, so a Swift file fails to compile. OIDC ships a
hook (`hook/add-swift-support.js`, dependencies `xcode` + `semver` in `package.json`) registered for
three phases:

```xml
<hook type="after_prepare"       src="hook/add-swift-support.js" />
<hook type="after_platform_add"  src="hook/add-swift-support.js" />
<hook type="after_plugin_add"    src="hook/add-swift-support.js" />
```

What it does, by editing `platforms/ios/<name>.xcodeproj/project.pbxproj` with the `xcode` module:
- sets `SWIFT_VERSION` to `5.0` on every build configuration that lacks it, or to the value of the
  `UseSwiftLanguageVersion` iOS preference from `config.xml` when present;
- forces `SWIFT_OPTIMIZATION_LEVEL = "-Onone"` on the `Debug` configuration.

It guards on `context.cmdLine` because Cordova fires hooks more often than the work is needed.

SMB2 and Diamond do **not** ship this hook — SMB2 compiles because CocoaPods with
`use-frameworks="true"` already forces a Swift toolchain configuration; Diamond's Swift file
(`SwiftObject.swift`) is not listed in `plugin.xml` at all (it only exists in the standalone dev
project).

### Preferences instead of the hook (Tabris CLI 3.10, cordova-ios 6.2)

The cordova-ios fork the Tabris CLI 3.10 ships reads two preferences from the *platform* `config.xml`
on every prepare (`~/.tabris-cli/platforms/ios/<version>/bin/templates/scripts/cordova/lib/prepare.js`):
`SwiftVersion` → `SWIFT_VERSION` and `deployment-target` → `IPHONEOS_DEPLOYMENT_TARGET`. Plugin
`<config-file>` munges are applied before those are read, and the app's own `config.xml` merges on top,
so a plugin can set both without a hook and the app still overrides:

```xml
<config-file target="config.xml" parent="/*">
  <preference name="deployment-target" value="16.0" />
  <preference name="SwiftVersion" value="5.0" />
</config-file>
```

The same two preferences work verbatim in an **application's** `config.xml`, with no munge involved.
That is where `tabris-plugin-network-diagnostics` puts them (`example/cordova/config.xml`): a
deployment target raises the minimum iOS version of the whole app rather than of one plugin, so it is
the app's to declare — see `docs/decisions/2026-09-08T1200Z-host-app-owns-required-configuration.md`.

Either way, verify by reading the *resolved* values with `xcodebuild -showBuildSettings` on the
generated project, not by grepping `project.pbxproj`. The `add-swift-support.js` hook remains the
fallback if a future fork stops honouring the preferences.

### App Store export needs an Xcode account, even with manual signing

`tabris build ios --device --release` archives and signs correctly from
`cordova/build.json` (`Apple Distribution` plus an explicit profile UUID), and the
`exportOptions.plist` Cordova generates already asks for `signingStyle: manual`. The
export step still fails:

```
DVTDeveloperAccountManager: Failed to load credentials for <apple id>:
  Invalid credentials in keychain … missing Xcode-Token
error: exportArchive Copy failed
** EXPORT FAILED **
```

The real reason is in the distribution log bundle named in the output
(`IDEDistribution.standard.log`): `Failed to find an account with App Store Connect
access for team <team id>`. `xcodebuild -exportArchive` with an App Store method wants
an authenticated Xcode account regardless of the signing style, and adding
`destination: export` to the export options does not avoid it.

Two ways out. Sign in again under Xcode → Settings → Accounts, or skip the export: an
ipa is a zip of `Payload/<App>.app`, and the app inside the archive is already signed
with the distribution identity, so

```bash
mkdir -p ipa/Payload && ditto "<archive>/Products/Applications/<App>.app" "ipa/Payload/<App>.app"
(cd ipa && zip -qry ../App.ipa Payload)
```

produces an ipa that `xcrun altool --validate-app` accepts with no errors. No
`SwiftSupport` directory is needed: Swift's runtime ships in the OS from iOS 12.2, well
below any deployment target this repository supports.

### Two more integration facts that bite

- **Unique bridging-header basename.** Cordova flattens every plugin file to
  `Plugins/<plugin-id>/<basename>` and merges each `type="BridgingHeader"` header into one
  `Bridging-Header.h` by basename (`Api.js`). Every existing plugin ships `Tabris-BridgingHeader.h`;
  two of them in one app collide. Name yours after the plugin (e.g. `NetworkDiagnostics-BridgingHeader.h`).
  Basename collisions apply to source files too — keep them unique.
- **System `.tbd` libraries link cleanly.** `<framework src="libresolv.tbd" />` is enough to link
  `libresolv` (the `xcode` npm module maps `.tbd` to `usr/lib`, `SDKROOT`); no `OTHER_LDFLAGS` needed.
- **Flat Swift namespace.** All plugin Swift compiles into the app module. A generic top-level name
  (`Log`, `Duration.milliseconds`, `TabrisError`) can clash with another plugin — prefix collision-prone
  names with the plugin's own (`NetworkDiagnosticsLog`).

## Consuming the plugin from an app

```xml
<plugin name="tabris-plugin-openidconnect"
        spec="https://github.com/eclipsesource/tabris-plugin-openidconnect.git" />
```

The example apps use `spec="../"` (local path) plus a `build.fish` that copies the example into a
temp directory and rewrites `../` to an absolute path, so `tabris build ios` resolves the plugin
without polluting the repo.

Set `<preference name="EnableDeveloperConsole" value="true" />` — the plugin console output
(`10_console_and_logging.md`) is only visible with the developer console enabled.

## Standalone Xcode project for native development (Diamond)

Editing plugin sources inside `platforms/ios` is throwaway work. Diamond keeps a real framework
target at `src/ios/diamond.xcodeproj` so Xcode gives completion, diagnostics and tests:

- `SWIFT_VERSION = 5.0`, `DEFINES_MODULE = YES`, `SKIP_INSTALL = YES`,
  `IPHONEOS_DEPLOYMENT_TARGET = 11.0`
- `FRAMEWORK_SEARCH_PATHS = ("$(inherited)", "$(PROJECT_DIR)/tabris_framework")`
- `src/ios/get_tabris_framework.sh` downloads `Tabris.xcframework` into `tabris_framework/`:
  it resolves the version with `npm show tabris version` (or the newest nightly with
  `npm view tabris versions --json | jq -r '.[-1]'`) and fetches
  `https://tabrisjs.com/api/v1/downloads/cli/$VERSION/ios` with the header
  `X-Tabris-Build-Key: $(cat ~/.tabris-cli/build.key)`.
- A test target (`src/ios/diamondTests`) exists but is an empty XCTest skeleton.
- `scripts/update-sources.sh`, registered as `<hook type="before_plugin_install">`, copies sources
  back from a built example app into the repo. It is a personal round-trip helper with hardcoded
  `~/git/...` paths — treat it as an example of the workflow, not as something to reuse verbatim.
