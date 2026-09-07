public struct PingStatistics: Codable, Sendable, Equatable {
    public let sentPackets: Int
    public let receivedPackets: Int
    public let minRttMs: Double
    public let avgRttMs: Double
    public let maxRttMs: Double
    public let packetLossPercent: Double

    public init(
        sentPackets: Int,
        receivedPackets: Int,
        minRttMs: Double,
        avgRttMs: Double,
        maxRttMs: Double,
        packetLossPercent: Double
    ) {
        self.sentPackets = sentPackets
        self.receivedPackets = receivedPackets
        self.minRttMs = minRttMs
        self.avgRttMs = avgRttMs
        self.maxRttMs = maxRttMs
        self.packetLossPercent = packetLossPercent
    }
}

public enum PingOutcome: Codable, Sendable, Equatable {
    case reachable(PingStatistics)
    case unreachable(sentPackets: Int)
    case resolutionFailed(reason: String)
    case failed(reason: String)
}

public struct PingHostResult: Codable, Sendable, Equatable {
    public let host: String
    public let resolvedAddress: String?
    public let outcome: PingOutcome

    public init(host: String, resolvedAddress: String?, outcome: PingOutcome) {
        self.host = host
        self.resolvedAddress = resolvedAddress
        self.outcome = outcome
    }
}
