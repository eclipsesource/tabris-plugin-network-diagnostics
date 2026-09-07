@testable import NetworkDiagnostics
import XCTest

/// Every error that reaches JavaScript must carry one of the documented codes;
/// these tests pin the classification of the library's own error types.
final class NetworkDiagnosticsErrorTests: XCTestCase {
    func testServiceFailureBecomesUnavailableWithItsDescription() {
        let failure = ServiceFailure(component: "ResolvDNSServerReader", operation: "res_9_ninit", reason: "EPERM")

        let error = NetworkDiagnosticsError(failure)

        XCTAssertEqual(
            error,
            NetworkDiagnosticsError(code: .unavailable, message: "ResolvDNSServerReader.res_9_ninit failed: EPERM")
        )
    }

    func testCancellationBecomesCancelled() {
        XCTAssertEqual(NetworkDiagnosticsError(CancellationError()).code, .cancelled)
    }

    func testTabrisErrorPassesThroughUnchanged() {
        let original = NetworkDiagnosticsError(code: .alreadyRunning, message: "call cancel() first")

        XCTAssertEqual(NetworkDiagnosticsError(original as any Error), original)
    }

    func testUnknownErrorsBecomeUnavailableWithTheirDescription() {
        struct Unexpected: Error {}

        let error = NetworkDiagnosticsError(Unexpected())

        XCTAssertEqual(error.code, .unavailable)
        XCTAssertEqual(error.message, "Unexpected()")
    }
}
