@testable import NetworkDiagnostics
import XCTest

/// Exercises each live service against local resources only.
final class LoopbackServicesTests: XCTestCase {
    func testICMPPingerReachesIPv4Loopback() async throws {
        let address = try XCTUnwrap(InternetAddress(family: .ipv4, rawBytes: Data([127, 0, 0, 1])))

        let outcome = await ICMPPinger().ping(address: address, packetCount: 4, timeoutPerPacketSeconds: 1)

        guard case let .reachable(statistics) = outcome else {
            XCTFail("IPv4 loopback ping failed: \(outcome)")
            return
        }
        XCTAssertEqual(statistics.receivedPackets, 4)
        XCTAssertEqual(statistics.packetLossPercent, 0)
    }

    func testICMPPingerReachesIPv6Loopback() async throws {
        let loopbackBytes = Data([UInt8](repeating: 0, count: 15) + [1])
        let address = try XCTUnwrap(InternetAddress(family: .ipv6, rawBytes: loopbackBytes))

        let outcome = await ICMPPinger().ping(address: address, packetCount: 2, timeoutPerPacketSeconds: 1)

        guard case let .reachable(statistics) = outcome else {
            XCTFail("IPv6 loopback ping failed: \(outcome)")
            return
        }
        XCTAssertEqual(statistics.receivedPackets, 2)
    }

    func testICMPPingerReportsLossForBlackholeAddress() async {
        guard let address = InternetAddress(family: .ipv4, rawBytes: Data([192, 0, 2, 1])) else {
            XCTFail("TEST-NET-1 literal must parse")
            return
        }

        let outcome = await ICMPPinger().ping(address: address, packetCount: 2, timeoutPerPacketSeconds: 0.2)

        switch outcome {
        case .unreachable(sentPackets: 2), .failed:
            break
        default:
            XCTFail("expected no reply from TEST-NET-1, got \(outcome)")
        }
    }

    func testInterfaceEnumeratorFindsLoopback() throws {
        let interfaces = try GetifaddrsInterfaceEnumerator().enumerateInterfaces()

        XCTAssertTrue(interfaces.contains { $0.isLoopback && $0.ipv4Addresses.contains("127.0.0.1") }, "\(interfaces)")
    }

    func testHostResolverHandlesLiteralsAndLocalhost() async throws {
        let literal = try await GetaddrinfoHostResolver().resolve(host: "127.0.0.1")
        let localhost = try await GetaddrinfoHostResolver().resolve(host: "localhost")

        XCTAssertEqual(literal.map(\.description), ["127.0.0.1"])
        XCTAssertTrue(localhost.contains { $0.description == "127.0.0.1" }, "\(localhost)")
    }

    func testUDPDNSQuerierGetsAnswerFromLoopbackServer() async throws {
        let dnsServer = try await LoopbackDNSServer.start()
        defer { dnsServer.stop() }
        let loopback = try XCTUnwrap(InternetAddress(family: .ipv4, rawBytes: Data([127, 0, 0, 1])))

        let querier = UDPDNSQuerier(port: dnsServer.port)

        let outcome = await querier.query(domain: "apple.com", server: loopback, timeoutSeconds: 3)

        guard case let .answered(responseCode, addresses, _) = outcome else {
            XCTFail("expected an answer, got \(outcome)")
            return
        }
        XCTAssertEqual(responseCode, .noError)
        XCTAssertEqual(addresses, [LoopbackDNSServer.answerAddress])
    }

    func testUDPDNSQuerierReportsUnreachablePort() async throws {
        let loopback = try XCTUnwrap(InternetAddress(family: .ipv4, rawBytes: Data([127, 0, 0, 1])))

        let outcome = await UDPDNSQuerier(port: 9).query(domain: "apple.com", server: loopback, timeoutSeconds: 1)

        switch outcome {
        case .timedOut, .failed:
            break
        default:
            XCTFail("expected timeout or failure on a closed port, got \(outcome)")
        }
    }

    func testUDPDNSQuerierRejectsInvalidDomain() async throws {
        let loopback = try XCTUnwrap(InternetAddress(family: .ipv4, rawBytes: Data([127, 0, 0, 1])))

        let outcome = await UDPDNSQuerier().query(domain: "bad..name", server: loopback, timeoutSeconds: 1)

        XCTAssertEqual(outcome, .failed(reason: "bad..name is not a valid DNS name"))
    }

    func testDNSServerReaderDoesNotCrash() {
        XCTAssertNoThrow(try ResolvDNSServerReader().readDNSServers())
    }

    func testGatewayDiscovererCompletesWithinTimeout() async {
        let clock = ContinuousClock()

        let start = clock.now
        _ = try? await PathMonitorGatewayDiscoverer().discoverGateways(timeoutSeconds: 2)

        XCTAssertLessThan(clock.now - start, .seconds(4))
    }
}
