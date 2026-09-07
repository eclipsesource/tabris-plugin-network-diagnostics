# Diagnostics expose progress as an event stream

Date: 2026-09-02

## Context

The task asks for one asynchronous method returning a `DiagnosticReport`. The
project's guiding principle "long-running operations show progress" requires
that the user sees incremental progress while diagnostics run, and a full run
takes several seconds when hosts do not answer.

## Decision

`NetworkDiagnostics` has one core, `collectReport`, which takes an event sink
and returns the report. Two public entry points wrap it:

- `diagnose(_:) -> AsyncStream<DiagnosticEvent>` yields `stageStarted` /
  `stageFinished` for each `DiagnosticStage`, one `gatewayResult`,
  `pingResult` or `httpResult` per host as soon as it is known, and finally
  `completed(DiagnosticReport)`. Cancelling the stream cancels the run.
- `runDiagnostics(_:) async -> DiagnosticReport` is the task's requested
  signature; it runs the same core with a no-op sink.

Because both share the core, mock and production behaviour cannot diverge
between the two entry points.

## Related modelling decisions

Discovery results are sum types rather than the plain arrays the task sketches:
`InterfaceDiscovery`, `GatewayDiscovery` and `DNSServerDiscovery` each have
`found(...)` and `unavailable(reason:)`. An empty array cannot distinguish
"nothing configured" from "the lookup failed", and the summary must not blame
the network for a failed lookup. `PingOutcome` and `HttpOutcome` follow the
same rule so a result is never a success flag next to a nullable error string.

The hard per-host timeout uses `timeoutPerHostSeconds` as the total budget for
resolving and probing one host; the per-packet ping timeout is derived from it.

## Alternatives considered

- **Only `runDiagnostics`.** Rejected: the UI would show nothing until the
  slowest host times out, violating the progress principle.
- **A delegate or callback closure parameter.** Rejected: `AsyncStream` is the
  idiomatic Swift 6 shape, cancellable, and testable by collecting events.
- **Optional fields for not-yet-known values** (`ping: PingOutcome?`).
  Rejected: the final report would carry `nil` states that are illegal after
  completion; `DiscoveredGateway` and `GatewayInfo` are separate types instead.
