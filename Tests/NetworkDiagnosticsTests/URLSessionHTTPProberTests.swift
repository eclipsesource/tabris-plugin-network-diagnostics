@testable import NetworkDiagnostics
import XCTest

final class URLSessionHTTPProberTests: XCTestCase {
    private let prober = URLSessionHTTPProber(session: MockURLProtocol.makeSession())

    private func url(_ name: String) throws -> URL {
        try XCTUnwrap(URL(string: "https://\(name).prober.test/health"))
    }

    private static func response(_ url: URL, statusCode: Int) throws -> HTTPURLResponse {
        try XCTUnwrap(HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil))
    }

    func testSuccessfulResponseReportsStatusAndLatency() async throws {
        let target = try url("ok")
        MockURLProtocol.register(target) { request in
            XCTAssertEqual(request.httpMethod, "HEAD")
            return (try Self.response(target, statusCode: 200), Data())
        }

        let outcome = await prober.probe(url: target, method: .head, timeoutSeconds: 3)

        guard case let .response(statusCode, latencyMs) = outcome else {
            XCTFail("expected response, got \(outcome)")
            return
        }
        XCTAssertEqual(statusCode, 200)
        XCTAssertGreaterThanOrEqual(latencyMs, 0)
    }

    func testGetMethodIsForwarded() async throws {
        let target = try url("get")
        MockURLProtocol.register(target) { request in
            XCTAssertEqual(request.httpMethod, "GET")
            return (try Self.response(target, statusCode: 503), Data())
        }

        let outcome = await prober.probe(url: target, method: .get, timeoutSeconds: 3)

        guard case let .response(statusCode, _) = outcome else {
            XCTFail("expected response, got \(outcome)")
            return
        }
        XCTAssertEqual(statusCode, 503)
    }

    func testDNSErrorIsClassified() async throws {
        let target = try url("nxdomain")
        MockURLProtocol.register(target) { _ in throw URLError(.cannotFindHost) }

        let outcome = await prober.probe(url: target, method: .head, timeoutSeconds: 3)

        XCTAssertEqual(outcome, .failure(.dnsResolutionFailed))
    }

    func testTLSErrorIsClassified() async throws {
        let target = try url("badtls")
        MockURLProtocol.register(target) { _ in throw URLError(.secureConnectionFailed) }

        let outcome = await prober.probe(url: target, method: .head, timeoutSeconds: 3)

        XCTAssertEqual(outcome, .failure(.tlsHandshakeFailed))
    }

    func testConnectionRefusedIsClassified() async throws {
        let target = try url("refused")
        MockURLProtocol.register(target) { _ in throw URLError(.cannotConnectToHost) }

        let outcome = await prober.probe(url: target, method: .head, timeoutSeconds: 3)

        XCTAssertEqual(outcome, .failure(.connectionRefused))
    }

    func testServerThatNeverAnswersTimesOut() async throws {
        let target = try url("silent")
        MockURLProtocol.register(target, handler: MockURLProtocol.neverAnswers)

        let outcome = await prober.probe(url: target, method: .head, timeoutSeconds: 0.5)

        XCTAssertEqual(outcome, .failure(.timedOut))
    }
}
