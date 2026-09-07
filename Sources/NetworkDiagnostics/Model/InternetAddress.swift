import Foundation

public struct InternetAddress: Codable, Sendable, Hashable, CustomStringConvertible {
    public enum Family: String, Codable, Sendable {
        case ipv4
        case ipv6
    }

    public let family: Family
    public let rawBytes: Data

    public init?(family: Family, rawBytes: Data) {
        guard rawBytes.count == family.byteCount else { return nil }
        self.family = family
        self.rawBytes = rawBytes
    }

    public var description: String {
        SocketAddressFormatter.format(family: family, rawBytes: rawBytes) ?? "<invalid \(family.rawValue)>"
    }
}

extension InternetAddress.Family {
    var byteCount: Int {
        switch self {
        case .ipv4: 4
        case .ipv6: 16
        }
    }

    var addressFamily: Int32 {
        switch self {
        case .ipv4: AF_INET
        case .ipv6: AF_INET6
        }
    }
}
