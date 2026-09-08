@testable import NetworkDiagnostics
import XCTest

final class NetworkDiagnosticsTests: XCTestCase {
    private let wifi = NetworkInterfaceInfo(
        name: "en0",
        ipv4Addresses: ["192.168.1.10"],
        ipv6Addresses: [],
        isUp: true,
        isLoopback: false
    )
    private let reachable = PingOutcome.reachable(
        PingStatistics(sentPackets: 3, receivedPackets: 3, minRttMs: 1, avgRttMs: 1, maxRttMs: 1, packetLossPercent: 0)
    )
    private let resolvedQuery = DNSQueryOutcome.answered(
        responseCode: .noError,
        addresses: ["17.253.144.10"],
        latencyMs: 4
    )

    private func healthyServices() throws -> DiagnosticServices {
        let gatewayAddress = try SocketAddressFixtures.internetAddress("192.168.1.1")
        return DiagnosticServices(
            interfaces: StubInterfaceEnumerator(result: .success([wifi])),
            gateways: StubGatewayDiscoverer(
                result: .success([DiscoveredGateway(address: gatewayAddress, interfaceName: "en0")])
            ),
            dnsServers: StubDNSServerReader(result: .success([gatewayAddress])),
            hostResolver: StubHostResolver(addressesByHost: [
                "one.test": [try SocketAddressFixtures.internetAddress("10.0.0.1")],
                "two.test": [try SocketAddressFixtures.internetAddress("fd00::2")],
            ]),
            dnsQuerier: StubDNSQuerier(outcome: resolvedQuery),
            pinger: StubPinger(outcome: reachable),
            httpProber: StubHTTPProber(outcome: .response(statusCode: 200, latencyMs: 12))
        )
    }

    private func configuration(timeoutSeconds: TimeInterval = 3) throws -> DiagnosticConfiguration {
        DiagnosticConfiguration(
            pingHosts: ["one.test", "two.test", "missing.test"],
            httpHosts: [
                try XCTUnwrap(URL(string: "https://one.test/")),
                try XCTUnwrap(URL(string: "https://two.test/")),
            ],
            dnsTestDomains: ["one.test", "two.test"],
            timeoutPerHostSeconds: timeoutSeconds,
            pingPacketCount: 3
        )
    }

    private func collectEvents(
        _ diagnostics: NetworkDiagnostics,
        _ config: DiagnosticConfiguration
    ) async -> [DiagnosticEvent] {
        var events: [DiagnosticEvent] = []
        for await event in diagnostics.diagnose(config) {
            events.append(event)
        }
        return events
    }

    func testReportCarriesEveryResultInInputOrder() async throws {
        let diagnostics = NetworkDiagnostics(services: try healthyServices())

        let report = await diagnostics.runDiagnostics(try configuration())

        XCTAssertEqual(report.interfaces, .found([wifi]))
        XCTAssertEqual(
            report.gateways,
            .found([GatewayInfo(address: "192.168.1.1", interfaceName: "en0", ping: reachable)])
        )
        XCTAssertEqual(
            report.dnsServers,
            .found([
                DNSServerInfo(
                    address: "192.168.1.1",
                    ping: reachable,
                    queries: [
                        DNSQueryResult(domain: "one.test", outcome: resolvedQuery),
                        DNSQueryResult(domain: "two.test", outcome: resolvedQuery),
                    ]
                ),
            ])
        )
        XCTAssertEqual(report.pingResults.map(\.host), ["one.test", "two.test", "missing.test"])
        XCTAssertEqual(report.pingResults.map(\.resolvedAddress), ["10.0.0.1", "fd00::2", nil])
        XCTAssertEqual(report.pingResults[0].outcome, reachable)
        guard case .resolutionFailed = report.pingResults[2].outcome else {
            XCTFail("expected resolution failure, got \(report.pingResults[2].outcome)")
            return
        }
        XCTAssertEqual(
            report.httpResults.map(\.outcome),
            Array(repeating: .response(statusCode: 200, latencyMs: 12), count: 2)
        )
        XCTAssertEqual(report.summary.verdict, .dnsResolutionFailing)
        XCTAssertGreaterThanOrEqual(report.durationSeconds, 0)
    }

    func testEventStreamCoversEveryStageAndEndsWithTheReport() async throws {
        let diagnostics = NetworkDiagnostics(services: try healthyServices())

        let events = await collectEvents(diagnostics, try configuration())

        for stage in DiagnosticStage.allCases {
            let started = events.firstIndex(of: .stageStarted(stage))
            let finished = events.firstIndex(of: .stageFinished(stage))
            XCTAssertNotNil(started, "\(stage) never started")
            XCTAssertNotNil(finished, "\(stage) never finished")
            if let started, let finished {
                XCTAssertLessThan(started, finished, "\(stage) finished before it started")
            }
        }
        guard case let .completed(report) = events.last else {
            XCTFail("stream must end with the report, ended with \(String(describing: events.last))")
            return
        }
        XCTAssertEqual(events.filter { $0 == .completed(report) }.count, 1)
        XCTAssertEqual(
            events.compactMap(\.pingResult).sorted { $0.host < $1.host },
            report.pingResults.sorted { $0.host < $1.host }
        )
        XCTAssertEqual(events.compactMap(\.httpResult).count, report.httpResults.count)
        XCTAssertEqual(events.compactMap(\.gatewayResult).count, 1)
        XCTAssertEqual(events.compactMap(\.dnsServerResult).count, 1)
    }

