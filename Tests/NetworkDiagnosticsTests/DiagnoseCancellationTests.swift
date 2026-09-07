import Foundation
@testable import NetworkDiagnostics
import XCTest

/// Cancelling the task that consumes `diagnose()` must end the stream, because
/// the plugin's cancel() and dispose() rely on exactly that to stop a run and
/// settle its JavaScript promise.
final class DiagnoseCancellationTests: XCTestCase {
    func testCancellingTheConsumerEndsAStreamWithAHangingPinger() async throws {
        let blackhole = try SocketAddressFixtures.internetAddress("192.0.2.1")
        let services = DiagnosticServices(
            interfaces: StubInterfaceEnumerator(result: .success([])),
            gateways: StubGatewayDiscoverer(result: .success([])),
            dnsServers: StubDNSServerReader(result: .success([])),
            hostResolver: StubHostResolver(addressesByHost: ["blackhole.test": [blackhole]]),
            dnsQuerier: StubDNSQuerier(outcome: .timedOut),
            pinger: StubPinger(outcome: .unreachable(sentPackets: 3), hangForever: true),
            httpProber: StubHTTPProber(outcome: .failure(.timedOut))
        )
        let configuration = DiagnosticConfiguration(
            pingHosts: ["blackhole.test"],
            httpHosts: [],
            dnsTestDomains: [],
            timeoutPerHostSeconds: 600
        )
        let clock = ContinuousClock()
        let start = clock.now
        let consumer = Task { () -> Bool in
            for await event in NetworkDiagnostics(services: services).diagnose(configuration) {
                if case .completed = event { return false }
            }
            return true
        }

        try? await Task.sleep(for: .milliseconds(100))
        consumer.cancel()
        let endedWithoutReport = await consumer.value

        XCTAssertTrue(endedWithoutReport, "the stream must end without a report when the consumer is cancelled")
        XCTAssertLessThan(clock.now - start, .seconds(5), "cancellation must not wait for the 600 s ping")
    }
}
