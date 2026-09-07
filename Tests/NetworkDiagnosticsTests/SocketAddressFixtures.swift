import Foundation
@testable import NetworkDiagnostics

/// Builds raw `sockaddr_in` / `sockaddr_in6` byte buffers the way the kernel
/// and libresolv hand them out, so parsers can be tested without any socket.
enum SocketAddressFixtures {
    static func ipv4(_ literal: String) -> Data {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        precondition(inet_pton(AF_INET, literal, &address.sin_addr) == 1, "invalid IPv4 literal \(literal)")
        return withUnsafeBytes(of: &address) { Data($0) }
    }

    static func ipv6(_ literal: String) -> Data {
        var address = sockaddr_in6()
        address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        address.sin6_family = sa_family_t(AF_INET6)
        precondition(inet_pton(AF_INET6, literal, &address.sin6_addr) == 1, "invalid IPv6 literal \(literal)")
        return withUnsafeBytes(of: &address) { Data($0) }
    }

    static func internetAddress(_ literal: String) throws -> InternetAddress {
        let bytes = literal.contains(":") ? ipv6(literal) : ipv4(literal)
        guard let address = SocketAddressFormatter.internetAddress(fromSocketAddress: bytes) else {
            throw FixtureError.invalidLiteral(literal)
        }
        return address
    }

    enum FixtureError: Error {
        case invalidLiteral(String)
    }
}
