import Foundation
@testable import NetworkDiagnostics
import XCTest

/// The primitives facade is what the Tabris bridge calls for the individual
/// JavaScript methods; it must forward to the same services the all-in-one run
/// uses, resolve hosts before pinging, and let discovery failures surface as
/// errors while probe failures stay values.
final class DiagnosticPrimitivesTests: XCTestCase {
    private let wifi = NetworkInterfaceInfo(
        name: "en0",
        ipv4Addresses: ["192.168.1.10"],
        ipv6Addresses: [],
        isUp: true,
        isLoopback: false
    )
    private let reachable = PingOutcome.reachable(
        PingStatistics(sentPackets: 2, receivedPackets: 2, minRttMs: 1, avgRttMs: 1, maxRttMs: 1, packetLossPercent: 0)
    )

    func testEnumerateInterfacesForwardsTheServiceResult() throws {
        let primitives = DiagnosticPrimitives(services: try services(interfaces: .success([wifi])))

        XCTAssertEqual(try primitives.enumerateInterfaces(), [wifi])
    }

    func testEnumerateInterfacesRethrowsTheServiceFailure() throws {
        let primitives = DiagnosticPrimitives(services: try services(interfaces: .failure(.stub("EPERM"))))

        XCTAssertThrowsError(try primitives.enumerateInterfaces()) { error in
            XCTAssertEqual(String(describing: error), "Stub.operation failed: EPERM")
        }
    }

    func testDiscoveriesForwardGatewaysAndDNSServers() async throws {
        let gateway = try SocketAddressFixtures.internetAddress("192.168.1.1")
        let primitives = DiagnosticPrimitives(services: try services(gateway: gateway))

        let gateways = try await primitives.discoverGateways(timeoutSeconds: 1)

        XCTAssertEqual(gateways, [DiscoveredGateway(address: gateway, interfaceName: "en0")])
        XCTAssertEqual(try primitives.readDNSServers(), [gateway])
    }

    func testDiscoveryFailuresAreThrown() async throws {
        let primitives = DiagnosticPrimitives(services: try services(gatewayFailure: .stub("no path")))

        do {
            _ = try await primitives.discoverGateways(timeoutSeconds: 1)
            XCTFail("expected the gateway failure to be thrown")
        } catch {
            XCTAssertEqual(String(describing: error), "Stub.operation failed: no path")
        }
    }

    func testPingResolvesTheHostAndReportsTheAddress() async throws {
        let primitives = DiagnosticPrimitives(services: try services())

        let result = await primitives.ping(host: "one.test", packetCount: 2, timeoutSeconds: 1)

        XCTAssertEqual(result, PingHostResult(host: "one.test", resolvedAddress: "10.0.0.1", outcome: reachable))
    }

    func testPingReportsResolutionFailuresAsOutcomes() async throws {
        let primitives = DiagnosticPrimitives(services: try services())

        let result = await primitives.ping(host: "missing.test", packetCount: 2, timeoutSeconds: 1)

        XCTAssertEqual(result.host, "missing.test")
        XCTAssertNil(result.resolvedAddress)
        guard case .resolutionFailed = result.outcome else {
            XCTFail("expected a resolution failure, got \(result.outcome)")
            return
        }
    }

    func testQueryAndProbeWrapTheServiceOutcomes() async throws {
        let primitives = DiagnosticPrimitives(services: try services())
        let server = try SocketAddressFixtures.internetAddress("192.168.1.1")
        let url = try XCTUnwrap(URL(string: "https://one.test/"))

        let query = await primitives.query(domain: "one.test", server: server, timeoutSeconds: 1)
        let probe = await primitives.probe(url: url, method: .head, timeoutSeconds: 1)

        XCTAssertEqual(query, DNSQueryResult(domain: "one.test", outcome: .timedOut))
        XCTAssertEqual(probe, HttpHostResult(url: url, outcome: .response(statusCode: 204, latencyMs: 12)))
    }

    private func services(
        interfaces: Result<[NetworkInterfaceInfo], ServiceFailure> = .success([]),
        gateway: InternetAddress? = nil,
        gatewayFailure: ServiceFailure? = nil
    ) throws -> DiagnosticServices {
        let gateways: Result<[DiscoveredGateway], ServiceFailure> = if let gatewayFailure {
            .failure(gatewayFailure)
        } else {
            .success(gateway.map { [DiscoveredGateway(address: $0, interfaceName: "en0")] } ?? [])
        }

        return DiagnosticServices(
            interfaces: StubInterfaceEnumerator(result: interfaces),
            gateways: StubGatewayDiscoverer(result: gateways),
            dnsServers: StubDNSServerReader(result: .success(gateway.map { [$0] } ?? [])),
            hostResolver: StubHostResolver(addressesByHost: [
                "one.test": [try SocketAddressFixtures.internetAddress("10.0.0.1")],
            ]),
            dnsQuerier: StubDNSQuerier(outcome: .timedOut),
            pinger: StubPinger(outcome: reachable),
            httpProber: StubHTTPProber(outcome: .response(statusCode: 204, latencyMs: 12))
        )
    }
}
