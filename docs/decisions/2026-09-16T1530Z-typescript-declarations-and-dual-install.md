# TypeScript declarations in a global namespace, installed through npm and Cordova

Date: 2026-09-16

## Context

A Tabris.js app written in TypeScript could not use the plugin: the module in
`www/` is installed by Cordova as the global `es.NetworkDiagnostics`, the
repository shipped no declarations, and `tsc` failed with `Cannot find name
'es'`. The Tabris CLI compiles the app (`npm run build`) before it creates the
Cordova project and adds plugins, so even a plugin that bundled declarations
would not be visible to the compiler through the Cordova install alone.

The older EclipseSource plugins with declarations (firebase, barcode-scanner)
hand-write `types/index.d.ts` with `declare global { namespace <clobbers
prefix> { … } }` and point `package.json`'s `types` at it; omr-2 generates its
declarations from TypeScript sources and its example app lists the plugin as an
npm dependency for exactly this reason.

## Decision

- `types/index.d.ts` is hand-written next to `www/NetworkDiagnostics.js` and
  declares everything inside `declare global { namespace es { … } }`: the
  class, the option and configuration types, the `state`-discriminated
  outcomes, the report and the event payloads. Result shapes are written as
  discriminated unions so that `outcome.avgRttMs` compiles only after checking
  `outcome.state === 'reachable'`. `package.json` gains `"types"`.
- The namespace name is the `clobbers` prefix; no module-level exports
  duplicate the types under a second name.
- A consuming app installs the plugin twice: as a devDependency for the
  compiler, referenced through `compilerOptions.types` (or a triple-slash
  reference), and as a Cordova plugin for the runtime. An `import` of the
  package is documented as wrong, because TypeScript keeps a bare import in
  the emitted JavaScript and the production bundle does not contain the
  package.
- `example_typescript/` is a second example app, a port of `example/` to
  TypeScript, built through the same `scripts/build-example.sh`, which
  rewrites both the Cordova `spec` and the `file:..` devDependency to the
  staged `npm pack` output. Its `tsc` run is the compile-time check of the
  declarations; `PluginManifestTests` checks that every public method and
  every native event in `www/` has a declaration.
- The TypeScript example's `.tabrisignore` excludes `package-lock.json`: the
  lock records the `file:` devDependency as a link relative to the app
  directory, and the Tabris CLI's `npm ci --production` inside the copied
  bundle fails on it. Without a lock the CLI runs `npm install --production`,
  which installs `tabris` only. An app that references a published version or
  a git URL keeps its lock.
- `dispose()` and `isDisposed()` are declared on the class: the Tabris typings
  do not put them on `NativeObject`, although the runtime provides them there.

## Consequences

- TypeScript apps see typed methods, events and results; `on()` keeps a
  `string` fallback overload for compatibility with `NativeObject`, so an
  unknown event name still compiles.
- Two version references per app (npm and Cordova) have to be kept in step.
- The declarations are maintained by hand; the parity test catches a missing
  method or event but not a changed field, which stays a review item alongside
  the README tables.
- The example's `tsconfig.json` follows the Tabris app conventions
  (`noImplicitAny` and friends, `skipLibCheck`, no `strict`): the Tabris
  typings rely on bivariant method parameters and fail under
  `strictFunctionTypes`.

## Rejected alternatives

- **An app-local `es.d.ts` in the consuming app.** Unblocks one app but leaves
  the declarations outside the plugin, where they drift from the API.
- **Generating the declarations from TypeScript sources (the omr-2 approach).**
  Would mean rewriting `www/` in TypeScript and adding a build step to a
  plugin whose JavaScript is one file; the hand-written file is smaller than
  that build.
- **A single example app switched to TypeScript.** The JavaScript example is
  what the README's snippets and the clickthrough script are written against;
  the user asked for the TypeScript example to be a separate app.
- **A bare `import 'tabris-plugin-network-diagnostics'` in the app.** Simplest
  to write, but emitted as a `require()` that fails at runtime in the
  production bundle.
