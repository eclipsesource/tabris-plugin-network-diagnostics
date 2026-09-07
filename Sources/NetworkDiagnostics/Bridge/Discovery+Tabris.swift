extension NetworkInterfaceInfo: NetworkDiagnosticsRepresentable {
    var tabrisObject: [String: Any] {
        [
            "name": name,
            "ipv4Addresses": ipv4Addresses,
            "ipv6Addresses": ipv6Addresses,
            "isUp": isUp,
            "isLoopback": isLoopback,
        ]
    }
}

extension InterfaceDiscovery: NetworkDiagnosticsRepresentable {
    var tabrisObject: [String: Any] {
        switch self {
        case let .found(interfaces): ["state": "found", "items": interfaces.tabrisObjects]
        case let .unavailable(reason): ["state": "unavailable", "reason": reason]
        }
    }
}

extension DiscoveredGateway: NetworkDiagnosticsRepresentable {
    var tabrisObject: [String: Any] {
        ["address": address.description, "interfaceName": networkDiagnosticsOptional(interfaceName)]
    }
}

extension GatewayInfo: NetworkDiagnosticsRepresentable {
    var tabrisObject: [String: Any] {
        ["address": address, "interfaceName": networkDiagnosticsOptional(interfaceName), "ping": ping.tabrisObject]
    }
}

extension GatewayDiscovery: NetworkDiagnosticsRepresentable {
    var tabrisObject: [String: Any] {
        switch self {
        case let .found(gateways): ["state": "found", "items": gateways.tabrisObjects]
        case let .unavailable(reason): ["state": "unavailable", "reason": reason]
        }
    }
}

extension DNSServerInfo: NetworkDiagnosticsRepresentable {
    var tabrisObject: [String: Any] {
        ["address": address, "ping": ping.tabrisObject, "queries": queries.tabrisObjects]
    }
}

extension DNSServerDiscovery: NetworkDiagnosticsRepresentable {
    var tabrisObject: [String: Any] {
        switch self {
        case let .found(servers): ["state": "found", "items": servers.tabrisObjects]
        case let .unavailable(reason): ["state": "unavailable", "reason": reason]
        }
    }
}
