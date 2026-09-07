@testable import NetworkDiagnostics
import XCTest

/// Real end-to-end run against loopback only. The simulator inherits the host
/// network, so assertions are structural: no interface names, no fixed IPs.
/// Gateway discovery and the DNS server list are stubbed so no packet leaves
/// the machine; every other service is the live implementation.
final class LoopbackDiagnosticsTests: XCTestCase {
    private var server: LoopbackHTTPServer?
    private var dnsServer: LoopbackDNSServer?

    override func setUp() async throws {
        try await super.setUp()
        server = try await LoopbackHTTPServer.start()
        dnsServer = try await LoopbackDNSServer.start()
    }

    override func tearDown() async throws {
        server?.stop()
        server = nil
        dnsServer?.stop()
        dnsServer = nil
        try await super.tearDown()
    }

    private func loopbackDiagnostics(dnsPort: UInt16) throws -> NetworkDiagnostics {
        let loopback = try XCTUnwrap(InternetAddress(family: .ipv4, rawBytes: Data([127, 0, 0, 1])))
        let live = DiagnosticServices.live

        return NetworkDiagnostics(
            services: DiagnosticServices(
                interfaces: live.interfaces,
                gateways: FixedGatewayDiscoverer(gateways: []),
                dnsServers: FixedDNSServerReader(servers: [loopback]),
                hostResolver: live.hostResolver,
                dnsQuerier: UDPDNSQuerier(port: dnsPort),
                pinger: live.pinger,
                httpProber: live.httpProber
            )
        )
    }

    func testRunDiagnosticsAgainstLoopbackTargets() async throws {
        let server = try XCTUnwrap(server)
        let dnsServer = try XCTUnwrap(dnsServer)
        let closedPort = try XCTUnwrap(URL(string: "http://127.0.0.1:1/"))
        let configuration = DiagnosticConfiguration(
            pingHosts: ["127.0.0.1"],
            httpHosts: [try server.url, closedPort],
            dnsTestDomains: ["example.test"],
            timeoutPerHostSeconds: 5,
            pingPacketCount: 3
        )

        var events: [DiagnosticEvent] = []
        for await event in try loopbackDiagnostics(dnsPort: dnsServer.port).diagnose(configuration) {
            events.append(event)
        }

        guard case let .completed(report) = events.last else {
            XCTFail("stream did not end with a report: \(String(describing: events.last))")
            return
        }
        for stage in DiagnosticStage.allCases {
            XCTAssertTrue(events.contains(.stageStarted(stage)), "\(stage) never started")
            XCTAssertTrue(events.contains(.stageFinished(stage)), "\(stage) never finished")
        }
        assertInterfaces(report)
        assertLoopbackPing(report)
        assertDNSServer(report)
        assertHTTP(report)
        XCTAssertEqual(report.summary.verdict, .partialConnectivity)
    }

    private func assertInterfaces(_ report: DiagnosticReport) {
        guard case let .found(interfaces) = report.interfaces else {
            XCTFail("interfaces unavailable: \(report.interfaces)")
            return
        }
        XCTAssertFalse(interfaces.isEmpty)
        XCTAssertTrue(interfaces.contains { !$0.ipv4Addresses.isEmpty }, "no interface with an IPv4 address")
        XCTAssertTrue(interfaces.contains { $0.isLoopback && $0.ipv4Addresses.contains("127.0.0.1") })
    }

    private func assertLoopbackPing(_ report: DiagnosticReport) {
        XCTAssertEqual(report.pingResults.count, 1)
        XCTAssertEqual(report.pingResults.first?.resolvedAddress, "127.0.0.1")
        guard case let .reachable(statistics) = report.pingResults.first?.outcome else {
            XCTFail("loopback ping failed: \(String(describing: report.pingResults.first?.outcome))")
            return
        }
        XCTAssertEqual(statistics.sentPackets, 3)
        XCTAssertEqual(statistics.receivedPackets, 3)
        XCTAssertEqual(statistics.packetLossPercent, 0)
        XCTAssertLessThanOrEqual(statistics.minRttMs, statistics.avgRttMs)
        XCTAssertLessThanOrEqual(statistics.avgRttMs, statistics.maxRttMs)
    }

    private func assertDNSServer(_ report: DiagnosticReport) {
        guard case let .found(dnsServers) = report.dnsServers, dnsServers.count == 1, let dns = dnsServers.first else {
            XCTFail("expected exactly one DNS server, got \(report.dnsServers)")
            return
        }
        XCTAssertEqual(dns.address, "127.0.0.1")
        guard case .reachable = dns.ping else {
            XCTFail("DNS server ping failed: \(dns.ping)")
            return
        }
        XCTAssertEqual(dns.queries.map(\.domain), ["example.test"])
        guard case let .answered(responseCode, addresses, latencyMs) = dns.queries.first?.outcome else {
            XCTFail("DNS query failed: \(String(describing: dns.queries.first?.outcome))")
            return
        }
        XCTAssertEqual(responseCode, .noError)
        XCTAssertEqual(addresses, [LoopbackDNSServer.answerAddress])
        XCTAssertGreaterThan(latencyMs, 0)
    }

    private func assertHTTP(_ report: DiagnosticReport) {
        XCTAssertEqual(report.httpResults.count, 2)
        guard case let .response(statusCode, latencyMs) = report.httpResults.first?.outcome else {
            XCTFail("loopback HTTP failed: \(String(describing: report.httpResults.first?.outcome))")
            return
        }
        XCTAssertEqual(statusCode, 200)
        XCTAssertGreaterThan(latencyMs, 0)
        XCTAssertEqual(report.httpResults.last?.outcome, .failure(.connectionRefused))
    }

    func testResolutionFailureIsReportedNotHidden() async throws {
        let dnsServer = try XCTUnwrap(dnsServer)
        let configuration = DiagnosticConfiguration(
            pingHosts: ["nonexistent.invalid"],
            httpHosts: [],
            dnsTestDomains: [],
            timeoutPerHostSeconds: 5
        )

        let report = await try loopbackDiagnostics(dnsPort: dnsServer.port).runDiagnostics(configuration)

        guard case let .resolutionFailed(reason) = report.pingResults.first?.outcome else {
            XCTFail("expected resolution failure, got \(String(describing: report.pingResults.first?.outcome))")
            return
        }
        XCTAssertFalse(reason.isEmpty)
    }
}

private struct FixedGatewayDiscoverer: GatewayDiscovering {
    let gateways: [DiscoveredGateway]

    func discoverGateways(timeoutSeconds: TimeInterval) async throws -> [DiscoveredGateway] {
        gateways
    }
}

private struct FixedDNSServerReader: DNSServerReading {
    let servers: [InternetAddress]

    func readDNSServers() throws -> [InternetAddress] {
        servers
    }
}
