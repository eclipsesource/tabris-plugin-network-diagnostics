import Foundation
@testable import NetworkDiagnostics

/// In-memory service doubles; each returns a canned result so orchestration
/// can be tested without touching sockets.
struct StubInterfaceEnumerator: InterfaceEnumerating {
    var result: Result<[NetworkInterfaceInfo], ServiceFailure>

    func enumerateInterfaces() throws -> [NetworkInterfaceInfo] {
        try result.get()
    }
}

struct StubGatewayDiscoverer: GatewayDiscovering {
    var result: Result<[DiscoveredGateway], ServiceFailure>

    func discoverGateways(timeoutSeconds: TimeInterval) async throws -> [DiscoveredGateway] {
        try result.get()
    }
}

struct StubDNSServerReader: DNSServerReading {
    var result: Result<[InternetAddress], ServiceFailure>

    func readDNSServers() throws -> [InternetAddress] {
        try result.get()
    }
}

struct StubDNSQuerier: DNSQuerying {
    var outcome: DNSQueryOutcome

    func query(domain: String, server: InternetAddress, timeoutSeconds: TimeInterval) async -> DNSQueryOutcome {
        outcome
    }
}

struct StubHostResolver: HostResolving {
    var addressesByHost: [String: [InternetAddress]]

    func resolve(host: String) async throws -> [InternetAddress] {
        guard let addresses = addressesByHost[host] else {
            throw ServiceFailure(component: "StubHostResolver", operation: "resolve(\(host))", reason: "NXDOMAIN")
        }
        return addresses
    }
}

struct StubPinger: Pinging {
    var outcome: PingOutcome
    var hangForever = false

    func ping(address: InternetAddress, packetCount: Int, timeoutPerPacketSeconds: TimeInterval) async -> PingOutcome {
        if hangForever {
            try? await Task.sleep(for: .seconds(600))
            return .failed(reason: "stub pinger was cancelled")
        }
        return outcome
    }
}

struct StubHTTPProber: HTTPProbing {
    var outcome: HttpOutcome

    func probe(url: URL, method: HTTPProbeMethod, timeoutSeconds: TimeInterval) async -> HttpOutcome {
        outcome
    }
}

extension ServiceFailure {
    static func stub(_ reason: String) -> ServiceFailure {
        ServiceFailure(component: "Stub", operation: "operation", reason: reason)
    }
}
