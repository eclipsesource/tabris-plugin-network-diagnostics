import Foundation

struct HostProbes: Sendable {
    let services: DiagnosticServices
    let timeoutPerHostSeconds: TimeInterval

    func pingHost(_ host: String, packetCount: Int) async -> PingHostResult {
        let result = await withHardTimeout(seconds: timeoutPerHostSeconds) {
            await resolveAndPing(host, packetCount: packetCount)
        }

        return result ?? PingHostResult(host: host, resolvedAddress: nil, outcome: .failed(reason: hardTimeoutReason))
    }

    func pingWithHardTimeout(_ address: InternetAddress, packetCount: Int) async -> PingOutcome {
        let outcome = await withHardTimeout(seconds: timeoutPerHostSeconds) {
            await ping(address, packetCount: packetCount)
        }

        return outcome ?? .failed(reason: hardTimeoutReason)
    }

    func probeHTTP(_ url: URL, method: HTTPProbeMethod) async -> HttpHostResult {
        let outcome = await withHardTimeout(seconds: timeoutPerHostSeconds) {
            await services.httpProber.probe(url: url, method: method, timeoutSeconds: timeoutPerHostSeconds)
        }

        return HttpHostResult(url: url, outcome: outcome ?? .failure(.timedOut))
    }

    func queryDNS(domain: String, server: InternetAddress) async -> DNSQueryResult {
        let outcome = await services.dnsQuerier.query(
            domain: domain,
            server: server,
            timeoutSeconds: timeoutPerHostSeconds
        )

        return DNSQueryResult(domain: domain, outcome: outcome)
    }

    private func resolveAndPing(_ host: String, packetCount: Int) async -> PingHostResult {
        do {
            let addresses = try await services.hostResolver.resolve(host: host)

            guard let address = addresses.first else {
                return PingHostResult(
                    host: host,
                    resolvedAddress: nil,
                    outcome: .resolutionFailed(reason: "no addresses")
                )
            }
            return PingHostResult(
                host: host,
                resolvedAddress: address.description,
                outcome: await ping(address, packetCount: packetCount)
            )
        } catch {
            NetworkDiagnosticsLog.ping.error("Host resolution failed for \(host): \(error)")
            return PingHostResult(
                host: host,
                resolvedAddress: nil,
                outcome: .resolutionFailed(reason: String(describing: error))
            )
        }
    }

    private func ping(_ address: InternetAddress, packetCount: Int) async -> PingOutcome {
        await services.pinger.ping(
            address: address,
            packetCount: packetCount,
            timeoutPerPacketSeconds: timeoutPerHostSeconds / Double(max(packetCount, 1))
        )
    }

    private var hardTimeoutReason: String {
        "no result within the \(timeoutPerHostSeconds)s hard timeout"
    }
}
