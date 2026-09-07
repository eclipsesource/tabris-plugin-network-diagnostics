import Foundation

protocol HTTPProbing: Sendable {
    func probe(url: URL, method: HTTPProbeMethod, timeoutSeconds: TimeInterval) async -> HttpOutcome
}

struct URLSessionHTTPProber: HTTPProbing {
    private let session: URLSession

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    func probe(url: URL, method: HTTPProbeMethod, timeoutSeconds: TimeInterval) async -> HttpOutcome {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: timeoutSeconds
        )
        let startedAt = ContinuousClock.now

        request.httpMethod = method.rawValue
        do {
            let (_, response) = try await session.data(for: request)
            let latencyMs = (ContinuousClock.now - startedAt).networkDiagnosticsMilliseconds

            guard let httpResponse = response as? HTTPURLResponse else {
                NetworkDiagnosticsLog.http.error("URLSessionHTTPProber.probe(\(url)) received a non-HTTP response")
                return .failure(.other(description: "non-HTTP response"))
            }
            return .response(statusCode: httpResponse.statusCode, latencyMs: latencyMs)
        } catch {
            NetworkDiagnosticsLog.http.error("URLSessionHTTPProber.probe(\(url)) failed: \(error)")
            return .failure(HTTPErrorClassifier.classify(error))
        }
    }
}
