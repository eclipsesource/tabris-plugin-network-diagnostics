import Foundation

public enum HTTPProbeMethod: String, Codable, Sendable {
    case head = "HEAD"
    case get = "GET"
}

public struct DiagnosticConfiguration: Sendable {
    public var pingHosts: [String]
    public var httpHosts: [URL]
    public var dnsTestDomains: [String]
    public var timeoutPerHostSeconds: TimeInterval
    public var pingPacketCount: Int
    public var httpMethod: HTTPProbeMethod

    public init(
        pingHosts: [String],
        httpHosts: [URL],
        dnsTestDomains: [String],
        timeoutPerHostSeconds: TimeInterval = 3.0,
        pingPacketCount: Int = 3,
        httpMethod: HTTPProbeMethod = .head
    ) {
        self.pingHosts = pingHosts
        self.httpHosts = httpHosts
        self.dnsTestDomains = dnsTestDomains
        self.timeoutPerHostSeconds = timeoutPerHostSeconds
        self.pingPacketCount = pingPacketCount
        self.httpMethod = httpMethod
    }
}
