@testable import NetworkDiagnostics
import XCTest

final class DNSServerParserTests: XCTestCase {
    func testParsesIPv4AndIPv6Servers() {
        let servers = DNSServerParser.parse([
            SocketAddressFixtures.ipv4("192.168.1.1"),
            SocketAddressFixtures.ipv6("2001:4860:4860::8888"),
            SocketAddressFixtures.ipv4("8.8.4.4"),
        ])

        XCTAssertEqual(servers.map(\.description), ["192.168.1.1", "2001:4860:4860::8888", "8.8.4.4"])
    }

    func testSkipsUnknownFamiliesAndTruncatedRecords() {
        var unknownFamily = SocketAddressFixtures.ipv4("1.2.3.4")
        unknownFamily[1] = UInt8(AF_UNIX)
        let truncated = SocketAddressFixtures.ipv6("::1").prefix(10)

        XCTAssertEqual(DNSServerParser.parse([unknownFamily, Data(truncated), Data()]), [])
    }

    func testEmptyBufferYieldsNoServers() {
        XCTAssertEqual(DNSServerParser.parse([]), [])
    }
}
