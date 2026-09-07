import Foundation

public struct DiagnosticReport: Codable, Sendable, Equatable {
    public let startedAt: Date
    public let durationSeconds: TimeInterval
    public let interfaces: InterfaceDiscovery
    public let gateways: GatewayDiscovery
    public let dnsServers: DNSServerDiscovery
    public let pingResults: [PingHostResult]
    public let httpResults: [HttpHostResult]
    public let summary: DiagnosticSummary

    public init(
        startedAt: Date,
        durationSeconds: TimeInterval,
        interfaces: InterfaceDiscovery,
        gateways: GatewayDiscovery,
        dnsServers: DNSServerDiscovery,
        pingResults: [PingHostResult],
        httpResults: [HttpHostResult],
        summary: DiagnosticSummary
    ) {
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.interfaces = interfaces
        self.gateways = gateways
        self.dnsServers = dnsServers
        self.pingResults = pingResults
        self.httpResults = httpResults
        self.summary = summary
    }
}
