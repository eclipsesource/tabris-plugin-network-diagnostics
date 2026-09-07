import Foundation

struct ProbeRunner: Sendable {
    struct Results {
        var gateways: [GatewayInfo] = []
        var dnsServers: [DNSServerInfo] = []
        var pings: [PingHostResult] = []
        var https: [HttpHostResult] = []
    }

    private struct StageTracker {
        private let emit: EventSink
        private var remaining: [DiagnosticStage: Int] = [:]

        init(emit: @escaping EventSink) {
            self.emit = emit
        }

        mutating func start(_ stage: DiagnosticStage, count: Int) {
            emit(.stageStarted(stage))
            remaining[stage] = count
            if count == 0 {
                emit(.stageFinished(stage))
            }
        }

        mutating func complete(_ stage: DiagnosticStage) {
            let left = (remaining[stage] ?? 0) - 1

            remaining[stage] = left
            if left == 0 {
                emit(.stageFinished(stage))
            }
        }
    }

    private enum Probe: Sendable {
        case gateway(index: Int, GatewayInfo)
        case dnsServer(index: Int, DNSServerInfo)
        case ping(index: Int, PingHostResult)
        case http(index: Int, HttpHostResult)

        var index: Int {
            switch self {
            case let .gateway(index, _), let .dnsServer(index, _), let .ping(index, _), let .http(index, _): index
            }
        }

        var stage: DiagnosticStage {
            switch self {
            case .gateway: .gatewayPing
            case .dnsServer: .dnsServerCheck
            case .ping: .hostPing
            case .http: .httpProbe
            }
        }

        var event: DiagnosticEvent {
            switch self {
            case let .gateway(_, info): .gatewayResult(info)
            case let .dnsServer(_, info): .dnsServerResult(info)
            case let .ping(_, result): .pingResult(result)
            case let .http(_, result): .httpResult(result)
            }
        }
    }

    let services: DiagnosticServices
    let configuration: DiagnosticConfiguration
    let emit: EventSink

    private var probes: HostProbes {
        HostProbes(services: services, timeoutPerHostSeconds: configuration.timeoutPerHostSeconds)
    }

    func run(gateways: [DiscoveredGateway], dnsServers: [InternetAddress]) async -> Results {
        var tracker = StageTracker(emit: emit)
        var indexed: [(index: Int, probe: Probe)] = []
        let probes = self.probes
        let packetCount = configuration.pingPacketCount
        let httpMethod = configuration.httpMethod

        tracker.start(.gatewayPing, count: gateways.count)
        tracker.start(.dnsServerCheck, count: dnsServers.count)
        tracker.start(.hostPing, count: configuration.pingHosts.count)
        tracker.start(.httpProbe, count: configuration.httpHosts.count)
        await withTaskGroup(of: Probe.self) { group in
            for (index, gateway) in gateways.enumerated() {
                group.addTask { .gateway(index: index, await pingGateway(gateway)) }
            }
            for (index, server) in dnsServers.enumerated() {
                group.addTask { .dnsServer(index: index, await checkDNSServer(server)) }
            }
            for (index, host) in configuration.pingHosts.enumerated() {
                group.addTask { .ping(index: index, await probes.pingHost(host, packetCount: packetCount)) }
            }
            for (index, url) in configuration.httpHosts.enumerated() {
                group.addTask { .http(index: index, await probes.probeHTTP(url, method: httpMethod)) }
            }
            for await probe in group {
                tracker.complete(probe.stage)
                emit(probe.event)
                indexed.append((probe.index, probe))
            }
        }
        return Self.collect(indexed.sorted { $0.index < $1.index }.map(\.probe))
    }

    private static func collect(_ probes: [Probe]) -> Results {
        probes.reduce(into: Results()) { results, probe in
            switch probe {
            case let .gateway(_, info): results.gateways.append(info)
            case let .dnsServer(_, info): results.dnsServers.append(info)
            case let .ping(_, result): results.pings.append(result)
            case let .http(_, result): results.https.append(result)
            }
        }
    }

    private func pingGateway(_ gateway: DiscoveredGateway) async -> GatewayInfo {
        GatewayInfo(
            address: gateway.address.description,
            interfaceName: gateway.interfaceName,
            ping: await probes.pingWithHardTimeout(gateway.address, packetCount: configuration.pingPacketCount)
        )
    }

    private func checkDNSServer(_ server: InternetAddress) async -> DNSServerInfo {
        async let ping = probes.pingWithHardTimeout(server, packetCount: configuration.pingPacketCount)
        async let queries = queryDomains(on: server)

        return DNSServerInfo(address: server.description, ping: await ping, queries: await queries)
    }

    private func queryDomains(on server: InternetAddress) async -> [DNSQueryResult] {
        let probes = self.probes

        return await withTaskGroup(of: (index: Int, result: DNSQueryResult).self) { group in
            for (index, domain) in configuration.dnsTestDomains.enumerated() {
                group.addTask { (index, await probes.queryDNS(domain: domain, server: server)) }
            }
            var results: [(index: Int, result: DNSQueryResult)] = []

            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.index < $1.index }.map(\.result)
        }
    }
}
