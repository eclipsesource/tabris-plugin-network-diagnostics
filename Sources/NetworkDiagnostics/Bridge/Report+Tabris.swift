import Foundation

extension DiagnosticVerdict {
    var tabrisName: String {
        switch self {
        case .healthy: "healthy"
        case .noActiveInterface: "noActiveInterface"
        case .gatewayUnreachable: "gatewayUnreachable"
        case .dnsResolutionFailing: "dnsResolutionFailing"
        case .remoteHostsUnreachable: "remoteHostsUnreachable"
        case .partialConnectivity: "partialConnectivity"
        case .inconclusive: "inconclusive"
        }
    }
}

extension DiagnosticSummary: NetworkDiagnosticsRepresentable {
    var tabrisObject: [String: Any] {
        switch verdict {
        case let .inconclusive(reason):
            ["verdict": verdict.tabrisName, "reason": reason, "message": message]
        default:
            ["verdict": verdict.tabrisName, "message": message]
        }
    }
}

extension DiagnosticReport: NetworkDiagnosticsRepresentable {
    var tabrisObject: [String: Any] {
        [
            "startedAt": startedAt.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)),
            "durationSeconds": durationSeconds,
            "interfaces": interfaces.tabrisObject,
            "gateways": gateways.tabrisObject,
            "dnsServers": dnsServers.tabrisObject,
            "pingResults": pingResults.tabrisObjects,
            "httpResults": httpResults.tabrisObjects,
            "summary": summary.tabrisObject,
        ]
    }
}
