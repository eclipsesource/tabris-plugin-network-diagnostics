extension NetworkInterfaceInfo: TabrisRepresentable {
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

extension InterfaceDiscovery: TabrisRepresentable {
    var tabrisObject: [String: Any] {
        switch self {
        case let .found(interfaces): ["state": "found", "items": interfaces.tabrisObjects]
        case let .unavailable(reason): ["state": "unavailable", "reason": reason]
        }
    }
}
