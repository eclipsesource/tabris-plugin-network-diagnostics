enum SummaryBuilder {
    static func summarize(
        interfaces: InterfaceDiscovery,
        gateways: GatewayDiscovery,
        dnsServers: DNSServerDiscovery,
        pingResults: [PingHostResult],
        httpResults: [HttpHostResult]
    ) -> DiagnosticSummary {
        DiagnosticSummary(
            verdict: verdict(
                interfaces: interfaces,
                gateways: gateways,
                dnsServers: dnsServers,
                pingResults: pingResults,
                httpResults: httpResults
            )
        )
    }

    private static func verdict(
        interfaces: InterfaceDiscovery,
        gateways: GatewayDiscovery,
        dnsServers: DNSServerDiscovery,
        pingResults: [PingHostResult],
        httpResults: [HttpHostResult]
    ) -> DiagnosticVerdict {
        switch interfaces {
        case let .unavailable(reason):
            return .inconclusive(reason: "interface enumeration failed: \(reason)")
        case let .found(list) where !list.contains(where: \.isActiveNonLoopback):
            return .noActiveInterface
        case .found:
            break
        }
        if case let .found(list) = gateways, !list.isEmpty, !list.contains(where: \.isReachable) {
            return .gatewayUnreachable
        }
        if case let .found(servers) = dnsServers,
           servers.contains(where: \.wasQueried),
           !servers.contains(where: \.resolvesAnyDomain) {
            return .dnsResolutionFailing
        }
        return remoteVerdict(pingResults: pingResults, httpResults: httpResults)
    }

    private static func remoteVerdict(
        pingResults: [PingHostResult],
        httpResults: [HttpHostResult]
    ) -> DiagnosticVerdict {
        let probeCount = pingResults.count + httpResults.count
        let failedCount = pingResults.filter { !$0.isSuccess }.count + httpResults.filter { !$0.isSuccess }.count
        let dnsFailureCount = pingResults.filter(\.isDNSFailure).count + httpResults.filter(\.isDNSFailure).count

        guard probeCount > 0 else {
            return .inconclusive(reason: "no ping or HTTP hosts were configured")
        }
        if dnsFailureCount > 0, dnsFailureCount == failedCount {
            return .dnsResolutionFailing
        }
        if failedCount == probeCount {
            return .remoteHostsUnreachable
        }
        return failedCount > 0 ? .partialConnectivity : .healthy
    }
}

private extension NetworkInterfaceInfo {
    var isActiveNonLoopback: Bool {
        isUp && !isLoopback && (!ipv4Addresses.isEmpty || !ipv6Addresses.isEmpty)
    }
}

private extension GatewayInfo {
    var isReachable: Bool {
        if case .reachable = ping { true } else { false }
    }
}

private extension DNSServerInfo {
    var wasQueried: Bool {
        !queries.isEmpty
    }

    var resolvesAnyDomain: Bool {
        queries.contains(where: \.isResolved)
    }
}

private extension PingHostResult {
    var isSuccess: Bool {
        if case .reachable = outcome { true } else { false }
    }

    var isDNSFailure: Bool {
        if case .resolutionFailed = outcome { true } else { false }
    }
}

private extension HttpHostResult {
    var isSuccess: Bool {
        if case .response = outcome { true } else { false }
    }

    var isDNSFailure: Bool {
        outcome == .failure(.dnsResolutionFailed)
    }
}
