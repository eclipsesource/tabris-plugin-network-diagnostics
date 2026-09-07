# The example app is built from an `npm pack` tarball of the plugin

Date: 2026-09-07

## Context

The example app lives inside the plugin repository and references the plugin
with `<plugin name="tabris-plugin-network-diagnostics" spec="../" />`, like the
older Tabris plugin repositories do. Cordova cannot install a plugin from a
parent directory of the app, so those repositories ship a `build.fish` that
copies the example to a temporary directory and rewrites `../` to the absolute
checkout path before running `tabris build`.

Pointing the spec at the checkout directory makes Cordova copy that directory
wholesale into `plugins/`: the first build of this example copied 858 MB,
almost all of it the SwiftPM `.build` tree plus `.git`, `Tests/`, `docs/` and
the example itself — none of which belongs in a consuming app.

## Decision

`example/build.sh` (bash, replacing the fish script of the older repositories)
keeps the temporary-directory workflow but rewrites the spec to a staging
directory that holds the unpacked tarball produced by `npm pack` from the
plugin root. npm honours `.npmignore`, so the app receives exactly the files a
published version of the plugin would contain, and every example build doubles
as a check that `.npmignore` and `plugin.xml` agree on what ships. Cordova
resolves a tarball path through the npm registry (`npm view <path>` → 404), so
the tarball is unpacked first and the directory is used as the spec. The script
prints the built `.app` path as its last line for the simulator script.

## Consequences

- Example builds are independent of the state of `.build/`, `.swiftpm/` and the
  git checkout; `npm pack` plus `tar -x` are the only extra steps.
- A file missing from the package (excluded by `.npmignore` but listed in
  `plugin.xml`) fails the example build instead of surfacing at publish time.
- The workflow still needs a temporary directory and a `sed` rewrite; Cordova's
  parent-directory restriction is unchanged.

## Rejected alternatives

- **Directory spec as in the older repositories.** Works, but copies the whole
  checkout on every build and never exercises `.npmignore`.
- **The `npm pack` + `before_platform_add` hook used by the newer plugin
  repositories (firebase, omr-2), building in place.** Avoids the temporary
  directory, but the user asked for the older temporary-directory pattern in
  bash.
- **Deleting `.build/` before every example build.** Forces a full SwiftPM
  rebuild for the next test run and still copies `.git`, `Tests/` and `docs/`.
