import Foundation
@testable import NetworkDiagnostics
import XCTest

/// Gateway and DNS-server shapes of the JavaScript contract. The `gateways()`
/// primitive returns discovery items without a ping; the report's items carry
/// one — both shapes are pinned here.
final class TabrisDiscoveryEncodingTests: XCTestCase {
    func testDiscoveredGatewayUsesNullForAMissingInterfaceName() throws {
        let address = try XCTUnwrap(InternetAddress(literal: "192.168.1.1"))

        assertTabrisObject(
            DiscoveredGateway(address: address, interfaceName: nil).tabrisObject,
            equals: ["address": "192.168.1.1", "interfaceName": NSNull()]
        )
        assertTabrisObject(
            DiscoveredGateway(address: address, interfaceName: "en0").tabrisObject,
            equals: ["address": "192.168.1.1", "interfaceName": "en0"]
        )
    }

    func testGatewayDiscoveryNestsThePingOutcome() {
        let gateway = GatewayInfo(address: "192.168.1.1", interfaceName: "en0", ping: .unreachable(sentPackets: 3))

        assertTabrisObject(
            GatewayDiscovery.found([gateway]).tabrisObject,
            equals: [
                "state": "found",
                "items": [
                    [
                        "address": "192.168.1.1",
                        "interfaceName": "en0",
                        "ping": ["state": "unreachable", "sentPackets": 3],
                    ],
                ],
            ]
        )
        assertTabrisObject(
            GatewayDiscovery.unavailable(reason: "no path update").tabrisObject,
            equals: ["state": "unavailable", "reason": "no path update"]
        )
    }

    func testDNSServerDiscoveryNestsQueries() {
        let server = DNSServerInfo(
            address: "192.168.1.1",
            ping: .failed(reason: "timeout"),
            queries: [DNSQueryResult(domain: "slow.test", outcome: .timedOut)]
        )

        assertTabrisObject(
            DNSServerDiscovery.found([server]).tabrisObject,
            equals: [
                "state": "found",
                "items": [
                    [
                        "address": "192.168.1.1",
                        "ping": ["state": "failed", "reason": "timeout"],
                        "queries": [
                            ["domain": "slow.test", "isResolved": false, "outcome": ["state": "timedOut"]],
                        ],
                    ],
                ],
            ]
        )
        assertTabrisObject(
            DNSServerDiscovery.unavailable(reason: "res_9_ninit").tabrisObject,
            equals: ["state": "unavailable", "reason": "res_9_ninit"]
        )
    }
}
