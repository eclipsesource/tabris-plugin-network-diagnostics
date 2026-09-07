import Foundation

enum SocketAddressFormatter {
    static func format(family: InternetAddress.Family, rawBytes: Data) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let formatted = rawBytes.withUnsafeBytes { raw in
            inet_ntop(family.addressFamily, raw.baseAddress, &buffer, socklen_t(buffer.count))
        }

        guard formatted != nil else { return nil }
        return buffer.withUnsafeBufferPointer { pointer in
            pointer.baseAddress.flatMap { String(validatingCString: $0) }
        }
    }

    static func internetAddress(fromSocketAddress bytes: Data) -> InternetAddress? {
        guard bytes.count >= 2 else { return nil }
        let family = Int32(bytes[bytes.startIndex + 1])
        switch family {
        case AF_INET:
            return slice(bytes, offset: 4, family: .ipv4)
        case AF_INET6:
            return slice(bytes, offset: 8, family: .ipv6)
        default:
            return nil
        }
    }

    private static func slice(_ bytes: Data, offset: Int, family: InternetAddress.Family) -> InternetAddress? {
        let start = bytes.startIndex + offset
        let end = start + family.byteCount

        guard bytes.endIndex >= end else { return nil }
        return InternetAddress(family: family, rawBytes: Data(bytes[start..<end]))
    }
}
