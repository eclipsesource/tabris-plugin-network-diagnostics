import Foundation

struct RawInterfaceAddress: Sendable, Equatable {
    let name: String
    let flags: UInt32
    let socketAddress: Data
}

enum InterfaceParser {
    static func parse(_ records: [RawInterfaceAddress]) -> [NetworkInterfaceInfo] {
        var order: [String] = []
        var grouped: [String: [RawInterfaceAddress]] = [:]

        for record in records {
            if grouped[record.name] == nil {
                order.append(record.name)
            }
            grouped[record.name, default: []].append(record)
        }
        return order.compactMap { name in
            grouped[name].flatMap { interface(named: name, records: $0) }
        }
    }

    private static func interface(named name: String, records: [RawInterfaceAddress]) -> NetworkInterfaceInfo? {
        guard let flags = records.first?.flags else { return nil }
        let addresses = records.compactMap {
            SocketAddressFormatter.internetAddress(fromSocketAddress: $0.socketAddress)
        }

        return NetworkInterfaceInfo(
            name: name,
            ipv4Addresses: addresses.filter { $0.family == .ipv4 }.map(\.description),
            ipv6Addresses: addresses.filter { $0.family == .ipv6 }.map(\.description),
            isUp: flags & UInt32(IFF_UP) != 0,
            isLoopback: flags & UInt32(IFF_LOOPBACK) != 0
        )
    }
}
