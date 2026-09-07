public enum DiagnosticStage: String, Codable, Sendable, CaseIterable {
    case interfaces
    case gateways
    case dnsServers
    case gatewayPing
    case dnsServerCheck
    case hostPing
    case httpProbe
}

public enum DiagnosticEvent: Sendable, Equatable {
    case stageStarted(DiagnosticStage)
    case stageFinished(DiagnosticStage)
    case gatewayResult(GatewayInfo)
    case dnsServerResult(DNSServerInfo)
    case pingResult(PingHostResult)
    case httpResult(HttpHostResult)
    case completed(DiagnosticReport)
}
