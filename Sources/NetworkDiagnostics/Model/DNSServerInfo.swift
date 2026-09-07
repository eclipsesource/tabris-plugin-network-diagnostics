public enum DNSResponseCode: Codable, Sendable, Equatable {
    case noError
    case formatError
    case serverFailure
    case nameError
    case notImplemented
    case refused
    case other(code: Int)

    public init(rawCode: Int) {
        switch rawCode {
        case 0: self = .noError
        case 1: self = .formatError
        case 2: self = .serverFailure
        case 3: self = .nameError
        case 4: self = .notImplemented
        case 5: self = .refused
        default: self = .other(code: rawCode)
        }
    }
}

public enum DNSQueryOutcome: Codable, Sendable, Equatable {
    case answered(responseCode: DNSResponseCode, addresses: [String], latencyMs: Double)
    case timedOut
    case failed(reason: String)
}

public struct DNSQueryResult: Codable, Sendable, Equatable {
    public let domain: String
    public let outcome: DNSQueryOutcome

    public init(domain: String, outcome: DNSQueryOutcome) {
        self.domain = domain
        self.outcome = outcome
    }

    public var isResolved: Bool {
        if case let .answered(.noError, addresses, _) = outcome { !addresses.isEmpty } else { false }
    }
}

public struct DNSServerInfo: Codable, Sendable, Equatable {
    public let address: String
    public let ping: PingOutcome
    public let queries: [DNSQueryResult]

    public init(address: String, ping: PingOutcome, queries: [DNSQueryResult]) {
        self.address = address
        self.ping = ping
        self.queries = queries
    }
}

public enum DNSServerDiscovery: Codable, Sendable, Equatable {
    case found([DNSServerInfo])
    case unavailable(reason: String)
}
