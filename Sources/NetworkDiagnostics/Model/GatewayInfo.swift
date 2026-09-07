public struct DiscoveredGateway: Sendable, Equatable {
    public let address: InternetAddress
    public let interfaceName: String?

    public init(address: InternetAddress, interfaceName: String?) {
        self.address = address
        self.interfaceName = interfaceName
    }
}

public struct GatewayInfo: Codable, Sendable, Equatable {
    public let address: String
    public let interfaceName: String?
    public let ping: PingOutcome

    public init(address: String, interfaceName: String?, ping: PingOutcome) {
        self.address = address
        self.interfaceName = interfaceName
        self.ping = ping
    }
}

public enum GatewayDiscovery: Codable, Sendable, Equatable {
    case found([GatewayInfo])
    case unavailable(reason: String)
}
