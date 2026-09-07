# Glossary

| Term | Meaning | Do not use |
|------|---------|------------|
| interface | A network interface reported by `getifaddrs` with at least one IP address (`NetworkInterfaceInfo`) | adapter, NIC |
| gateway | A default-route next hop reported by `NWPath.gateways` (`DiscoveredGateway` before ping, `GatewayInfo` after) | router (only in user-facing summary text) |
| DNS server | A resolver address reported by `res_9_getservers`; pinged and queried during `dnsServerCheck` (`DNSServerInfo`) | nameserver |
| DNS query | One UDP A-record question sent directly to a DNS server on port 53 (`DNSQuerying`, `DNSQueryOutcome`) | lookup, resolution (the latter is reserved for `HostResolving`) |
| test domain | A `dnsTestDomains` entry sent as a DNS query to every DNS server | probe domain |
| ping | ICMP echo request/reply exchange (`Pinging`, `PingOutcome`) | ICMP probe, reachability |
| probe | One HTTP/HTTPS request to a configured URL (`HTTPProbing`, `HttpOutcome`) | request, check |
| host | A `pingHosts` entry before resolution (IP literal or domain name) | target, endpoint |
| address | A resolved IPv4/IPv6 address (`InternetAddress`) | IP, host |
| stage | One phase of a run (`DiagnosticStage`); every stage emits started/finished events | step, phase |
| discovery | The result of a local lookup that can fail: `InterfaceDiscovery`, `GatewayDiscovery`, `DNSServerDiscovery` | lookup, scan |
| outcome | The typed result of one ping or probe: `PingOutcome`, `HttpOutcome` | status, result |
| verdict | The summary classification (`DiagnosticVerdict`); `DiagnosticSummary.message` is its text | diagnosis, conclusion |
| hard timeout | The total budget for one host, `timeoutPerHostSeconds`, enforced by `withHardTimeout` | deadline |
| run | One execution of the all-in-one diagnosis started by `diagnose()`; at most one per plugin object at a time | session, job |
| primitive | One diagnostic building block exposed to JavaScript on its own (`interfaces`, `gateways`, `dnsServers`, `ping`, `dnsQuery`, `http`), implemented by `DiagnosticPrimitives` | helper, utility |
| contract | The JavaScript API in `www/` together with the JSON shapes it returns and the events it emits; changed only as a coordinated migration | interface (reserved for network interfaces), schema |
| Tabris object | The `[String: Any]` form of a model value that crosses the bridge to JavaScript (`NetworkDiagnosticsRepresentable.tabrisObject`); discriminated by a `state` key where the Swift type is an enum | dictionary, payload, JSON (the shape, not the encoding) |
| listener flag | The `@objc` boolean `<event>Listener` that Tabris sets when JavaScript subscribes to a native event | subscription |

## Unit suffix convention

Numeric identifiers carry their unit: `…Seconds` for `TimeInterval` values,
`…Ms` for millisecond doubles, `…Bytes` for sizes, `…Packets` for packet
counts. `Duration` and `Date` typed fields keep plain names.
