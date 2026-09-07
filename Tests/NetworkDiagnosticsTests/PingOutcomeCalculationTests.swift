@testable import NetworkDiagnostics
import XCTest

final class PingOutcomeCalculationTests: XCTestCase {
    func testComputesStatisticsFromSamples() {
        let outcome = PingOutcome(sentPackets: 4, rttSamplesMs: [10, 20, 30])

        XCTAssertEqual(
            outcome,
            .reachable(
                PingStatistics(
                    sentPackets: 4,
                    receivedPackets: 3,
                    minRttMs: 10,
                    avgRttMs: 20,
                    maxRttMs: 30,
                    packetLossPercent: 25
                )
            )
        )
    }

    func testNoRepliesMeansUnreachable() {
        XCTAssertEqual(PingOutcome(sentPackets: 3, rttSamplesMs: []), .unreachable(sentPackets: 3))
    }

    func testAllRepliesMeansZeroLoss() {
        guard case let .reachable(statistics) = PingOutcome(sentPackets: 2, rttSamplesMs: [1.5, 2.5]) else {
            XCTFail("expected reachable outcome")
            return
        }

        XCTAssertEqual(statistics.packetLossPercent, 0)
        XCTAssertEqual(statistics.avgRttMs, 2)
    }
}
