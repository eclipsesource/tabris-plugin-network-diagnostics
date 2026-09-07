import Foundation

struct NetworkDiagnosticsParameterError: LocalizedError, Equatable {
    let errorDescription: String?

    init(_ description: String) {
        errorDescription = description
    }
}

enum NetworkDiagnosticsParameters {
    struct Ping: Equatable, Sendable {
        let host: String
        let packetCount: Int
        let timeoutSeconds: TimeInterval
    }

    struct DNSQuery: Equatable, Sendable {
        let domain: String
        let server: InternetAddress
        let timeoutSeconds: TimeInterval
    }

    struct HTTP: Equatable, Sendable {
        let url: URL
        let method: HTTPProbeMethod
        let timeoutSeconds: TimeInterval
    }

    struct Gateway: Equatable, Sendable {
        let timeoutSeconds: TimeInterval
    }

    static let defaultTimeoutSeconds: TimeInterval = 3
    static let defaultPacketCount = 3
    static let allowedSchemes: Set<String> = ["http", "https"]

    static func ping(_ parameters: [String: Any]) throws -> Ping {
        Ping(
            host: try requiredText(parameters, key: "host"),
            packetCount: try packetCount(parameters, key: "packetCount"),
            timeoutSeconds: try timeout(parameters, key: "timeoutSeconds")
        )
    }

    static func dnsQuery(_ parameters: [String: Any]) throws -> DNSQuery {
        DNSQuery(
            domain: try requiredText(parameters, key: "domain"),
            server: try address(parameters, key: "server"),
            timeoutSeconds: try timeout(parameters, key: "timeoutSeconds")
        )
    }

    static func http(_ parameters: [String: Any]) throws -> HTTP {
        HTTP(
            url: try url(parameters, key: "url"),
            method: try method(parameters, key: "method"),
            timeoutSeconds: try timeout(parameters, key: "timeoutSeconds")
        )
    }

    static func gateways(_ parameters: [String: Any]) throws -> Gateway {
        Gateway(timeoutSeconds: try timeout(parameters, key: "timeoutSeconds"))
    }

    static func diagnosticConfiguration(_ parameters: [String: Any]) throws -> DiagnosticConfiguration {
        DiagnosticConfiguration(
            pingHosts: try textList(parameters, key: "pingHosts"),
            httpHosts: try textList(parameters, key: "httpHosts").map { try url($0, key: "httpHosts") },
            dnsTestDomains: try textList(parameters, key: "dnsTestDomains"),
            timeoutPerHostSeconds: try timeout(parameters, key: "timeoutPerHostSeconds"),
            pingPacketCount: try packetCount(parameters, key: "pingPacketCount"),
            httpMethod: try method(parameters, key: "httpMethod")
        )
    }

    static func textList(_ parameters: [String: Any], key: String) throws -> [String] {
        guard let value = parameters[key] else { return [] }
        guard let items = value as? [String] else {
            throw NetworkDiagnosticsParameterError("\(key) must be an array of strings, received \(describe(value))")
        }
        let trimmed = items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard !trimmed.contains(where: \.isEmpty) else {
            throw NetworkDiagnosticsParameterError("\(key) must not contain empty strings, received \(items)")
        }
        return trimmed
    }

    static func timeout(_ parameters: [String: Any], key: String) throws -> TimeInterval {
        guard let value = parameters[key] else { return defaultTimeoutSeconds }
        guard let seconds = number(value), seconds > 0, seconds.isFinite else {
            throw NetworkDiagnosticsParameterError(
                "\(key) must be a number of seconds greater than 0, received \(describe(value))"
            )
        }
        return seconds
    }

    static func packetCount(_ parameters: [String: Any], key: String) throws -> Int {
        guard let value = parameters[key] else { return defaultPacketCount }
        guard let count = integral(number(value)), count >= 1 else {
            throw NetworkDiagnosticsParameterError(
                "\(key) must be an integer of at least 1, received \(describe(value))"
            )
        }
        return count
    }

    static func number(_ value: Any) -> Double? {
        guard CFGetTypeID(value as AnyObject) != CFBooleanGetTypeID() else { return nil }
        return value as? Double ?? (value as? Int).map(Double.init)
    }

    static func integral(_ value: Double?) -> Int? {
        guard let value, value.isFinite, value == value.rounded() else { return nil }
        return Int(exactly: value)
    }

    static func requiredText(_ parameters: [String: Any], key: String) throws -> String {
        guard let value = parameters[key] else {
            throw NetworkDiagnosticsParameterError("\(key) is required")
        }
        guard let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NetworkDiagnosticsParameterError("\(key) must be a non-empty string, received \(describe(value))")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func address(_ parameters: [String: Any], key: String) throws -> InternetAddress {
        let text = try requiredText(parameters, key: key)

        guard let address = InternetAddress(literal: text) else {
            throw NetworkDiagnosticsParameterError(
                "\(key) must be an IPv4 or IPv6 address literal, received \"\(text)\""
            )
        }
        return address
    }

    static func url(_ parameters: [String: Any], key: String) throws -> URL {
        let text = try requiredText(parameters, key: key)

        return try url(text, key: key)
    }

    static func url(_ text: String, key: String) throws -> URL {
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              allowedSchemes.contains(scheme),
              let host = url.host,
              !host.isEmpty else {
            throw NetworkDiagnosticsParameterError(
                "\(key) must be an http or https URL with a host, received \"\(text)\""
            )
        }
        return url
    }

    static func method(_ parameters: [String: Any], key: String) throws -> HTTPProbeMethod {
        guard let value = parameters[key] else { return .head }
        guard let text = value as? String, let method = HTTPProbeMethod(rawValue: text.uppercased()) else {
            throw NetworkDiagnosticsParameterError("\(key) must be HEAD or GET, received \(describe(value))")
        }
        return method
    }

    static func describe(_ value: Any) -> String {
        if let text = value as? String {
            return "\"\(text)\""
        }
        return String(describing: value)
    }
}
