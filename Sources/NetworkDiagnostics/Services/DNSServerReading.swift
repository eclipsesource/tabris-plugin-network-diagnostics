#if canImport(CResolv)
import CResolv
#endif
import Foundation

protocol DNSServerReading: Sendable {
    func readDNSServers() throws -> [InternetAddress]
}

struct ResolvDNSServerReader: DNSServerReading {
    private static let capacity = 8

    func readDNSServers() throws -> [InternetAddress] {
        var storage = [sockaddr_storage](repeating: sockaddr_storage(), count: Self.capacity)
        let count = Int(cresolv_copy_dns_servers(&storage, Int32(Self.capacity)))

        guard count >= 0 else {
            throw ServiceFailure(
                component: "ResolvDNSServerReader",
                operation: "res_9_ninit",
                reason: "resolver state could not be initialised"
            )
        }
        return DNSServerParser.parse(storage.prefix(count).map { withUnsafeBytes(of: $0) { Data($0) } })
    }
}
