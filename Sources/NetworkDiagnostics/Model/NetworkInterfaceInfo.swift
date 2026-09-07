public struct NetworkInterfaceInfo: Codable, Sendable, Equatable {
    public let name: String
    public let ipv4Addresses: [String]
    public let ipv6Addresses: [String]
    public let isUp: Bool
    public let isLoopback: Bool

    public init(name: String, ipv4Addresses: [String], ipv6Addresses: [String], isUp: Bool, isLoopback: Bool) {
        self.name = name
        self.ipv4Addresses = ipv4Addresses
        self.ipv6Addresses = ipv6Addresses
        self.isUp = isUp
        self.isLoopback = isLoopback
    }
}
