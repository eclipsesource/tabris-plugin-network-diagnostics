import Foundation

/// URLProtocol stand-in for the network. Each test registers a handler for its
/// own URL so tests stay independent even when XCTest runs classes in parallel.
final class MockURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    /// A handler that never answers, used to exercise the client-side timeout.
    static let neverAnswers: Handler = { _ in
        throw HandlerError.never
    }

    nonisolated(unsafe) private static var handlers: [URL: Handler] = [:]
    private static let lock = NSLock()

    static func register(_ url: URL, handler: @escaping Handler) {
        lock.withLock { handlers[url] = handler }
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let handler = Self.lock.withLock({ Self.handlers[url] }) else {
            client?.urlProtocol(self, didFailWithError: HandlerError.unregistered(request.url))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch HandlerError.never {
            return
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    enum HandlerError: Error {
        case unregistered(URL?)
        case never
    }
}
