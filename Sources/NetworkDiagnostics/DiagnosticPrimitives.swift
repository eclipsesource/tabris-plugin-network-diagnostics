import Foundation

public struct DiagnosticPrimitives: Sendable {
    private let services: DiagnosticServices

    public init() {
        self.init(services: .live)
    }

    init(services: DiagnosticServices) {
        self.services = services
    }

    public func enumerateInterfaces() throws -> [NetworkInterfaceInfo] {
        try services.interfaces.enumerateInterfaces()
    }

    public func discoverGateways(timeoutSeconds: TimeInterval) async throws -> [DiscoveredGateway] {
        try await services.gateways.discoverGateways(timeoutSeconds: timeoutSeconds)
    }

    public func readDNSServers() throws -> [InternetAddress] {
        try services.dnsServers.readDNSServers()
    }

    public func ping(host: String, packetCount: Int, timeoutSeconds: TimeInterval) async -> PingHostResult {
        await probes(timeoutSeconds: timeoutSeconds).pingHost(host, packetCount: packetCount)
    }

    public func query(domain: String, server: InternetAddress, timeoutSeconds: TimeInterval) async -> DNSQueryResult {
        await probes(timeoutSeconds: timeoutSeconds).queryDNS(domain: domain, server: server)
    }

    public func probe(url: URL, method: HTTPProbeMethod, timeoutSeconds: TimeInterval) async -> HttpHostResult {
        await probes(timeoutSeconds: timeoutSeconds).probeHTTP(url, method: method)
    }

    private func probes(timeoutSeconds: TimeInterval) -> HostProbes {
        HostProbes(services: services, timeoutPerHostSeconds: timeoutSeconds)
    }
}
