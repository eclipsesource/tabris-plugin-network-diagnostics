# The hard timeout returns even when the operation ignores cancellation

Date: 2026-09-07

## Context

`withHardTimeout(seconds:operation:)` bounds every ping, HTTP probe, DNS query
and gateway discovery. The ported implementation raced the operation against a
sleeping child inside one task group and returned the first result — but a task
group does not leave its scope until every child has finished. When the losing
operation ignored cancellation (a blocked `getaddrinfo` on a background queue, a
continuation nobody resumes), the "hard" timeout waited for it anyway, and with
the plugin that wait became a JavaScript promise that never settled on time.

## Decision

`withHardTimeout` starts the operation and the sleeper as unstructured tasks and
resumes a single continuation from whichever finishes first, guarded by a
one-shot lock. The loser is cancelled but not awaited. Cancelling the caller
cancels both tasks and resumes promptly with whatever the race yields. The
signature and the `nil`-on-timeout contract are unchanged.

## Consequences

- A non-cooperative operation keeps running in its own task until it completes
  or the process exits; its result is dropped. That is the price of returning on
  time and is bounded by the same system limits the caller already faced.
- `TimeoutTests` pins the behaviour with an operation that never resumes.
- The `Duration.milliseconds` helper next to it is renamed
  `networkDiagnosticsMilliseconds`: it is an extension on a standard-library
  type and the most likely name clash with another Swift plugin in the same app.

## Rejected alternatives

- **Keep the task-group race and document the cooperation requirement.** The
  requirement cannot be enforced across `getaddrinfo` and `URLSession`, and the
  JavaScript contract promises a bound.
- **Wrap only `getaddrinfo` in a detached task.** Fixes one service; the helper
  is the single place where the bound is meant to hold.
