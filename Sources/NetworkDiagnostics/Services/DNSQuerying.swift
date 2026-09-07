import Foundation
import Network

protocol DNSQuerying: Sendable {
    func query(domain: String, server: InternetAddress, timeoutSeconds: TimeInterval) async -> DNSQueryOutcome
}

struct UDPDNSQuerier: DNSQuerying {
    private let port: NWEndpoint.Port

    init(port: UInt16 = 53) {
        self.port = NWEndpoint.Port(rawValue: port) ?? .init(integerLiteral: 53)
    }

    func query(domain: String, server: InternetAddress, timeoutSeconds: TimeInterval) async -> DNSQueryOutcome {
        let identifier = UInt16.random(in: 0...UInt16.max)

        guard let message = DNSMessage.query(domain: domain, identifier: identifier) else {
            return .failed(reason: "\(domain) is not a valid DNS name")
        }
        guard let host = server.endpointHost else {
            return .failed(reason: "\(server) cannot be expressed as a Network.framework host")
        }
        let outcome = await withHardTimeout(seconds: timeoutSeconds) {
            await exchange(message, identifier: identifier, host: host)
        }

        return outcome ?? .timedOut
    }

    private func exchange(_ message: Data, identifier: UInt16, host: NWEndpoint.Host) async -> DNSQueryOutcome {
        let connection = NWConnection(host: host, port: port, using: .udp)
        let startedAt = ContinuousClock.now
        let outcomes = AsyncStream<DNSQueryOutcome> { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: message, completion: .contentProcessed { error in
                        if let error {
                            continuation.yield(.failed(reason: "send failed: \(error)"))
                        }
                    })
                    connection.receiveMessage { data, _, _, error in
                        continuation.yield(
                            Self.outcome(data: data, error: error, identifier: identifier, startedAt: startedAt)
                        )
                    }
                case let .failed(error):
                    continuation.yield(.failed(reason: "connection failed: \(error)"))
                case let .waiting(error):
                    continuation.yield(.failed(reason: "no route to server: \(error)"))
                default:
                    break
                }
            }
        }

        connection.start(queue: DispatchQueue(label: "NetworkDiagnostics.dns"))
        defer { connection.cancel() }
        return await outcomes.first { _ in true } ?? .failed(reason: "connection closed before a reply arrived")
    }

    private static func outcome(
        data: Data?,
        error: NWError?,
        identifier: UInt16,
        startedAt: ContinuousClock.Instant
    ) -> DNSQueryOutcome {
        let latencyMs = (ContinuousClock.now - startedAt).milliseconds

        if let error {
            return .failed(reason: "receive failed: \(error)")
        }
        guard let data, let response = DNSMessage.parseResponse(data) else {
            return .failed(reason: "reply of \(data?.count ?? 0) bytes is not a DNS response")
        }
        guard response.identifier == identifier else {
            return .failed(reason: "reply identifier \(response.identifier) does not match query \(identifier)")
        }
        return .answered(responseCode: response.responseCode, addresses: response.addresses, latencyMs: latencyMs)
    }
}

extension InternetAddress {
    var endpointHost: NWEndpoint.Host? {
        switch family {
        case .ipv4: IPv4Address(rawBytes).map(NWEndpoint.Host.ipv4)
        case .ipv6: IPv6Address(rawBytes).map(NWEndpoint.Host.ipv6)
        }
    }
}
