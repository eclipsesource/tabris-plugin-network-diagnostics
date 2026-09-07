# One run per object, six named events, promise settles exactly once

Date: 2026-09-07

## Context

`diagnose()` wraps `NetworkDiagnostics.diagnose(_:)`, an `AsyncStream` of
`DiagnosticEvent` values that ends with `.completed(report)`. JavaScript needs
the report as a Promise result and the intermediate events as progress. The
Tabris bridge delivers native events synchronously on the main thread and only
while a listener flag is set, and a `JSFunctionValue` callback may be called at
most once per call if the Promise contract is to hold.

## Decision

1. **One run per plugin object.** A second `diagnose()` while one is in flight
   rejects with `alreadyRunning`. Apps that need parallel runs create a second
   object. The run slot is cleared before its Promise settles, so a `diagnose()`
   issued from the previous run's `.then` is accepted.
2. **Six named events**, one per `DiagnosticEvent` case: `stageStarted`,
   `stageFinished` (`{stage}`), `gatewayResult`, `dnsServerResult`,
   `pingResult`, `httpResult` (the result object spread into the event). The
   `completed` case is not an event; it settles the Promise with the report.
   Events are fired only when the matching listener flag is set.
3. **Exactly one settlement.** Every delivery to JavaScript passes through the
   main actor and checks a run generation counter plus `isDisposed`. `cancel()`
   bumps the generation, cancels the task and rejects the pending Promise with
   `cancelled`; `dispose()` does the same with `disposed` for the run and every
   pending primitive. A late `.completed` from a cancelled run is dropped. The
   library cooperates: cancelling the consuming task terminates the stream, and
   the stream's `onTermination` cancels the diagnosis.
4. **`cancel()` affects only the run.** Primitives are bounded by their own
   timeouts and finish on their own; `dispose()` is the only operation that
   rejects everything.
5. **Errors are `{code, message}` objects**, turned into an `Error` with a `code`
   property by the JavaScript module. Codes: `invalidParameter`,
   `unavailable`, `alreadyRunning`, `cancelled`, `disposed`.

## Consequences

- Progress rendering in an app is a set of typed handlers
  (`onStageStarted`, `onPingResult`, …) with homogeneous payloads; no `switch`
  over an event kind is needed.
- The report shape returned by `diagnose()` is a superset of the primitive
  shapes: gateway and DNS-server items carry `ping` (and `queries`), the
  primitives return the discovery items only.
- `startedAt` is an ISO-8601 string with fractional seconds; JavaScript parses
  it with `new Date(report.startedAt)`.

## Rejected alternatives

- **A single `progress` event with a `type` field.** Forces a tagged union on
  the consumer and `type` collides with the `type` field Tabris puts on every
  event object.
- **Cancel-and-replace on a second `diagnose()`.** Hides a programming error and
  makes the first Promise's fate depend on timing.
- **`cancel()` cancelling in-flight primitives too.** Primitives are short and
  self-bounded; a single-purpose `cancel()` maps one-to-one onto the library's
  run cancellation.
- **Resolving the cancelled Promise with a partial report.** The library emits
  no report for a cancelled run, and a half-filled report would look like a
  finished diagnosis.
