import Foundation
import Network

/// Minimal UDP DNS responder on 127.0.0.1 with an ephemeral port. It echoes
/// the query's id and question and answers every A query with 203.0.113.7.
final class LoopbackDNSServer: @unchecked Sendable {
    static let answerAddress = "203.0.113.7"
    private static let answerBytes: [UInt8] = [203, 0, 113, 7]

    private let listener: NWListener
    let port: UInt16

    private init(listener: NWListener, port: UInt16) {
        self.listener = listener
        self.port = port
    }

    static func start() async throws -> LoopbackDNSServer {
        let parameters = NWParameters.udp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "LoopbackDNSServer")
        let states = AsyncStream<NWListener.State> { continuation in
            listener.stateUpdateHandler = { continuation.yield($0) }
        }

        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receiveMessage { data, _, _, _ in
                guard let data, let reply = response(to: data) else {
                    connection.cancel()
                    return
                }
                connection.send(content: reply, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: queue)

        for await state in states {
            switch state {
            case .ready:
                guard let port = listener.port?.rawValue else { throw ServerError.noPort }
                return LoopbackDNSServer(listener: listener, port: port)
            case let .failed(error):
                throw error
            default:
                continue
            }
        }
        throw ServerError.listenerStoppedBeforeReady
    }

    func stop() {
        listener.cancel()
    }

    /// Copies header id + question, sets QR/RD/RA flags, ANCOUNT 1, and appends
    /// one A record pointing back at the question name.
    private static func response(to query: Data) -> Data? {
        let bytes = [UInt8](query)
        guard bytes.count > 12 else { return nil }
        var response = Data(bytes[0..<2])
        response.append(contentsOf: [0x81, 0x80, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00])
        response.append(contentsOf: bytes[12...])
        response.append(contentsOf: [0xC0, 0x0C, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x3C, 0x00, 0x04])
        response.append(contentsOf: answerBytes)
        return response
    }

    enum ServerError: Error {
        case noPort
        case listenerStoppedBeforeReady
    }
}
