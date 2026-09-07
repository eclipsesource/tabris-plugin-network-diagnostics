import Foundation
import Network

/// Minimal in-process HTTP/1.1 server bound to 127.0.0.1 on an ephemeral port.
/// It answers every request with an empty 200 so integration tests never need
/// the public internet.
final class LoopbackHTTPServer: @unchecked Sendable {
    private static let response = Data("HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)

    private let listener: NWListener
    private let queue = DispatchQueue(label: "LoopbackHTTPServer")
    let port: UInt16

    var url: URL {
        get throws {
            guard let url = URL(string: "http://127.0.0.1:\(port)/") else {
                throw ServerError.invalidURL
            }
            return url
        }
    }

    private init(listener: NWListener, port: UInt16) {
        self.listener = listener
        self.port = port
    }

    static func start() async throws -> LoopbackHTTPServer {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "LoopbackHTTPServer.listener")
        let states = AsyncStream<NWListener.State> { continuation in
            listener.stateUpdateHandler = { continuation.yield($0) }
        }

        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { _, _, _, _ in
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: queue)

        for await state in states {
            switch state {
            case .ready:
                guard let port = listener.port?.rawValue else { throw ServerError.noPort }
                return LoopbackHTTPServer(listener: listener, port: port)
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

    enum ServerError: Error {
        case invalidURL
        case noPort
        case listenerStoppedBeforeReady
    }
}
