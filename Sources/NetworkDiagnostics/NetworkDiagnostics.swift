import Foundation

public struct NetworkDiagnostics: Sendable {
    private let services: DiagnosticServices

    public init() {
        self.init(services: .live)
    }

    init(services: DiagnosticServices) {
        self.services = services
    }

    public func diagnose(_ configuration: DiagnosticConfiguration) -> AsyncStream<DiagnosticEvent> {
        AsyncStream { continuation in
            let task = Task {
                _ = await collectReport(configuration) { continuation.yield($0) }
                continuation.finish()
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func runDiagnostics(_ configuration: DiagnosticConfiguration) async -> DiagnosticReport {
        await collectReport(configuration) { _ in }
    }

    private func collectReport(
        _ configuration: DiagnosticConfiguration,
        emit: @escaping EventSink
    ) async -> DiagnosticReport {
        let startedAt = Date()
        let startedInstant = ContinuousClock.now
        async let interfaces = discoverInterfaces(emit: emit)
        async let gateways = discoverGateways(timeoutSeconds: configuration.timeoutPerHostSeconds, emit: emit)
        async let dnsServers = discoverDNSServers(emit: emit)
        let discoveredInterfaces = await interfaces
        let discoveredGateways = await gateways
        let discoveredDNSServers = await dnsServers
        let probes = await ProbeRunner(services: services, configuration: configuration, emit: emit)
            .run(gateways: discoveredGateways.gateways, dnsServers: discoveredDNSServers.servers)
        let gatewayDiscovery = discoveredGateways.discovery(pinged: probes.gateways)
        let dnsDiscovery = discoveredDNSServers.discovery(checked: probes.dnsServers)
        let report = DiagnosticReport(
            startedAt: startedAt,
            durationSeconds: (ContinuousClock.now - startedInstant).milliseconds / 1_000,
            interfaces: discoveredInterfaces,
            gateways: gatewayDiscovery,
            dnsServers: dnsDiscovery,
            pingResults: probes.pings,
            httpResults: probes.https,
            summary: SummaryBuilder.summarize(
                interfaces: discoveredInterfaces,
                gateways: gatewayDiscovery,
                dnsServers: dnsDiscovery,
                pingResults: probes.pings,
                httpResults: probes.https
            )
        )

        emit(.completed(report))
        return report
    }

    private func discoverInterfaces(emit: EventSink) async -> InterfaceDiscovery {
        emit(.stageStarted(.interfaces))
        defer { emit(.stageFinished(.interfaces)) }
        do {
            return .found(try services.interfaces.enumerateInterfaces())
        } catch {
            NetworkDiagnosticsLog.interfaces.error("Interface enumeration failed: \(error)")
            return .unavailable(reason: String(describing: error))
        }
    }

    private func discoverGateways(timeoutSeconds: TimeInterval, emit: EventSink) async -> GatewayDiscoveryStep {
        emit(.stageStarted(.gateways))
        defer { emit(.stageFinished(.gateways)) }
        do {
            return .found(try await services.gateways.discoverGateways(timeoutSeconds: timeoutSeconds))
        } catch {
            NetworkDiagnosticsLog.gateways.error("Gateway discovery failed: \(error)")
            return .unavailable(reason: String(describing: error))
        }
    }

    private func discoverDNSServers(emit: EventSink) async -> DNSServerDiscoveryStep {
        emit(.stageStarted(.dnsServers))
        defer { emit(.stageFinished(.dnsServers)) }
        do {
            return .found(try services.dnsServers.readDNSServers())
        } catch {
            NetworkDiagnosticsLog.dns.error("DNS server discovery failed: \(error)")
            return .unavailable(reason: String(describing: error))
        }
    }
}

typealias EventSink = @Sendable (DiagnosticEvent) -> Void

enum DNSServerDiscoveryStep {
    case found([InternetAddress])
    case unavailable(reason: String)

    var servers: [InternetAddress] {
        if case let .found(servers) = self { servers } else { [] }
    }

    func discovery(checked: [DNSServerInfo]) -> DNSServerDiscovery {
        switch self {
        case .found: .found(checked)
        case let .unavailable(reason): .unavailable(reason: reason)
        }
    }
}

enum GatewayDiscoveryStep {
    case found([DiscoveredGateway])
    case unavailable(reason: String)

    var gateways: [DiscoveredGateway] {
        if case let .found(gateways) = self { gateways } else { [] }
    }

    func discovery(pinged: [GatewayInfo]) -> GatewayDiscovery {
        switch self {
        case .found: .found(pinged)
        case let .unavailable(reason): .unavailable(reason: reason)
        }
    }
}
