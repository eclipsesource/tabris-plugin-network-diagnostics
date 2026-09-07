import Foundation

public enum HttpFailure: Codable, Sendable, Equatable {
    case dnsResolutionFailed
    case tlsHandshakeFailed
    case connectionRefused
    case timedOut
    case networkUnavailable
    case other(description: String)
}

public enum HttpOutcome: Codable, Sendable, Equatable {
    case response(statusCode: Int, latencyMs: Double)
    case failure(HttpFailure)
}

public struct HttpHostResult: Codable, Sendable, Equatable {
    public let url: URL
    public let outcome: HttpOutcome

    public init(url: URL, outcome: HttpOutcome) {
        self.url = url
        self.outcome = outcome
    }
}
