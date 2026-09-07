import Foundation
@testable import NetworkDiagnostics
import XCTest

/// Ping, HTTP and DNS outcomes of the JavaScript contract: every enum case has
/// a `state`, associated values sit flat next to it, optionals become `null`.
final class TabrisOutcomeEncodingTests: XCTestCase {
    private struct ResponseCodeCase {
        let code: DNSResponseCode
        let name: String
        let rcode: Int
    }

    func testPingOutcomesFlattenTheirPayloadNextToTheState() {
        let statistics = PingStatistics(
            sentPackets: 3,
            receivedPackets: 2,
            minRttMs: 1.5,
            avgRttMs: 2,
            maxRttMs: 2.5,
            packetLossPercent: 33.3
        )

        assertTabrisObject(
            PingOutcome.reachable(statistics).tabrisObject,
            equals: [
                "state": "reachable",
                "sentPackets": 3,
                "receivedPackets": 2,
                "minRttMs": 1.5,
                "avgRttMs": 2,
                "maxRttMs": 2.5,
                "packetLossPercent": 33.3,
            ]
        )
        assertTabrisObject(
            PingOutcome.unreachable(sentPackets: 3).tabrisObject,
            equals: ["state": "unreachable", "sentPackets": 3]
        )
        assertTabrisObject(
            PingOutcome.resolutionFailed(reason: "NXDOMAIN").tabrisObject,
            equals: ["state": "resolutionFailed", "reason": "NXDOMAIN"]
        )
        assertTabrisObject(
            PingOutcome.failed(reason: "socket failed").tabrisObject,
            equals: ["state": "failed", "reason": "socket failed"]
        )
    }

    func testPingHostResultUsesNullForAnUnresolvedAddress() {
        let unresolved = PingHostResult(
            host: "example.test",
            resolvedAddress: nil,
            outcome: .failed(reason: "timeout")
        )
        let resolved = PingHostResult(
            host: "10.0.0.1",
            resolvedAddress: "10.0.0.1",
            outcome: .unreachable(sentPackets: 3)
        )

        assertTabrisObject(
            unresolved.tabrisObject,
            equals: [
                "host": "example.test",
                "resolvedAddress": NSNull(),
                "outcome": ["state": "failed", "reason": "timeout"],
            ]
        )
        assertTabrisObject(
            resolved.tabrisObject,
            equals: [
                "host": "10.0.0.1",
                "resolvedAddress": "10.0.0.1",
                "outcome": ["state": "unreachable", "sentPackets": 3],
            ]
        )
    }

    func testHttpOutcomesNameEveryFailure() throws {
        let url = try XCTUnwrap(URL(string: "https://example.test/health"))
        let failures: [(HttpFailure, [String: Any])] = [
            (.dnsResolutionFailed, ["state": "failure", "failure": "dnsResolutionFailed"]),
            (.tlsHandshakeFailed, ["state": "failure", "failure": "tlsHandshakeFailed"]),
            (.connectionRefused, ["state": "failure", "failure": "connectionRefused"]),
            (.timedOut, ["state": "failure", "failure": "timedOut"]),
            (.networkUnavailable, ["state": "failure", "failure": "networkUnavailable"]),
            (
                .other(description: "URLError -1"),
                ["state": "failure", "failure": "other", "description": "URLError -1"]
            ),
        ]

        assertTabrisObject(
            HttpHostResult(url: url, outcome: .response(statusCode: 200, latencyMs: 87.5)).tabrisObject,
            equals: [
                "url": "https://example.test/health",
                "outcome": ["state": "response", "statusCode": 200, "latencyMs": 87.5],
            ]
        )
        for (failure, expected) in failures {
            assertTabrisObject(HttpOutcome.failure(failure).tabrisObject, equals: expected)
        }
    }

    func testDNSQueryOutcomesCarryTheResponseCodeAsNameAndNumber() {
        let codes = [
            ResponseCodeCase(code: .noError, name: "noError", rcode: 0),
            ResponseCodeCase(code: .formatError, name: "formatError", rcode: 1),
            ResponseCodeCase(code: .serverFailure, name: "serverFailure", rcode: 2),
            ResponseCodeCase(code: .nameError, name: "nameError", rcode: 3),
            ResponseCodeCase(code: .notImplemented, name: "notImplemented", rcode: 4),
            ResponseCodeCase(code: .refused, name: "refused", rcode: 5),
            ResponseCodeCase(code: .other(code: 9), name: "other", rcode: 9),
        ]

        for responseCode in codes {
            let outcome = DNSQueryOutcome.answered(
                responseCode: responseCode.code,
                addresses: ["17.253.144.10"],
                latencyMs: 4
            )

            assertTabrisObject(
                outcome.tabrisObject,
                equals: [
                    "state": "answered",
                    "responseCode": responseCode.name,
                    "rcode": responseCode.rcode,
                    "addresses": ["17.253.144.10"],
                    "latencyMs": 4,
                ]
            )
        }
        assertTabrisObject(DNSQueryOutcome.timedOut.tabrisObject, equals: ["state": "timedOut"])
        assertTabrisObject(
            DNSQueryOutcome.failed(reason: "connection refused").tabrisObject,
            equals: ["state": "failed", "reason": "connection refused"]
        )
    }

    func testDNSQueryResultAddsTheServerOnlyForThePrimitive() throws {
        let result = DNSQueryResult(
            domain: "apple.com",
            outcome: .answered(responseCode: .noError, addresses: ["17.253.144.10"], latencyMs: 4)
        )
        let server = try XCTUnwrap(InternetAddress(literal: "192.168.1.1"))
        let nested: [String: Any] = [
            "domain": "apple.com",
            "isResolved": true,
            "outcome": [
                "state": "answered",
                "responseCode": "noError",
                "rcode": 0,
                "addresses": ["17.253.144.10"],
                "latencyMs": 4,
            ],
        ]

        assertTabrisObject(result.tabrisObject, equals: nested)
        assertTabrisObject(
            result.tabrisObject(server: server),
            equals: nested.merging(["server": "192.168.1.1"]) { _, server in server }
        )
    }
}
