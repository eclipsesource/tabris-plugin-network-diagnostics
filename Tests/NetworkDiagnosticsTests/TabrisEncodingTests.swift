import Foundation
@testable import NetworkDiagnostics
import XCTest

/// The `[String: Any]` shapes are the JavaScript contract of the plugin. Every
/// expected dictionary here is spelled out literally so a change to the contract
/// shows up as a diff in this file, and every object must survive
/// `JSONSerialization` because the Tabris bridge accepts only plain
/// string/number/bool/null/array/dictionary values.
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
            TabrisError(code: .disposed, message: "gone").tabrisObject,
            equals: ["code": "disposed", "message": "gone"]
        )
    }

    func testOptionalHelperMapsNilToNull() {
        XCTAssertTrue(tabrisOptional(nil as String?) is NSNull)
        XCTAssertEqual(tabrisOptional("en0") as? String, "en0")
    }

    private func assertTabrisObject(
        _ actual: [String: Any],
        equals expected: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            JSONSerialization.isValidJSONObject(actual),
            "object contains values the bridge cannot encode: \(actual)",
            file: file,
            line: line
        )
        XCTAssertEqual(canonicalJSON(actual), canonicalJSON(expected), file: file, line: line)
    }

    /// Both dictionaries are serialised with sorted keys, so two shapes are equal
    /// exactly when a JavaScript consumer would see the same JSON text.
    private func canonicalJSON(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let json = String(bytes: data, encoding: .utf8) else {
            return "<not serialisable: \(object)>"
        }
        return json
    }
}