    func testProbeResultsArriveBeforeTheirStageFinishes() async throws {
        let diagnostics = NetworkDiagnostics(services: try healthyServices())

        let events = await collectEvents(diagnostics, try configuration())

        assertResultsPrecedeStageFinish(events, resultStage: .gatewayPing) { $0.isGatewayResult }
        assertResultsPrecedeStageFinish(events, resultStage: .dnsServerCheck) { $0.isDNSServerResult }
        assertResultsPrecedeStageFinish(events, resultStage: .hostPing) { $0.isPingResult }
        assertResultsPrecedeStageFinish(events, resultStage: .httpProbe) { $0.isHTTPResult }
    }

    private func assertResultsPrecedeStageFinish(
        _ events: [DiagnosticEvent],
        resultStage: DiagnosticStage,
        isResult: (DiagnosticEvent) -> Bool
    ) {
        guard let finished = events.firstIndex(of: .stageFinished(resultStage)) else {
            XCTFail("\(resultStage) never finished")
            return
        }
        let lastResult = events.lastIndex(where: isResult)
        XCTAssertNotNil(lastResult, "\(resultStage) produced no result event")
        if let lastResult {
            XCTAssertLessThan(lastResult, finished, "\(resultStage) finished before its last result event")
        }
    }

    func testEmptyStagesStillReportStartAndFinish() async throws {
        let diagnostics = NetworkDiagnostics(services: try healthyServices())
        let config = DiagnosticConfiguration(pingHosts: [], httpHosts: [], dnsTestDomains: [])

        let events = await collectEvents(diagnostics, config)

        XCTAssertTrue(events.contains(.stageStarted(.hostPing)))
        XCTAssertTrue(events.contains(.stageFinished(.hostPing)))
        XCTAssertTrue(events.contains(.stageStarted(.httpProbe)))
        XCTAssertTrue(events.contains(.stageFinished(.httpProbe)))
    }

    func testHangingPingerHitsTheHardTimeout() async throws {
        var services = try healthyServices()
        services = DiagnosticServices(
            interfaces: services.interfaces,
            gateways: services.gateways,
            dnsServers: services.dnsServers,
            hostResolver: services.hostResolver,
            dnsQuerier: services.dnsQuerier,
            pinger: StubPinger(outcome: reachable, hangForever: true),
            httpProber: services.httpProber
        )
        let diagnostics = NetworkDiagnostics(services: services)
        let clock = ContinuousClock()

        let start = clock.now
        let report = await diagnostics.runDiagnostics(try configuration(timeoutSeconds: 0.3))
        let elapsed = clock.now - start

        XCTAssertLessThan(elapsed, .seconds(3))
        for result in report.pingResults.prefix(2) {
            guard case let .failed(reason) = result.outcome else {
                XCTFail("expected hard-timeout failure for \(result.host), got \(result.outcome)")
                return
            }
            XCTAssertTrue(reason.contains("hard timeout"), reason)
        }
        guard case let .found(gateways) = report.gateways, case .failed = gateways.first?.ping else {
            XCTFail("gateway ping should have hit the hard timeout: \(report.gateways)")
            return
        }
    }

    func testServiceFailuresSurfaceAsUnavailableAndInconclusive() async throws {
        let services = DiagnosticServices(
            interfaces: StubInterfaceEnumerator(result: .failure(.stub("EPERM"))),
            gateways: StubGatewayDiscoverer(result: .failure(.stub("no path"))),
            dnsServers: StubDNSServerReader(result: .failure(.stub("res_9_ninit"))),
            hostResolver: StubHostResolver(addressesByHost: [:]),
            dnsQuerier: StubDNSQuerier(outcome: .timedOut),
            pinger: StubPinger(outcome: reachable),
            httpProber: StubHTTPProber(outcome: .failure(.timedOut))
        )
        let diagnostics = NetworkDiagnostics(services: services)

        let report = await diagnostics.runDiagnostics(try configuration())

        XCTAssertEqual(report.interfaces, .unavailable(reason: "Stub.operation failed: EPERM"))
        XCTAssertEqual(report.gateways, .unavailable(reason: "Stub.operation failed: no path"))
        XCTAssertEqual(report.dnsServers, .unavailable(reason: "Stub.operation failed: res_9_ninit"))
        XCTAssertEqual(
            report.summary.verdict,
            .inconclusive(reason: "interface enumeration failed: Stub.operation failed: EPERM")
        )
    }
}

private extension DiagnosticEvent {
    var pingResult: PingHostResult? {
        if case let .pingResult(result) = self { result } else { nil }
    }

    var httpResult: HttpHostResult? {
        if case let .httpResult(result) = self { result } else { nil }
    }

    var gatewayResult: GatewayInfo? {
        if case let .gatewayResult(info) = self { info } else { nil }
    }

    var dnsServerResult: DNSServerInfo? {
        if case let .dnsServerResult(info) = self { info } else { nil }
    }

    var isGatewayResult: Bool { gatewayResult != nil }
    var isDNSServerResult: Bool { dnsServerResult != nil }
    var isPingResult: Bool { pingResult != nil }
    var isHTTPResult: Bool { httpResult != nil }
}
