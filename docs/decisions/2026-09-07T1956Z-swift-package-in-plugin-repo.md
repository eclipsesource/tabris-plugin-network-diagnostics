# The plugin repository doubles as the Swift package

Date: 2026-09-07

## Context

`NetworkDiagnostics` was written as a Swift package with two XCTest targets:
pure unit tests over the codecs, parsers and the verdict matrix, and loopback
integration tests that exercise the real ICMP, UDP DNS and HTTP paths against
in-process servers. A Cordova plugin, however, is a flat list of source files
that Cordova copies into the generated Xcode project — it has no module
boundary, no test target and no package manifest.

Compiling the same sources in both worlds raises three concrete conflicts:

- the resolver shim is a separate C target (`Sources/CResolv`) that Swift
  imports as a module; inside the Cordova app there is no module, only the
  header reachable through the Swift bridging header;
- the package required iOS 17 for `AsyncStream.makeStream(of:)` (two production
  sites and both loopback test servers), while Tabris-generated projects declare
  a deployment target of 11.0–12.0;
- a Cordova app compiles every plugin's Swift into one module, so a generic
  top-level name such as `Log` can collide with another plugin.

## Decision

1. The repository root keeps `Package.swift`. `plugin.xml` lists the very same
   files under `Sources/` as `<source-file>` entries, so the tested code and the
   shipped code are one set of files. Tests stay under `Tests/`, run with
   `swift test` on the macOS host for the fast loop and with
   `scripts/run-simulator-tests.sh` on a dedicated simulator as the gate. The
   `.macOS` platform is retained for that host loop; every service used by the
   package (`getifaddrs`, `libresolv`, `NWPathMonitor`, unprivileged `SOCK_DGRAM`
   ICMP, `NWListener`) exists on macOS.
2. `Services/DNSServerReading.swift` imports the shim behind
   `#if canImport(CResolv)`. Under SwiftPM the C target is a module and the
   import is real; under Cordova the condition is false and the symbol
   `cresolv_copy_dns_servers` is visible through the plugin's bridging header,
   which imports `CResolv.h`. The file compiles unchanged in both builds.
3. The deployment floor is iOS 16. The four `makeStream` sites use the
   `AsyncStream { continuation in … }` initializer instead; its build closure
   runs synchronously at construction, so the handler is installed before the
   monitor, connection or listener is started, exactly as before. Everything
   else the package needs (`ContinuousClock`, `Duration`, `Task.sleep(for:)`,
   `NWPath.gateways`, `os.Logger`) is available on iOS 16. The plugin raises the
   consumer app's deployment target to 16.0 through a Cordova preference
   (recorded in the packaging decision).
4. `Log` is renamed `NetworkDiagnosticsLog`. Other internal type names
   (`ProbeRunner`, `DNSMessage`, `ICMPPacket`, `ServiceFailure`) are specific
   enough to keep.

## Consequences

- One `#if canImport` line is the only build-system trace in production code.
- The package's tests continue to protect the port; the mechanical edits
  (import guard, stream construction, rename) are covered by the existing suites.
- Test-only files (`Tests/**`, stubs, loopback servers, `MockURLProtocol`) are
  never listed in `plugin.xml` and never reach a consumer app.
- The plugin's own bridge class (`src/ios/`) depends on the Tabris framework and
  is compiled by Cordova only; anything in it that can be unit-tested is moved
  into `Sources/NetworkDiagnostics/Bridge/`.

## Rejected alternatives

- **Copy the sources flat into `src/ios/` and drop the package and its tests.**
  Loses both test suites and the simulator harness, and violates the rule that
  every feature lands with tests; the port itself touches every file, so the
  tests are the only regression proof.
- **Move the tests into an Xcode test target of the generated example app.**
  The Cordova project is regenerated on every build; a stable test target would
  need its own project generator and a downloaded `Tabris.xcframework` — many
  more moving parts than a package `xcodebuild` already understands.
- **Keep iOS 17 and require consumers to raise their floor further.** iOS 17
  buys nothing the plugin needs; iOS 16 keeps the change to a plugin-injected
  preference that most apps already satisfy.
- **Replace the C shim with `@_silgen_name` declarations or a direct
  `<resolv.h>` import.** `<resolv.h>` is not part of the Darwin module map and
  `__res_state` carries bitfields Swift cannot import cleanly; the shim stays.
