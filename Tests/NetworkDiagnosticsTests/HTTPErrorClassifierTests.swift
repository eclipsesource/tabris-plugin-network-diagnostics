@testable import NetworkDiagnostics
import XCTest

final class HTTPErrorClassifierTests: XCTestCase {
    func testMapsURLErrorCodesToFailures() {
        let expectations: [(URLError.Code, HttpFailure)] = [
            (.cannotFindHost, .dnsResolutionFailed),
            (.dnsLookupFailed, .dnsResolutionFailed),
            (.secureConnectionFailed, .tlsHandshakeFailed),
            (.serverCertificateUntrusted, .tlsHandshakeFailed),
            (.cannotConnectToHost, .connectionRefused),
            (.timedOut, .timedOut),
            (.notConnectedToInternet, .networkUnavailable),
            (.networkConnectionLost, .networkUnavailable),
        ]

        for (code, expected) in expectations {
            XCTAssertEqual(HTTPErrorClassifier.classify(URLError(code)), expected, "\(code)")
        }
    }

    func testUnknownURLErrorKeepsCodeInDescription() {
        guard case let .other(description) = HTTPErrorClassifier.classify(URLError(.badServerResponse)) else {
            XCTFail("expected .other")
            return
        }

        XCTAssertTrue(description.contains("\(URLError.badServerResponse.rawValue)"), description)
    }

    func testNonURLErrorIsDescribed() {
        struct CustomError: Error {}

        XCTAssertEqual(HTTPErrorClassifier.classify(CustomError()), .other(description: "CustomError()"))
    }
}
