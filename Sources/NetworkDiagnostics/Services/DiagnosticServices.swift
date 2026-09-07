struct DiagnosticServices: Sendable {
    let interfaces: any InterfaceEnumerating
    let gateways: any GatewayDiscovering
    let dnsServers: any DNSServerReading
    let hostResolver: any HostResolving
    let dnsQuerier: any DNSQuerying
    let pinger: any Pinging
    let httpProber: any HTTPProbing

    static var live: Self {
        Self(
            interfaces: GetifaddrsInterfaceEnumerator(),
            gateways: PathMonitorGatewayDiscoverer(),
            dnsServers: ResolvDNSServerReader(),
            hostResolver: GetaddrinfoHostResolver(),
            dnsQuerier: UDPDNSQuerier(),
            pinger: ICMPPinger(),
            httpProber: URLSessionHTTPProber()
        )
    }
}
