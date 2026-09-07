public enum InterfaceDiscovery: Codable, Sendable, Equatable {
    case found([NetworkInterfaceInfo])
    case unavailable(reason: String)
}
