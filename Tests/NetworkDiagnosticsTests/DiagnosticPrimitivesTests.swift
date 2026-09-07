import Foundation
@testable import NetworkDiagnostics
import XCTest

/// The primitives facade is what the Tabris bridge calls for the individual
/// JavaScript methods; it must forward to the same services the all-in-one run
/// uses and let discovery failures surface as errors.
final class DiagnosticPrimitivesTests: XCTestCase {
    private let wifi = NetworkInterfaceInfo(
        name: "en0",
        ipv4Addresses: ["192.168.1.10"],
        ipv6Addresses: [],
        isUp: true,
        isLoopback: false
    )

    func testEnumerateInterfacesForwardsTheServiceResult() throws {
        let primitives = DiagnosticPrimitives(services: services(interfaces: .success([wifi])))

        XCTAssertEqual(try primitives.enumerateInterfaces(), [wifi])
    }

    func testEnumerateInterfacesRethrowsTheServiceFailure() {
        let primitives = DiagnosticPrimitives(services: services(interfaces: .failure(.stub("EPERM"))))

        XCTAssertThrowsError(try primitives.enumerateInterfaces()) { error in
            XCTAssertEqual(String(describing: error), "Stub.operation failed: EPERM")
        }
    }

    private func services(interfaces: Result<[NetworkInterfaceInfo], ServiceFailure>) -> DiagnosticServices {
        DiagnosticServices(
            interfaces: StubInterfaceEnumerator(result: interfaces),
            gateways: StubGatewayDiscoverer(result: .success([])),
            dnsServers: StubDNSServerReader(result: .success([])),
            hostResolver: StubHostResolver(addressesByHost: [:]),
            dnsQuerier: StubDNSQuerier(outcome: .timedOut),
            pinger: StubPinger(outcome: .unreachable(sentPackets: 0)),
            httpProber: StubHTTPProber(outcome: .failure(.timedOut))
        )
    }
}
