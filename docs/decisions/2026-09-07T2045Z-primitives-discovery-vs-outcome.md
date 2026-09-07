# Primitives: discoveries reject, probes return outcomes

Date: 2026-09-07

## Context

Besides the all-in-one `diagnose()`, the plugin exposes the library's building
blocks individually to JavaScript: `interfaces()`, `gateways()`, `dnsServers()`,
`ping()`, `dnsQuery()` and `http()`. Each needs an answer to three questions:
when does the Promise reject, what does `gateways()` return, and where does a
DNS query get its server from. The library already draws one line the glossary
records: a *discovery* is a local lookup that can fail as a whole
(`InterfaceDiscovery.unavailable(reason:)`), an *outcome* is the typed result of
one probe and never throws (`PingOutcome.failed(reason:)`,
`HttpOutcome.failure(_:)`, `DNSQueryOutcome.timedOut`).

## Decision

1. **Discovery primitives reject, probe primitives never reject for network
   reasons.** `interfaces()`, `gateways()` and `dnsServers()` reject with code
   `unavailable` and the service's own description when the underlying call
   throws; `ping()`, `dnsQuery()` and `http()` always resolve with an object
   whose `outcome.state` names the result. Every method rejects with
   `invalidParameter` for malformed input, listing the offending key and value.
2. **`gateways()` is discovery only** and returns `{address, interfaceName}`
   items without a ping; the report's gateway items additionally carry `ping`.
   Composition is `ping(gateway.address)`.
3. **`dnsQuery()` requires `server`.** Defaulting to the first system resolver
   would couple a discovery failure into a probe call and hide which resolver
   answered; `const [server] = await nd.dnsServers()` is the one-line
   composition. The result echoes `server` next to `domain`, `outcome` and
   `isResolved`.
4. **URLs are validated, not silently dropped.** `http()` accepts `http` and
   `https` URLs with a host; anything else is an `invalidParameter` rejection.
5. **One code path for run and primitives.** The host-ping (resolve, hard
   timeout, ICMP), HTTP-probe and DNS-query logic moved from `ProbeRunner` into
   `HostProbes`, which both the orchestrated run and `DiagnosticPrimitives` use,
   so the two entry points cannot drift apart.

## Consequences

- `NetworkDiagnosticsParameters` is the single place that turns the JavaScript dictionary
  into typed requests, with defaults `timeoutSeconds` 3, `packetCount` 3 and
  `method` `HEAD`; its tests pin every accepted shape and every rejection.
- Result shapes are encoded once per model type (`NetworkDiagnosticsRepresentable`); the
  primitive shapes are subsets of the report shapes, so an app can reuse the
  same rendering code.
- `ProbeRunner` keeps orchestration only (stage tracking, ordering, fan-out).

## Rejected alternatives

- **Default `dnsQuery()` server = first system resolver.** Convenient, but a
  failed resolver lookup would turn a probe into a rejection and the caller
  could not tell which server answered.
- **`gateways()` pinging every gateway.** Duplicates the run's gateway stage
  and makes the "discovery only" answer slow; `ping()` composes.
- **Dropping invalid URLs silently, as the SwiftUI demo did.** Contradicts
  "uncertainty must not be hidden" for a public API.
- **Rejecting probes on network failure.** Mixes transport failures into the
  error channel and forces every caller into try/catch for expected outcomes.
