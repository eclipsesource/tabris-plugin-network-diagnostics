import Foundation
@testable import NetworkDiagnostics
import XCTest

/// Parameters arrive from JavaScript as loosely typed dictionaries; every
/// accepted shape and every rejection message is part of the plugin contract.
final class NetworkDiagnosticsParametersTests: XCTestCase {
    func testPingRequestAppliesDefaults() throws {
        XCTAssertEqual(
            try NetworkDiagnosticsParameters.ping(["host": "1.1.1.1"]),
            NetworkDiagnosticsParameters.Ping(host: "1.1.1.1", packetCount: 3, timeoutSeconds: 3)
        )
    }

    func testPingRequestReadsExplicitValuesAndTrimsTheHost() throws {
        XCTAssertEqual(
            try NetworkDiagnosticsParameters.ping(["host": " example.test ", "packetCount": 5, "timeoutSeconds": 1.5]),
            NetworkDiagnosticsParameters.Ping(host: "example.test", packetCount: 5, timeoutSeconds: 1.5)
        )
    }

    func testNumbersMayArriveAsIntegersOrDoubles() throws {
        XCTAssertEqual(try NetworkDiagnosticsParameters.timeout(["t": 2], key: "t"), 2)
        XCTAssertEqual(try NetworkDiagnosticsParameters.timeout(["t": 2.5], key: "t"), 2.5)
        XCTAssertEqual(try NetworkDiagnosticsParameters.packetCount(["p": 4.0], key: "p"), 4)
    }

    func testPingRequestRejectsMissingEmptyOrNonStringHost() {
        assertInvalid(try NetworkDiagnosticsParameters.ping([:]), mentioning: "host")
        assertInvalid(try NetworkDiagnosticsParameters.ping(["host": "   "]), mentioning: "host")
        assertInvalid(try NetworkDiagnosticsParameters.ping(["host": 42]), mentioning: "host")
    }

    func testPacketCountRejectsZeroFractionsAndStrings() {
        assertInvalid(try NetworkDiagnosticsParameters.packetCount(["p": 0], key: "p"), mentioning: "p")
        assertInvalid(try NetworkDiagnosticsParameters.packetCount(["p": 2.5], key: "p"), mentioning: "p")
        assertInvalid(try NetworkDiagnosticsParameters.packetCount(["p": "3"], key: "p"), mentioning: "3")
        assertInvalid(try NetworkDiagnosticsParameters.packetCount(["p": -1], key: "p"), mentioning: "p")
    }

    func testTimeoutRejectsNonPositiveNonFiniteAndNonNumericValues() {
        assertInvalid(try NetworkDiagnosticsParameters.timeout(["t": 0], key: "t"), mentioning: "t")
        assertInvalid(try NetworkDiagnosticsParameters.timeout(["t": -1], key: "t"), mentioning: "t")
        assertInvalid(try NetworkDiagnosticsParameters.timeout(["t": Double.infinity], key: "t"), mentioning: "t")
        assertInvalid(try NetworkDiagnosticsParameters.timeout(["t": "fast"], key: "t"), mentioning: "fast")
    }

    func testDNSQueryRequestParsesIPv4AndIPv6Servers() throws {
        let ipv4 = try NetworkDiagnosticsParameters.dnsQuery(["domain": "apple.com", "server": "192.168.1.1"])
        let ipv6 = try NetworkDiagnosticsParameters.dnsQuery([
            "domain": "apple.com",
            "server": "fd00::53",
            "timeoutSeconds": 1,
        ])

        XCTAssertEqual(ipv4.server.description, "192.168.1.1")
        XCTAssertEqual(ipv4.timeoutSeconds, 3)
        XCTAssertEqual(ipv6.server.description, "fd00::53")
        XCTAssertEqual(ipv6.timeoutSeconds, 1)
        XCTAssertEqual(ipv6.domain, "apple.com")
    }

    func testDNSQueryRequestRejectsMissingOrInvalidServer() {
        let noServer: [String: Any] = ["domain": "apple.com"]
        let hostName: [String: Any] = ["domain": "apple.com", "server": "dns.local"]
        let noDomain: [String: Any] = ["server": "1.1.1.1"]

        assertInvalid(try NetworkDiagnosticsParameters.dnsQuery(noServer), mentioning: "server")
        assertInvalid(try NetworkDiagnosticsParameters.dnsQuery(hostName), mentioning: "dns.local")
        assertInvalid(try NetworkDiagnosticsParameters.dnsQuery(noDomain), mentioning: "domain")
    }

    func testHTTPRequestAcceptsHttpAndHttpsAndReadsTheMethodCaseInsensitively() throws {
        let head = try NetworkDiagnosticsParameters.http(["url": "https://www.apple.com"])
        let get = try NetworkDiagnosticsParameters.http(["url": "http://127.0.0.1:8080/health", "method": "get"])
        let appleURL = try XCTUnwrap(URL(string: "https://www.apple.com"))

        XCTAssertEqual(head, NetworkDiagnosticsParameters.HTTP(url: appleURL, method: .head, timeoutSeconds: 3))
        XCTAssertEqual(get.method, .get)
        XCTAssertEqual(get.url.port, 8_080)
    }

    func testHTTPRequestRejectsUnsupportedOrIncompleteURLs() {
        let rejected = ["ftp://files.test/", "https://", "www.apple.com", "not a url"]

        assertInvalid(try NetworkDiagnosticsParameters.http([:]), mentioning: "url")
        for url in rejected {
            assertInvalid(try NetworkDiagnosticsParameters.http(["url": url]), mentioning: url)
        }
    }

    func testHTTPRequestRejectsUnknownMethods() {
        let put: [String: Any] = ["url": "https://www.apple.com", "method": "PUT"]

        assertInvalid(try NetworkDiagnosticsParameters.http(put), mentioning: "PUT")
    }

    func testGatewayRequestUsesTheDefaultTimeout() throws {
        XCTAssertEqual(
            try NetworkDiagnosticsParameters.gateways([:]),
            NetworkDiagnosticsParameters.Gateway(timeoutSeconds: 3)
        )
        XCTAssertEqual(
            try NetworkDiagnosticsParameters.gateways(["timeoutSeconds": 0.5]),
            NetworkDiagnosticsParameters.Gateway(timeoutSeconds: 0.5)
        )
    }

    private func assertInvalid<Value>(
        _ expression: @autoclosure () throws -> Value,
        mentioning fragment: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            guard let error = error as? NetworkDiagnosticsParameterError else {
                XCTFail("expected NetworkDiagnosticsParameterError, got \(error)", file: file, line: line)
                return
            }
            XCTAssertEqual(
                error.errorDescription?.contains(fragment),
                true,
                "\(String(describing: error.errorDescription)) does not mention \(fragment)",
                file: file,
                line: line
            )
        }
    }
}
