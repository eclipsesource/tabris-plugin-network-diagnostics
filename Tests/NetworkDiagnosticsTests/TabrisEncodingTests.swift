import Foundation
@testable import NetworkDiagnostics
import XCTest

/// Interface and error shapes of the JavaScript contract. Every expected
/// dictionary is spelled out literally so a change to the contract shows up as
/// a diff in this file.
final class TabrisEncodingTests: XCTestCase {
    func testInterfaceEncodesEveryField() {
        let interface = NetworkInterfaceInfo(
            name: "en0",
            ipv4Addresses: ["192.168.1.10"],
            ipv6Addresses: ["fe80::1"],
            isUp: true,
            isLoopback: false
        )

        assertTabrisObject(
            interface.tabrisObject,
            equals: [
                "name": "en0",
                "ipv4Addresses": ["192.168.1.10"],
                "ipv6Addresses": ["fe80::1"],
                "isUp": true,
                "isLoopback": false,
            ]
        )
    }

    func testFoundInterfaceDiscoveryUsesTheStateDiscriminator() {
        let discovery = InterfaceDiscovery.found([
            NetworkInterfaceInfo(
                name: "lo0",
                ipv4Addresses: ["127.0.0.1"],
                ipv6Addresses: ["::1"],
                isUp: true,
                isLoopback: true
            ),
        ])

        assertTabrisObject(
            discovery.tabrisObject,
            equals: [
                "state": "found",
                "items": [
                    [
                        "name": "lo0",
                        "ipv4Addresses": ["127.0.0.1"],
                        "ipv6Addresses": ["::1"],
                        "isUp": true,
                        "isLoopback": true,
                    ],
                ],
            ]
        )
    }

    func testUnavailableInterfaceDiscoveryCarriesTheReason() {
        assertTabrisObject(
            InterfaceDiscovery.unavailable(reason: "getifaddrs: EPERM").tabrisObject,
            equals: ["state": "unavailable", "reason": "getifaddrs: EPERM"]
        )
    }

    func testTabrisErrorEncodesCodeAndMessage() {
        assertTabrisObject(
            NetworkDiagnosticsError(code: .disposed, message: "gone").tabrisObject,
            equals: ["code": "disposed", "message": "gone"]
        )
    }

    func testOptionalHelperMapsNilToNull() {
        XCTAssertTrue(networkDiagnosticsOptional(nil as String?) is NSNull)
        XCTAssertEqual(networkDiagnosticsOptional("en0") as? String, "en0")
    }
}
