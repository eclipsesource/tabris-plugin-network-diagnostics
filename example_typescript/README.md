# Tabris.js Network Diagnostics Plugin TypeScript Example

The JavaScript example (`../example/`) ported to TypeScript. It exists to prove
that the plugin's type declarations (`../types/index.d.ts`) compile against
the Tabris typings and describe the API an app actually uses.

## The plugin is installed twice

`tabris build` runs `npm run build` (here: `tsc`) before it hands the app to
Cordova, so at compile time no Cordova plugin exists yet. The plugin therefore
reaches the app through two channels:

- **npm, for the compiler.** `package.json` lists the plugin as a devDependency
  (`"file:.."` in this checkout; a published version or git URL in a real app)
  and `tsconfig.json` names it under `compilerOptions.types`. `tabris build`
  installs only production dependencies into the bundle, so nothing of this
  ships. `preserveSymlinks` is set because npm links a `file:` dependency and
  the linked declarations must resolve `tabris` from this app's `node_modules`.
- **Cordova, for the runtime.** `cordova/config.xml` carries the `<plugin>`
  entry that installs the native code and the `www/` module behind the global
  `es.NetworkDiagnostics`.

The app never `import`s the package: a bare import would be emitted as a
`require()` of a package that is not in the bundle.

`.tabrisignore` keeps `package-lock.json` out of the bundle: the lock records
the `file:` devDependency as a link relative to this directory, and
`npm ci --production` inside the copied bundle cannot resolve it. Without the
lock the Tabris CLI falls back to `npm install --production`, which installs
`tabris` only.

## Type-check without building the app

```bash
npm install
npm run build
```

## Build for the simulator or the App Store

```bash
./build.sh              # last line: APP_PATH=<.app>
./build.sh --app-store  # last two lines: BUILD_NUMBER=, IPA_PATH=
```

Both run `../scripts/build-example.sh`, which copies the app to a temporary
directory, rewrites the `spec="../"` and `"file:.."` references to the same
unpacked `npm pack` tarball of the plugin and runs `tabris build`. See
`../example/README.md` for the App Store upload and the simulator scripts;
they apply unchanged.
