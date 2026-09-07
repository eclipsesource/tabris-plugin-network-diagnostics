import Foundation
@testable import NetworkDiagnostics
import XCTest

/// Every `DiagnosticEvent` case except `completed` becomes one named Tabris event
/// whose attributes are the flattened result object; `completed` settles the
/// promise instead and produces no event.
final class DiagnosticEventTabrisTests: XCTestCase {
    func testStageEventsCarryTheStageName() throws {
        let started = try XCTUnwrap(DiagnosticEvent.stageStarted(.gatewayPing).tabrisEvent)
        let finished = try XCTUnwrap(DiagnosticEvent.stageFinished(.httpProbe).tabrisEvent)

        XCTAssertEqual(started.name, "stageStarted")
        assertTabrisObject(started.attributes, equals: ["stage": "gatewayPing"])
        XCTAssertEqual(finished.name, "stageFinished")
        assertTabrisObject(finished.attributes, equals: ["stage": "httpProbe"])
    }

    func testResultEventsSpreadTheResultObject() throws {
        let gateway = GatewayInfo(address: "192.168.1.1", interfaceName: nil, ping: .unreachable(sentPackets: 3))
        let server = DNSServerInfo(address: "192.168.1.1", ping: .failed(reason: "timeout"), queries: [])
        let ping = PingHostResult(host: "one.test", resolvedAddress: "10.0.0.1", outcome: .failed(reason: "socket"))
        let http = HttpHostResult(
            url: try XCTUnwrap(URL(string: "https://one.test/")),
            outcome: .failure(.timedOut)
        )

        let events = try [
            XCTUnwrap(DiagnosticEvent.gatewayResult(gateway).tabrisEvent),
            XCTUnwrap(DiagnosticEvent.dnsServerResult(server).tabrisEvent),
            XCTUnwrap(DiagnosticEvent.pingResult(ping).tabrisEvent),
            XCTUnwrap(DiagnosticEvent.httpResult(http).tabrisEvent),
        ]

        XCTAssertEqual(events.map(\.name), ["gatewayResult", "dnsServerResult", "pingResult", "httpResult"])
        assertTabrisObject(events[0].attributes, equals: gateway.tabrisObject)
        assertTabrisObject(events[1].attributes, equals: server.tabrisObject)
        assertTabrisObject(events[2].attributes, equals: ping.tabrisObject)
        assertTabrisObject(events[3].attributes, equals: http.tabrisObject)
    }

    func testCompletedProducesNoEvent() {
        let report = DiagnosticReport(
            startedAt: Date(),
            durationSeconds: 0,
            interfaces: .found([]),
            gateways: .found([]),
            dnsServers: .found([]),
            pingResults: [],
            httpResults: [],
            summary: DiagnosticSummary(verdict: .healthy)
        )

        XCTAssertNil(DiagnosticEvent.completed(report).tabrisEvent)
    }
}
