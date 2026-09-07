# DNS servers are pinged and queried directly over UDP port 53

Date: 2026-09-02

## Context

Resolving `pingHosts` and `httpHosts` through `getaddrinfo` exercises the
system resolver, which on iOS goes through mDNSResponder, its cache, and
whatever server it picks. When resolution fails that path cannot say which of
the configured DNS servers is at fault, and when it succeeds from cache it says
nothing about the servers at all. The user needs a verdict per DNS server.

## Decision

Every DNS server reported by `res_9_getservers` gets its own `dnsServerCheck`
stage entry that runs two things concurrently:

- an ICMP ping through the same `Pinging` service used for gateways;
- one DNS A query per `dnsTestDomains` entry, built by the pure `DNSMessage`
  codec and sent with `NWConnection` over UDP to port 53 of that server.

The query is a standard recursive question (RFC 1035 §4.1); the response is
accepted only if its id matches the query, then its RCODE and A/AAAA answers
are reported as `DNSQueryOutcome.answered`. Timeouts and transport failures are
separate cases. `DNSQueryResult.isResolved` means NOERROR with at least one
address; `SummaryBuilder` reports `dnsResolutionFailing` when servers were
queried and none resolved anything, before it looks at remote probes.

`dnsTestDomains` has no default in the library: a generic component must not
hard-code a vendor's domain, and an empty list simply skips the queries while
keeping the ping. The demo app pre-fills `apple.com`.

`UDPDNSQuerier` takes the port as an initialiser argument so integration tests
can point it at an in-process `NWListener` responder on loopback; production
always uses 53.

## Alternatives considered

- **Reuse `getaddrinfo` per server** by manipulating resolver state. Rejected:
  `res_9` state manipulation is not thread-safe and still goes through the
  system resolver's policies.
- **TCP port 53 connection test only.** Rejected: proves reachability, not that
  the server answers; many resolvers do not listen on TCP.
- **DNS over HTTPS/TLS.** Rejected: the configured servers are plain resolvers
  handed out by DHCP; encrypted transports test something else.
