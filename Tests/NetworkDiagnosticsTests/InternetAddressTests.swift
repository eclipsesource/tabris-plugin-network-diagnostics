@testable import NetworkDiagnostics
import XCTest

/// `InternetAddress(literal:)` is how a DNS server address typed in JavaScript
/// becomes a value the querier can use.
final class InternetAddressTests: XCTestCase {
    func testParsesIPv4Literals() throws {
        let address = try XCTUnwrap(InternetAddress(literal: "192.168.8.1"))

        XCTAssertEqual(address.family, .ipv4)
        XCTAssertEqual(address.description, "192.168.8.1")
    }

    func testParsesIPv6Literals() throws {
        let address = try XCTUnwrap(InternetAddress(literal: "fe80::1"))

        XCTAssertEqual(address.family, .ipv6)
        XCTAssertEqual(address.description, "fe80::1")
        XCTAssertEqual(InternetAddress(literal: "::1")?.description, "::1")
    }

    func testRejectsHostNamesAndMalformedLiterals() {
        XCTAssertNil(InternetAddress(literal: "dns.local"))
        XCTAssertNil(InternetAddress(literal: "192.168.8"))
        XCTAssertNil(InternetAddress(literal: "192.168.8.1:53"))
        XCTAssertNil(InternetAddress(literal: ""))
    }
}
