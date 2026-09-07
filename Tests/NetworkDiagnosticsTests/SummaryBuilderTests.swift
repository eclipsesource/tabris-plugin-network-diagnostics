@testable import NetworkDiagnostics
import XCTest

final class SummaryBuilderTests: XCTestCase {
    private let wifi = NetworkInterfaceInfo(
        name: "en0",
        ipv4Addresses: ["192.168.1.10"],
        ipv6Addresses: [],
        isUp: true,
        isLoopback: false
    )
    private let loopback = NetworkInterfaceInfo(
        name: "lo0",
        ipv4Addresses: ["127.0.0.1"],
        ipv6Addresses: ["::1"],
        isUp: true,
        isLoopback: true
    )
    private let reachableStatistics = PingStatistics(
        sentPackets: 3,
        receivedPackets: 3,
        minRttMs: 1,
        avgRttMs: 1,
        maxRttMs: 1,
        packetLossPercent: 0
    )

    private func gateway(_ ping: PingOutcome) -> GatewayInfo {
        GatewayInfo(address: "192.168.1.1", interfaceName: "en0", ping: ping)
    }

    private func http(_ outcome: HttpOutcome, path: String = "/") throws -> HttpHostResult {
        HttpHostResult(url: try XCTUnwrap(URL(string: "https://example.test\(path)")), outcome: outcome)
    }

    private func ping(_ outcome: PingOutcome, host: String = "example.test") -> PingHostResult {
        PingHostResult(host: host, resolvedAddress: nil, outcome: outcome)
    }

    private func dnsServer(_ outcomes: DNSQueryOutcome...) -> DNSServerInfo {
        DNSServerInfo(
            address: "192.168.1.1",
            ping: .reachable(reachableStatistics),
            queries: outcomes.enumerated().map {
                DNSQueryResult(domain: "domain\($0.offset).test", outcome: $0.element)
            }
        )
    }

    private func summarize(
        interfaces: InterfaceDiscovery? = nil,
        gateways: GatewayDiscovery = .unavailable(reason: "not tested"),
        dnsServers: DNSServerDiscovery = .unavailable(reason: "not tested"),
        pings: [PingHostResult] = [],
        https: [HttpHostResult] = []
    ) -> DiagnosticVerdict {
        SummaryBuilder.summarize(
            interfaces: interfaces ?? .found([loopback, wifi]),
            gateways: gateways,
            dnsServers: dnsServers,
            pingResults: pings,
            httpResults: https
        ).verdict
    }

    func testDNSServersAnsweringNothingMeansDNSFailing() throws {
        XCTAssertEqual(
            summarize(
                dnsServers: .found([dnsServer(.timedOut), dnsServer(.failed(reason: "connection refused"))]),
                https: [try http(.response(statusCode: 200, latencyMs: 5))]
            ),
            .dnsResolutionFailing
        )
    }

    func testDNSServerReturningNXDOMAINForEveryDomainMeansDNSFailing() {
        XCTAssertEqual(
            summarize(
                dnsServers: .found([dnsServer(.answered(responseCode: .nameError, addresses: [], latencyMs: 3))])
            ),
            .dnsResolutionFailing
        )
    }

    func testOneResolvingDNSServerIsEnough() throws {
        let resolved = DNSQueryOutcome.answered(responseCode: .noError, addresses: ["17.253.144.10"], latencyMs: 3)

        XCTAssertEqual(
            summarize(
                dnsServers: .found([dnsServer(.timedOut), dnsServer(.timedOut, resolved)]),
                https: [try http(.response(statusCode: 200, latencyMs: 5))]
            ),
            .healthy
        )
    }

    func testDNSServersWithoutQueriesDoNotAffectTheVerdict() throws {
        XCTAssertEqual(
            summarize(dnsServers: .found([dnsServer()]), https: [try http(.response(statusCode: 200, latencyMs: 5))]),
            .healthy
        )
    }

    func testOnlyLoopbackMeansNoActiveInterface() throws {
        XCTAssertEqual(
            summarize(interfaces: .found([loopback]), https: [try http(.response(statusCode: 200, latencyMs: 5))]),
            .noActiveInterface
        )
    }

    func testDownInterfaceWithAddressIsNotActive() {
        let down = NetworkInterfaceInfo(
            name: "en0",
            ipv4Addresses: ["10.0.0.1"],
            ipv6Addresses: [],
            isUp: false,
            isLoopback: false
        )

        XCTAssertEqual(summarize(interfaces: .found([down])), .noActiveInterface)
    }

    func testInterfaceEnumerationFailureIsInconclusive() {
        XCTAssertEqual(
            summarize(interfaces: .unavailable(reason: "getifaddrs failed")),
            .inconclusive(reason: "interface enumeration failed: getifaddrs failed")
        )
    }

    func testNoGatewayAnsweringMeansGatewayUnreachable() throws {
        XCTAssertEqual(
            summarize(
                gateways: .found([gateway(.unreachable(sentPackets: 3))]),
                https: [try http(.failure(.timedOut))]
            ),
            .gatewayUnreachable
        )
    }

    func testEmptyGatewayListDoesNotBlameTheRouter() throws {
        XCTAssertEqual(
            summarize(gateways: .found([]), https: [try http(.response(statusCode: 200, latencyMs: 5))]),
            .healthy
        )
    }

    func testAllFailuresBeingDNSMeansDNSFailing() throws {
        XCTAssertEqual(
            summarize(
                gateways: .found([gateway(.reachable(reachableStatistics))]),
                pings: [ping(.resolutionFailed(reason: "nodename nor servname provided"))],
                https: [try http(.failure(.dnsResolutionFailed))]
            ),
            .dnsResolutionFailing
        )
    }

    func testDNSFailuresNextToIPLiteralSuccessesStillMeanDNSFailing() throws {
        XCTAssertEqual(
            summarize(
                pings: [ping(.reachable(reachableStatistics), host: "192.168.1.1")],
                https: [try http(.failure(.dnsResolutionFailed))]
            ),
            .dnsResolutionFailing
        )
    }

    func testEverythingFailingMeansRemoteHostsUnreachable() throws {
        XCTAssertEqual(
            summarize(
                pings: [ping(.unreachable(sentPackets: 3))],
                https: [try http(.failure(.timedOut)), try http(.failure(.dnsResolutionFailed), path: "/b")]
            ),
            .remoteHostsUnreachable
        )
    }

    func testMixedResultsMeanPartialConnectivity() throws {
        XCTAssertEqual(
            summarize(
                pings: [ping(.reachable(reachableStatistics))],
                https: [try http(.failure(.connectionRefused))]
            ),
            .partialConnectivity
        )
    }

    func testAllProbesSucceedingMeansHealthy() throws {
        XCTAssertEqual(
            summarize(
                gateways: .found([gateway(.reachable(reachableStatistics))]),
                pings: [ping(.reachable(reachableStatistics))],
                https: [try http(.response(statusCode: 503, latencyMs: 40))]
            ),
            .healthy
        )
    }

    func testNoProbesConfiguredIsInconclusive() {
        XCTAssertEqual(summarize(), .inconclusive(reason: "no ping or HTTP hosts were configured"))
    }

    func testEveryVerdictHasAMessage() {
        let verdicts: [DiagnosticVerdict] = [
            .healthy, .noActiveInterface, .gatewayUnreachable, .dnsResolutionFailing,
            .remoteHostsUnreachable, .partialConnectivity, .inconclusive(reason: "x"),
        ]

        for verdict in verdicts {
            XCTAssertFalse(DiagnosticSummary(verdict: verdict).message.isEmpty, "\(verdict)")
        }
    }
}
