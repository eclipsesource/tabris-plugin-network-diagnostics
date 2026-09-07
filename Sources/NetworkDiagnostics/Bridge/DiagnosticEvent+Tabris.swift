struct NetworkDiagnosticsEvent {
    let name: String
    let attributes: [String: Any]
}

extension DiagnosticEvent {
    var tabrisEvent: NetworkDiagnosticsEvent? {
        switch self {
        case let .stageStarted(stage):
            NetworkDiagnosticsEvent(name: "stageStarted", attributes: ["stage": stage.rawValue])
        case let .stageFinished(stage):
            NetworkDiagnosticsEvent(name: "stageFinished", attributes: ["stage": stage.rawValue])
        case let .gatewayResult(gateway):
            NetworkDiagnosticsEvent(name: "gatewayResult", attributes: gateway.tabrisObject)
        case let .dnsServerResult(server):
            NetworkDiagnosticsEvent(name: "dnsServerResult", attributes: server.tabrisObject)
        case let .pingResult(result):
            NetworkDiagnosticsEvent(name: "pingResult", attributes: result.tabrisObject)
        case let .httpResult(result):
            NetworkDiagnosticsEvent(name: "httpResult", attributes: result.tabrisObject)
        case .completed:
            nil
        }
    }
}
