import Foundation

protocol HostResolving: Sendable {
    func resolve(host: String) async throws -> [InternetAddress]
}

struct GetaddrinfoHostResolver: HostResolving {
    func resolve(host: String) async throws -> [InternetAddress] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Self.resolveBlocking(host))
            }
        }
    }

    private static func resolveBlocking(_ host: String) -> Result<[InternetAddress], ServiceFailure> {
        var hints = addrinfo()
        var list: UnsafeMutablePointer<addrinfo>?

        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_DGRAM
        let status = getaddrinfo(host, nil, &hints, &list)

        guard status == 0 else {
            return .failure(
                ServiceFailure(
                    component: "GetaddrinfoHostResolver",
                    operation: "getaddrinfo(\(host))",
                    reason: String(cString: gai_strerror(status))
                )
            )
        }
        defer { freeaddrinfo(list) }
        return .success(addresses(startingAt: list))
    }

    private static func addresses(startingAt list: UnsafeMutablePointer<addrinfo>?) -> [InternetAddress] {
        var addresses: [InternetAddress] = []
        var cursor = list

        while let entry = cursor {
            if let socketAddress = entry.pointee.ai_addr,
               let address = SocketAddressFormatter.internetAddress(
                fromSocketAddress: Data(bytes: socketAddress, count: Int(entry.pointee.ai_addrlen))
               ),
               !addresses.contains(address) {
                addresses.append(address)
            }
            cursor = entry.pointee.ai_next
        }
        return addresses.filter { $0.family == .ipv4 } + addresses.filter { $0.family == .ipv6 }
    }
}
