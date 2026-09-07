import os

enum NetworkDiagnosticsLog {
    private static let subsystem = "NetworkDiagnostics"

    static let interfaces = Logger(subsystem: subsystem, category: "interfaces")
    static let gateways = Logger(subsystem: subsystem, category: "gateways")
    static let dns = Logger(subsystem: subsystem, category: "dns")
    static let ping = Logger(subsystem: subsystem, category: "ping")
    static let http = Logger(subsystem: subsystem, category: "http")
    static let diagnostics = Logger(subsystem: subsystem, category: "diagnostics")
}
