import Foundation

struct ProbeResults {
    var gateways: [GatewayInfo] = []
    var dnsServers: [DNSServerInfo] = []
    var pings: [PingHostResult] = []
    var https: [HttpHostResult] = []
}

struct ProbeRunner: Sendable {
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

    func run(gateways: [DiscoveredGateway], dnsServers: [InternetAddress]) async -> ProbeResults {
        var tracker = StageTracker(emit: emit)
        var indexed: [(index: Int, probe: Probe)] = []

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
                group.addTask { .ping(index: index, await pingHost(host)) }
            }
            for (index, url) in configuration.httpHosts.enumerated() {
                group.addTask { .http(index: index, await probeHTTP(url)) }
            }
            for await probe in group {
                tracker.complete(probe.stage)
                emit(probe.event)
                indexed.append((probe.index, probe))
            }
        }
        return Self.collect(indexed.sorted { $0.index < $1.index }.map(\.probe))
    }

    private static func collect(_ probes: [Probe]) -> ProbeResults {
        probes.reduce(into: ProbeResults()) { results, probe in
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
            ping: await pingWithHardTimeout(gateway.address)
        )
    }

    private func checkDNSServer(_ server: InternetAddress) async -> DNSServerInfo {
        async let ping = pingWithHardTimeout(server)
        async let queries = queryDomains(on: server)

        return DNSServerInfo(address: server.description, ping: await ping, queries: await queries)
    }

    private func queryDomains(on server: InternetAddress) async -> [DNSQueryResult] {
        await withTaskGroup(of: (index: Int, result: DNSQueryResult).self) { group in
            for (index, domain) in configuration.dnsTestDomains.enumerated() {
                group.addTask {
                    let outcome = await services.dnsQuerier.query(
                        domain: domain,
                        server: server,
                        timeoutSeconds: configuration.timeoutPerHostSeconds
                    )

                    return (index, DNSQueryResult(domain: domain, outcome: outcome))
                }
            }
            var results: [(index: Int, result: DNSQueryResult)] = []

            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.index < $1.index }.map(\.result)
        }
    }

    private func pingWithHardTimeout(_ address: InternetAddress) async -> PingOutcome {
        let outcome = await withHardTimeout(seconds: configuration.timeoutPerHostSeconds) {
            await ping(address)
        }

        return outcome ?? .failed(reason: hardTimeoutReason)
    }

    private func pingHost(_ host: String) async -> PingHostResult {
        let result = await withHardTimeout(seconds: configuration.timeoutPerHostSeconds) {
            await resolveAndPing(host)
        }

        return result ?? PingHostResult(host: host, resolvedAddress: nil, outcome: .failed(reason: hardTimeoutReason))
    }

    private func resolveAndPing(_ host: String) async -> PingHostResult {
        do {
            let addresses = try await services.hostResolver.resolve(host: host)

            guard let address = addresses.first else {
                return PingHostResult(
                    host: host,
                    resolvedAddress: nil,
                    outcome: .resolutionFailed(reason: "no addresses")
                )
            }
            return PingHostResult(host: host, resolvedAddress: address.description, outcome: await ping(address))
        } catch {
            NetworkDiagnosticsLog.ping.error("Host resolution failed for \(host): \(error)")
            return PingHostResult(
                host: host,
                resolvedAddress: nil,
                outcome: .resolutionFailed(reason: String(describing: error))
            )
        }
    }

    private func ping(_ address: InternetAddress) async -> PingOutcome {
        await services.pinger.ping(
            address: address,
            packetCount: configuration.pingPacketCount,
            timeoutPerPacketSeconds: configuration.timeoutPerHostSeconds / Double(max(configuration.pingPacketCount, 1))
        )
    }

    private func probeHTTP(_ url: URL) async -> HttpHostResult {
        let outcome = await withHardTimeout(seconds: configuration.timeoutPerHostSeconds) {
            await services.httpProber.probe(
                url: url,
                method: configuration.httpMethod,
                timeoutSeconds: configuration.timeoutPerHostSeconds
            )
        }

        return HttpHostResult(url: url, outcome: outcome ?? .failure(.timedOut))
    }

    private var hardTimeoutReason: String {
        "no result within the \(configuration.timeoutPerHostSeconds)s hard timeout"
    }
}

struct StageTracker {
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
