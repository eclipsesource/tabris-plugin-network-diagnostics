import Foundation

protocol InterfaceEnumerating: Sendable {
    func enumerateInterfaces() throws -> [NetworkInterfaceInfo]
}

struct GetifaddrsInterfaceEnumerator: InterfaceEnumerating {
    func enumerateInterfaces() throws -> [NetworkInterfaceInfo] {
        var head: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&head) == 0, let head else {
            throw ServiceFailure(
                component: "GetifaddrsInterfaceEnumerator",
                operation: "getifaddrs",
                reason: String(cString: strerror(errno))
            )
        }
        defer { freeifaddrs(head) }
        return InterfaceParser.parse(Self.records(startingAt: head))
    }

    private static func records(startingAt head: UnsafeMutablePointer<ifaddrs>) -> [RawInterfaceAddress] {
        var records: [RawInterfaceAddress] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = head

        while let entry = cursor {
            if let record = record(from: entry.pointee) {
                records.append(record)
            }
            cursor = entry.pointee.ifa_next
        }
        return records
    }

    private static func record(from entry: ifaddrs) -> RawInterfaceAddress? {
        guard let address = entry.ifa_addr else { return nil }
        let family = Int32(address.pointee.sa_family)

        guard family == AF_INET || family == AF_INET6 else { return nil }
        return RawInterfaceAddress(
            name: String(cString: entry.ifa_name),
            flags: entry.ifa_flags,
            socketAddress: Data(bytes: address, count: Int(address.pointee.sa_len))
        )
    }
}
