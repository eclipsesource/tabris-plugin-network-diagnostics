# ICMP ping is a Swift port of SimplePing's mechanism

Date: 2026-09-02

## Context

The task requires ICMP ping of gateways and configured hosts "using Apple's
SimplePing mechanism", restricted to public API. Apple's SimplePing is an
Objective-C sample built on `CFSocket` scheduled on a run loop. The library is
written in Swift 6 language mode with strict concurrency and exposes an
`async` API, which has no run loop to schedule a `CFSocket` on.

## Decision

`ICMPEchoSession` reimplements SimplePing's mechanism in Swift:

- an unprivileged `SOCK_DGRAM` socket with `IPPROTO_ICMP` / `IPPROTO_ICMPV6`,
  which is what lets SimplePing work without root on iOS;
- echo requests carrying a per-session random 16-bit identifier and an
  incrementing sequence number, replies matched on both so concurrent sessions
  sharing the same kernel demultiplexing do not steal each other's replies;
- RFC 1071 checksum computed and verified for IPv4, left to the kernel for
  IPv6, exactly as SimplePing does;
- the IPv4 header that datagram ICMP sockets prepend to received packets is
  stripped before parsing, as SimplePing does.

Readiness is driven by `DispatchSource.makeReadSource` on a private serial
queue instead of a run loop. Packets are sent one at a time; each waits for its
reply or a per-packet timeout of `timeoutPerHostSeconds / pingPacketCount`, so
a host never takes longer than the configured per-host timeout. The
orchestrator additionally wraps every host in a hard timeout.

Packet encoding, parsing and checksum live in `ICMPPacket` as pure functions
and are covered by byte-level unit tests; the socket-owning session is covered
by loopback integration tests (IPv4 and IPv6).

## Alternatives considered

- **Vendor Apple's Objective-C SimplePing** in a separate C/ObjC package
  target. Rejected: it requires a dedicated thread running a run loop to host
  the `CFSocket`, an Objective-C delegate bridged to Swift continuations, and
  a second language in the package. The download of sample code is also not
  verifiable at build time.
- **TCP or HTTP reachability instead of ICMP.** Rejected: the task mandates
  ICMP and gateways rarely expose TCP services.
- **`NWConnection`.** Rejected: Network.framework offers no ICMP transport.
