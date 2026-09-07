public enum DiagnosticVerdict: Codable, Sendable, Equatable {
    case healthy
    case noActiveInterface
    case gatewayUnreachable
    case dnsResolutionFailing
    case remoteHostsUnreachable
    case partialConnectivity
    case inconclusive(reason: String)
}

public struct DiagnosticSummary: Codable, Sendable, Equatable {
    public let verdict: DiagnosticVerdict

    public init(verdict: DiagnosticVerdict) {
        self.verdict = verdict
    }

    public var message: String {
        switch verdict {
        case .healthy:
            "Network looks healthy: local interfaces, gateways, DNS and remote hosts all responded."
        case .noActiveInterface:
            "No active network interface with an IP address was found. "
                + "Wi-Fi and cellular appear to be off or disconnected."
        case .gatewayUnreachable:
            "The device has a local IP address but no default gateway answered ping. The router is not responding."
        case .dnsResolutionFailing:
            "Local network is up but host names cannot be resolved. DNS is failing."
        case .remoteHostsUnreachable:
            "Local network and DNS work but none of the remote hosts responded. The servers are unreachable."
        case .partialConnectivity:
            "Some remote hosts responded and some did not. Connectivity is degraded or specific servers are down."
        case let .inconclusive(reason):
            "The diagnosis is inconclusive: \(reason)"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case verdict
        case message
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        verdict = try container.decode(DiagnosticVerdict.self, forKey: .verdict)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(verdict, forKey: .verdict)
        try container.encode(message, forKey: .message)
    }
}
