public struct DiagnosticPrimitives: Sendable {
    private let services: DiagnosticServices

    public init() {
        self.init(services: .live)
    }

    init(services: DiagnosticServices) {
        self.services = services
    }

    public func enumerateInterfaces() throws -> [NetworkInterfaceInfo] {
        try services.interfaces.enumerateInterfaces()
    }
}
