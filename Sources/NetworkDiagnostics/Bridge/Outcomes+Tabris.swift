import Foundation

extension PingStatistics: NetworkDiagnosticsRepresentable {
    var tabrisObject: [String: Any] {
        [
            "sentPackets": sentPackets,
            "receivedPackets": receivedPackets,
            "minRttMs": minRttMs,
            "avgRttMs": avgRttMs,
            "maxRttMs": maxRttMs,
            "packetLossPercent": packetLossPercent,
        ]
    }
}

extension PingOutcome: NetworkDiagnosticsRepresentable {
    var tabrisObject: [String: Any] {
        switch self {
        case let .reachable(statistics):
            statistics.tabrisObject.merging(["state": "reachable"]) { _, state in state }
        case let .unreachable(sentPackets):
            ["state": "unreachable", "sentPackets": sentPackets]
        case let .resolutionFailed(reason):
            ["state": "resolutionFailed", "reason": reason]
        case let .failed(reason):
            ["state": "failed", "reason": reason]
        }
    }
}

extension PingHostResult: NetworkDiagnosticsRepresentable {
    var tabrisObject: [String: Any] {
        [
            "host": host,
            "resolvedAddress": networkDiagnosticsOptional(resolvedAddress),
            "outcome": outcome.tabrisObject,
        ]
    }
}

extension HttpFailure {
    var tabrisName: String {
        switch self {
        case .dnsResolutionFailed: "dnsResolutionFailed"
        case .tlsHandshakeFailed: "tlsHandshakeFailed"
        case .connectionRefused: "connectionRefused"
        case .timedOut: "timedOut"
        case .networkUnavailable: "networkUnavailable"
        case .other: "other"
        }
    }
}

extension HttpOutcome: NetworkDiagnosticsRepresentable {
    var tabrisObject: [String: Any] {
        switch self {
        case let .response(statusCode, latencyMs):
            ["state": "response", "statusCode": statusCode, "latencyMs": latencyMs]
        case let .failure(.other(description)):
            [
                "state": "failure",
                "failure": HttpFailure.other(description: description).tabrisName,
                "description": description,
            ]
        case let .failure(failure):
            ["state": "failure", "failure": failure.tabrisName]
        }
    }
}

extension HttpHostResult: NetworkDiagnosticsRepresentable {
    var tabrisObject: [String: Any] {
        ["url": url.absoluteString, "outcome": outcome.tabrisObject]
    }
}

extension DNSResponseCode {
    var tabrisName: String {
        switch self {
        case .noError: "noError"
        case .formatError: "formatError"
        case .serverFailure: "serverFailure"
        case .nameError: "nameError"
        case .notImplemented: "notImplemented"
        case .refused: "refused"
        case .other: "other"
        }
    }

    var rawCode: Int {
        switch self {
        case .noError: 0
        case .formatError: 1
        case .serverFailure: 2
        case .nameError: 3
        case .notImplemented: 4
        case .refused: 5
        case let .other(code): code
        }
    }
}

extension DNSQueryOutcome: NetworkDiagnosticsRepresentable {
    var tabrisObject: [String: Any] {
        switch self {
        case let .answered(responseCode, addresses, latencyMs):
            [
                "state": "answered",
                "responseCode": responseCode.tabrisName,
                "rcode": responseCode.rawCode,
                "addresses": addresses,
                "latencyMs": latencyMs,
            ]
        case .timedOut:
            ["state": "timedOut"]
        case let .failed(reason):
            ["state": "failed", "reason": reason]
        }
    }
}

extension DNSQueryResult: NetworkDiagnosticsRepresentable {
    var tabrisObject: [String: Any] {
        ["domain": domain, "outcome": outcome.tabrisObject, "isResolved": isResolved]
    }

    func tabrisObject(server: InternetAddress) -> [String: Any] {
        tabrisObject.merging(["server": server.description]) { _, server in server }
    }
}
