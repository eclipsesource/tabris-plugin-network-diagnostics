extension PingOutcome {
    init(sentPackets: Int, rttSamplesMs: [Double]) {
        guard let minRtt = rttSamplesMs.min(), let maxRtt = rttSamplesMs.max() else {
            self = .unreachable(sentPackets: sentPackets)
            return
        }
        let received = rttSamplesMs.count
        let lost = max(sentPackets - received, 0)

        self = .reachable(
            PingStatistics(
                sentPackets: sentPackets,
                receivedPackets: received,
                minRttMs: minRtt,
                avgRttMs: rttSamplesMs.reduce(0, +) / Double(received),
                maxRttMs: maxRtt,
                packetLossPercent: sentPackets > 0 ? Double(lost) / Double(sentPackets) * 100 : 0
            )
        )
    }
}
