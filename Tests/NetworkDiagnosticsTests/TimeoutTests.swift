@testable import NetworkDiagnostics
import XCTest

/// `withHardTimeout` must return when the budget is spent even if the operation
/// never observes cancellation; otherwise a stuck resolver would hold a whole
/// diagnosis (and the JavaScript promise behind it) hostage.
final class TimeoutTests: XCTestCase {
    func testReturnsTheValueWhenTheOperationFinishesFirst() async {
        let value = await withHardTimeout(seconds: 5) { 42 }

        XCTAssertEqual(value, 42)
    }

    func testReturnsNilWhenTheOperationIgnoresCancellation() async {
        let clock = ContinuousClock()
        let start = clock.now

        let value: Int? = await withHardTimeout(seconds: 0.2) {
            await withCheckedContinuation { (_: CheckedContinuation<Int, Never>) in }
        }

        XCTAssertNil(value)
        XCTAssertLessThan(clock.now - start, .seconds(2))
    }

    func testReturnsNilWhenACooperativeOperationOverrunsTheBudget() async {
        let value: Int? = await withHardTimeout(seconds: 0.1) {
            try? await Task.sleep(for: .seconds(10))
            return 1
        }

        XCTAssertNil(value)
    }

    func testCancellationOfTheCallerEndsTheWaitPromptly() async {
        let clock = ContinuousClock()
        let start = clock.now
        let waiting = Task<Int?, Never> {
            await withHardTimeout(seconds: 10) {
                await withCheckedContinuation { (_: CheckedContinuation<Int, Never>) in }
            }
        }

        try? await Task.sleep(for: .milliseconds(50))
        waiting.cancel()
        let value = await waiting.value

        XCTAssertNil(value)
        XCTAssertLessThan(clock.now - start, .seconds(2))
    }
}
