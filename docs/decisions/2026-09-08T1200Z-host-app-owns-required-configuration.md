# The host app owns the build settings and the privacy string

Date: 2026-09-08

Supersedes `2026-09-07T2015Z-build-settings-via-preferences.md`.

## Context

The superseded decision had `plugin.xml` inject three things into every
consuming application: the `deployment-target` and `SwiftVersion` preferences
through a `<config-file target="config.xml">` munge, and
`NSLocalNetworkUsageDescription` into the app's `Info.plist` from a plugin
variable. It was chosen so that no consumer would fail on a first build.

The review of that skeleton rated the build-setting injection a **high** risk,
because two plugins can inject conflicting values into the same app, and
`docs/reviews/open-questions.md` carried it as an open question with the
alternative stated: *documenting both as host-app requirements only*. That
question is now decided.

Three properties make these settings the application's rather than the
plugin's:

- `deployment-target` raises the minimum iOS version of the **whole
  application**, every other plugin and every device it can be installed on. A
  library dependency does not get to make that call silently.
- `SwiftVersion` sets the Swift language version for the app target, which
  compiles every plugin's Swift, not only this one's.
- `NSLocalNetworkUsageDescription` is a sentence the application's own users
  read in a system permission dialog. Shipping a default means an app can
  present text its author never wrote and cannot localise.

## Decision

`plugin.xml` configures nothing outside its own compilation units. It declares
the source files, the bridging header, the frameworks and the
`TabrisPlugins.plist` class registration, and nothing else. The
`LOCAL_NETWORK_USAGE_DESCRIPTION` variable is gone with the munge that used it.

The three entries are documented instead, in one highlighted block at the top
of `README.md`, before installation — they are a precondition for the plugin
working at all, not a footnote under requirements.

`example/cordova/config.xml` carries all three as a working reference, so the
documentation is executable rather than aspirational. The example declares the
two preferences at the root of its `config.xml` and the usage description
through `<edit-config mode="merge">` inside `<platform name="ios">`.

`PluginManifestTests` asserts the split holds: `plugin.xml` must not carry a
`config.xml` munge or an `Info.plist` munge, and the example's `config.xml` must
declare every entry the README requires.

## Consequences

- An app that skips the build settings fails to compile, with availability
  errors naming `ContinuousClock` and `Task.sleep(for:)`. That is a loud,
  actionable failure at the earliest possible moment, and the README block is
  the first thing a reader sees.
- An app that skips the usage description builds and runs, but its local
  network probes — the gateway ping and the DNS server queries — fail on a
  device. This is the one silent failure the split introduces, which is why the
  README block names it explicitly and the plugin no longer supplies a default
  that would hide it.
- Two plugins can no longer inject conflicting build settings into one app; the
  app states its own.
- `docs/knowledge/tabris-ios-plugins/02_packaging_and_build.md` keeps describing
  the preference mechanism, because it remains the way a Tabris app raises those
  settings — only the party who writes them changed.

## Rejected alternatives

- **Keeping the injection** (the superseded decision). Convenient on a first
  build, but it silently rewrites the host app's minimum iOS version and its
  privacy copy, and the review flagged the plugin-versus-plugin conflict.
- **Injecting the build settings but not the privacy string.** The build
  settings are the more invasive of the two, so a split along that line puts the
  boundary in the wrong place.
- **Failing the plugin install with a hook when the app has not declared them.**
  Adds the hook and the npm dependencies the superseded decision was written to
  avoid, and a compile error already says the same thing.
- **Shipping the settings in a documented snippet the app author copies, plus a
  variable default for the privacy string.** Half a contract: the default is
  exactly the part that hides the mistake.
