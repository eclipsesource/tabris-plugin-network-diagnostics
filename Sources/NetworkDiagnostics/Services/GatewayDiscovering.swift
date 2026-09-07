import Foundation
import Network

protocol GatewayDiscovering: Sendable {
    func discoverGateways(timeoutSeconds: TimeInterval) async throws -> [DiscoveredGateway]
}

struct PathMonitorGatewayDiscoverer: GatewayDiscovering {
    func discoverGateways(timeoutSeconds: TimeInterval) async throws -> [DiscoveredGateway] {
        let monitor = NWPathMonitor()
        let updates = AsyncStream<[DiscoveredGateway]> { continuation in
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.gateways.compactMap(Self.gateway(from:)))
            }
        }

        monitor.start(queue: DispatchQueue(label: "NetworkDiagnostics.gateways"))
        defer { monitor.cancel() }

        let firstUpdate = await withHardTimeout(seconds: timeoutSeconds) {
            await updates.first { _ in true }
        }

        guard let gateways = firstUpdate.flatMap({ $0 }) else {
            throw ServiceFailure(
                component: "PathMonitorGatewayDiscoverer",
                operation: "NWPathMonitor.pathUpdateHandler",
                reason: "no path update within \(timeoutSeconds)s"
            )
        }
        return gateways
    }

    private static func gateway(from endpoint: NWEndpoint) -> DiscoveredGateway? {
        guard case let .hostPort(host, _) = endpoint else { return nil }
        let address: InternetAddress?

        switch host {
        case let .ipv4(ipv4):
            address = InternetAddress(family: .ipv4, rawBytes: ipv4.rawValue)
        case let .ipv6(ipv6):
            address = InternetAddress(family: .ipv6, rawBytes: ipv6.rawValue)
        default:
            address = nil
        }
        return address.map { DiscoveredGateway(address: $0, interfaceName: endpoint.interface?.name) }
    }
}
