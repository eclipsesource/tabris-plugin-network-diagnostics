import Foundation

enum DNSServerParser {
    static func parse(_ socketAddresses: [Data]) -> [InternetAddress] {
        socketAddresses.compactMap(SocketAddressFormatter.internetAddress(fromSocketAddress:))
    }
}
