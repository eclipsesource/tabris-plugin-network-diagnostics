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

    public init?(literal: String) {
        var ipv4 = in_addr()
        var ipv6 = in6_addr()

        if inet_pton(AF_INET, literal, &ipv4) == 1 {
            self.init(family: .ipv4, rawBytes: withUnsafeBytes(of: &ipv4) { Data($0) })
        } else if inet_pton(AF_INET6, literal, &ipv6) == 1 {
            self.init(family: .ipv6, rawBytes: withUnsafeBytes(of: &ipv6) { Data($0) })
        } else {
            return nil
        }
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
