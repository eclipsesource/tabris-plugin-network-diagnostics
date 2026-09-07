import Foundation
@testable import NetworkDiagnostics
import XCTest

/// The primitives behind the individual JavaScript methods, exercised with the
/// live services against loopback resources only.
final class PrimitivesLoopbackTests: XCTestCase {
    func testPingPrimitiveReachesLoopback() async {
        let result = await DiagnosticPrimitives().ping(host: "127.0.0.1", packetCount: 2, timeoutSeconds: 3)

        XCTAssertEqual(result.host, "127.0.0.1")
        XCTAssertEqual(result.resolvedAddress, "127.0.0.1")
        guard case let .reachable(statistics) = result.outcome else {
            XCTFail("loopback ping failed: \(result.outcome)")
            return
        }
        XCTAssertEqual(statistics.receivedPackets, 2)
    }

    func testQueryPrimitiveGetsTheLoopbackAnswer() async throws {
        let dnsServer = try await LoopbackDNSServer.start()
        defer { dnsServer.stop() }
        let primitives = DiagnosticPrimitives(services: liveServices(dnsPort: dnsServer.port))
        let loopback = try XCTUnwrap(InternetAddress(literal: "127.0.0.1"))

        let result = await primitives.query(domain: "apple.com", server: loopback, timeoutSeconds: 3)
        let expected = DNSQueryOutcome.answered(
            responseCode: .noError,
            addresses: [LoopbackDNSServer.answerAddress],
            latencyMs: latency(of: result)
        )

        XCTAssertEqual(result.outcome, expected)
        XCTAssertTrue(result.isResolved)
    }

    func testProbePrimitiveReportsStatusAndRefusedConnections() async throws {
        let httpServer = try await LoopbackHTTPServer.start()
        defer { httpServer.stop() }
        let primitives = DiagnosticPrimitives()
        let refused = try XCTUnwrap(URL(string: "http://127.0.0.1:1/"))

        let response = await primitives.probe(url: try httpServer.url, method: .head, timeoutSeconds: 3)
        let closed = await primitives.probe(url: refused, method: .head, timeoutSeconds: 3)

        guard case let .response(statusCode, _) = response.outcome else {
            XCTFail("expected a response from the loopback server, got \(response.outcome)")
            return
        }
        XCTAssertEqual(statusCode, 200)
        XCTAssertEqual(closed.outcome, .failure(.connectionRefused))
    }

    func testDiscoveryPrimitivesUseTheLiveServices() throws {
        let interfaces = try DiagnosticPrimitives().enumerateInterfaces()

        XCTAssertTrue(interfaces.contains { $0.isLoopback && $0.ipv4Addresses.contains("127.0.0.1") }, "\(interfaces)")
        XCTAssertNoThrow(try DiagnosticPrimitives().readDNSServers())
    }

    private func liveServices(dnsPort: UInt16) -> DiagnosticServices {
        DiagnosticServices(
            interfaces: GetifaddrsInterfaceEnumerator(),
            gateways: PathMonitorGatewayDiscoverer(),
            dnsServers: ResolvDNSServerReader(),
            hostResolver: GetaddrinfoHostResolver(),
            dnsQuerier: UDPDNSQuerier(port: dnsPort),
            pinger: ICMPPinger(),
            httpProber: URLSessionHTTPProber()
        )
    }

    private func latency(of result: DNSQueryResult) -> Double {
        if case let .answered(_, _, latencyMs) = result.outcome { latencyMs } else { -1 }
    }
}
