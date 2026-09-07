@testable import NetworkDiagnostics
import XCTest

final class DiagnosticReportCodableTests: XCTestCase {
    func testRoundTripPreservesEveryField() throws {
        let report = try fullyPopulatedReport()

        let encoded = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(DiagnosticReport.self, from: encoded)

        XCTAssertEqual(decoded, report)
    }

    func testSummaryEncodesDerivedMessage() throws {
        let encoded = try JSONEncoder().encode(DiagnosticSummary(verdict: .gatewayUnreachable))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(object["message"] as? String, DiagnosticSummary(verdict: .gatewayUnreachable).message)
        XCTAssertNotNil(object["verdict"])
    }

    func testUnavailableDiscoveriesRoundTrip() throws {
        let report = DiagnosticReport(
            startedAt: Date(timeIntervalSince1970: 0),
            durationSeconds: 0,
            interfaces: .unavailable(reason: "getifaddrs: EPERM"),
            gateways: .unavailable(reason: "no path update"),
            dnsServers: .unavailable(reason: "res_9_ninit failed"),
            pingResults: [],
            httpResults: [],
            summary: DiagnosticSummary(
                verdict: .inconclusive(reason: "interface enumeration failed: getifaddrs: EPERM")
            )
        )

        let decoded = try JSONDecoder().decode(DiagnosticReport.self, from: JSONEncoder().encode(report))

        XCTAssertEqual(decoded, report)
    }

    private func fullyPopulatedReport() throws -> DiagnosticReport {
        DiagnosticReport(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 1.25,
            interfaces: .found([
                NetworkInterfaceInfo(
                    name: "en0",
                    ipv4Addresses: ["192.168.1.10"],
                    ipv6Addresses: ["fe80::1"],
                    isUp: true,
                    isLoopback: false
                ),
            ]),
            gateways: .found([gatewayFixture]),
            dnsServers: .found([
                DNSServerInfo(
                    address: "192.168.1.1",
                    ping: .unreachable(sentPackets: 3),
                    queries: [
                        DNSQueryResult(
                            domain: "example.test",
                            outcome: .answered(responseCode: .noError, addresses: ["93.184.216.34"], latencyMs: 12.5)
                        ),
                        DNSQueryResult(
                            domain: "missing.test",
                            outcome: .answered(responseCode: .nameError, addresses: [], latencyMs: 9)
                        ),
                        DNSQueryResult(domain: "slow.test", outcome: .timedOut),
                        DNSQueryResult(domain: "broken.test", outcome: .failed(reason: "connection refused")),
                    ]
                ),
            ]),
            pingResults: pingFixtures,
            httpResults: try httpFixtures(),
            summary: DiagnosticSummary(verdict: .partialConnectivity)
        )
    }

    private var gatewayFixture: GatewayInfo {
        GatewayInfo(
            address: "192.168.1.1",
            interfaceName: "en0",
            ping: .reachable(
                PingStatistics(
                    sentPackets: 3,
                    receivedPackets: 2,
                    minRttMs: 1.5,
                    avgRttMs: 2,
                    maxRttMs: 2.5,
                    packetLossPercent: 33.3
                )
            )
        )
    }

    private var pingFixtures: [PingHostResult] {
        [
            PingHostResult(host: "example.test", resolvedAddress: nil, outcome: .resolutionFailed(reason: "NXDOMAIN")),
            PingHostResult(host: "10.0.0.1", resolvedAddress: "10.0.0.1", outcome: .unreachable(sentPackets: 3)),
            PingHostResult(host: "10.0.0.2", resolvedAddress: "10.0.0.2", outcome: .failed(reason: "socket failed")),
        ]
    }

    private func httpFixtures() throws -> [HttpHostResult] {
        [
            HttpHostResult(
                url: try XCTUnwrap(URL(string: "https://example.test/health")),
                outcome: .response(statusCode: 200, latencyMs: 87.5)
            ),
            HttpHostResult(
                url: try XCTUnwrap(URL(string: "https://down.example.test/")),
                outcome: .failure(.other(description: "URLError -1"))
            ),
        ]
    }
}
