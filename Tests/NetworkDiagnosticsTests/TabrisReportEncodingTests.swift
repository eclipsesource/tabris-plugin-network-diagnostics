import Foundation
@testable import NetworkDiagnostics
import XCTest

/// The report shape is the return value of `diagnose()`; the summary carries the
/// verdict as a name plus the derived message, and `startedAt` is ISO-8601 with
/// fractional seconds so `JSON.stringify` and `new Date()` round-trip it.
final class TabrisReportEncodingTests: XCTestCase {
    func testReportEncodesEverySection() throws {
        let url = try XCTUnwrap(URL(string: "https://example.test/health"))
        let report = DiagnosticReport(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 1.25,
            interfaces: .found([wifi]),
            gateways: .found([gateway]),
            dnsServers: .unavailable(reason: "res_9_ninit failed"),
            pingResults: [
                PingHostResult(host: "10.0.0.1", resolvedAddress: "10.0.0.1", outcome: .failed(reason: "socket")),
            ],
            httpResults: [HttpHostResult(url: url, outcome: .response(statusCode: 200, latencyMs: 87.5))],
            summary: DiagnosticSummary(verdict: .partialConnectivity)
        )

        assertTabrisObject(
            report.tabrisObject,
            equals: [
                "startedAt": "2023-11-14T22:13:20.000Z",
                "durationSeconds": 1.25,
                "interfaces": ["state": "found", "items": [encodedWifi]],
                "gateways": ["state": "found", "items": [encodedGateway]],
                "dnsServers": ["state": "unavailable", "reason": "res_9_ninit failed"],
                "pingResults": [
                    [
                        "host": "10.0.0.1",
                        "resolvedAddress": "10.0.0.1",
                        "outcome": ["state": "failed", "reason": "socket"],
                    ],
                ],
                "httpResults": [
                    [
                        "url": "https://example.test/health",
                        "outcome": ["state": "response", "statusCode": 200, "latencyMs": 87.5],
                    ],
                ],
                "summary": [
                    "verdict": "partialConnectivity",
                    "message": DiagnosticSummary(verdict: .partialConnectivity).message,
                ],
            ]
        )
    }

    func testSummaryNamesEveryVerdictAndAddsTheReasonOnlyWhenInconclusive() {
        let verdicts: [(DiagnosticVerdict, String)] = [
            (.healthy, "healthy"),
            (.noActiveInterface, "noActiveInterface"),
            (.gatewayUnreachable, "gatewayUnreachable"),
            (.dnsResolutionFailing, "dnsResolutionFailing"),
            (.remoteHostsUnreachable, "remoteHostsUnreachable"),
            (.partialConnectivity, "partialConnectivity"),
        ]

        for (verdict, name) in verdicts {
            let summary = DiagnosticSummary(verdict: verdict)

            assertTabrisObject(summary.tabrisObject, equals: ["verdict": name, "message": summary.message])
        }
        let inconclusive = DiagnosticSummary(verdict: .inconclusive(reason: "no hosts"))

        assertTabrisObject(
            inconclusive.tabrisObject,
            equals: ["verdict": "inconclusive", "reason": "no hosts", "message": inconclusive.message]
        )
    }

    func testStartedAtKeepsFractionalSeconds() {
        let report = DiagnosticReport(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000.25),
            durationSeconds: 0,
            interfaces: .found([]),
            gateways: .found([]),
            dnsServers: .found([]),
            pingResults: [],
            httpResults: [],
            summary: DiagnosticSummary(verdict: .healthy)
        )

        XCTAssertEqual(report.tabrisObject["startedAt"] as? String, "2023-11-14T22:13:20.250Z")
    }

    private let wifi = NetworkInterfaceInfo(
        name: "en0",
        ipv4Addresses: ["192.168.1.10"],
        ipv6Addresses: [],
        isUp: true,
        isLoopback: false
    )

    private let encodedWifi: [String: Any] = [
        "name": "en0",
        "ipv4Addresses": ["192.168.1.10"],
        "ipv6Addresses": [],
        "isUp": true,
        "isLoopback": false,
    ]

    private let gateway = GatewayInfo(address: "192.168.1.1", interfaceName: "en0", ping: .unreachable(sentPackets: 3))

    private let encodedGateway: [String: Any] = [
        "address": "192.168.1.1",
        "interfaceName": "en0",
        "ping": ["state": "unreachable", "sentPackets": 3],
    ]
}
