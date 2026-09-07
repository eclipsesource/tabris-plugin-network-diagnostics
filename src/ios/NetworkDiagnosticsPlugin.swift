import Foundation

@objc(NetworkDiagnosticsPlugin)
public class NetworkDiagnosticsPlugin: BasicObject {
    private struct PendingCall {
        let task: Task<Void, Never>
        let call: NetworkDiagnosticsCall
    }

    private let primitives = DiagnosticPrimitives()
    private var pendingCalls: [UUID: PendingCall] = [:]
    private var generation = 0

    // swiftlint:disable:next implicitly_unwrapped_optional
    override public class func remoteObjectType() -> String! {
        "com.eclipsesource.NetworkDiagnostics"
    }

    // swiftlint:disable:next implicitly_unwrapped_optional
    required init!(objectId: String!, properties: [AnyHashable: Any]!, in context: TabrisContext!) {
        super.init(objectId: objectId, properties: properties, in: context)
        register(#selector(interfaces(properties:)), forCall: "interfaces")
        register(#selector(gateways(properties:)), forCall: "gateways")
        register(#selector(dnsServers(properties:)), forCall: "dnsServers")
        register(#selector(ping(properties:)), forCall: "ping")
        register(#selector(dnsQuery(properties:)), forCall: "dnsQuery")
        register(#selector(http(properties:)), forCall: "http")
    }

    deinit {
        pendingCalls.values.forEach { $0.task.cancel() }
    }

    @objc(interfaces:)
    public func interfaces(properties: [String: Any]) {
        guard let call = NetworkDiagnosticsCall(properties: properties, console: context.console) else { return }
        let primitives = self.primitives

        perform(call) { try primitives.enumerateInterfaces().tabrisObjects }
    }

    @objc(gateways:)
    public func gateways(properties: [String: Any]) {
        guard let call = NetworkDiagnosticsCall(properties: properties, console: context.console),
              let request = request({ try NetworkDiagnosticsParameters.gateways(call.parameters) }, for: call) else {
            return
        }
        let primitives = self.primitives

        perform(call) { try await primitives.discoverGateways(timeoutSeconds: request.timeoutSeconds).tabrisObjects }
    }

    @objc(dnsServers:)
    public func dnsServers(properties: [String: Any]) {
        guard let call = NetworkDiagnosticsCall(properties: properties, console: context.console) else { return }
        let primitives = self.primitives

        perform(call) { try primitives.readDNSServers().map(\.description) }
    }

    @objc(ping:)
    public func ping(properties: [String: Any]) {
        guard let call = NetworkDiagnosticsCall(properties: properties, console: context.console),
              let request = request({ try NetworkDiagnosticsParameters.ping(call.parameters) }, for: call) else {
            return
        }
        let primitives = self.primitives

        perform(call) {
            await primitives.ping(
                host: request.host,
                packetCount: request.packetCount,
                timeoutSeconds: request.timeoutSeconds
            ).tabrisObject
        }
    }

    @objc(dnsQuery:)
    public func dnsQuery(properties: [String: Any]) {
        guard let call = NetworkDiagnosticsCall(properties: properties, console: context.console),
              let request = request({ try NetworkDiagnosticsParameters.dnsQuery(call.parameters) }, for: call) else {
            return
        }
        let primitives = self.primitives

        perform(call) {
            let result = await primitives.query(
                domain: request.domain,
                server: request.server,
                timeoutSeconds: request.timeoutSeconds
            )

            return result.tabrisObject(server: request.server)
        }
    }

    @objc(http:)
    public func http(properties: [String: Any]) {
        guard let call = NetworkDiagnosticsCall(properties: properties, console: context.console),
              let request = request({ try NetworkDiagnosticsParameters.http(call.parameters) }, for: call) else {
            return
        }
        let primitives = self.primitives

        perform(call) {
            await primitives.probe(
                url: request.url,
                method: request.method,
                timeoutSeconds: request.timeoutSeconds
            ).tabrisObject
        }
    }

    override public func destroy() {
        generation += 1
        let calls = pendingCalls

        pendingCalls.removeAll()
        for pending in calls.values {
            pending.task.cancel()
            pending.call.reject(
                NetworkDiagnosticsError(code: .disposed, message: "NetworkDiagnostics object was disposed")
            )
        }
        logDebug("destroyed, \(calls.count) pending call(s) rejected")
        super.destroy()
    }

    private func request<Request>(
        _ parse: () throws -> Request,
        for call: NetworkDiagnosticsCall
    ) -> Request? {
        do {
            return try parse()
        } catch {
            call.reject(NetworkDiagnosticsError(error))
            return nil
        }
    }

    private func perform(_ call: NetworkDiagnosticsCall, _ work: @escaping @Sendable () async throws -> Any) {
        let identifier = UUID()
        let generation = self.generation
        let task = Task {
            let outcome: Result<Any, any Error>

            do {
                outcome = .success(try await work())
            } catch {
                outcome = .failure(error)
            }
            await MainActor.run { [weak self] in
                self?.deliver(outcome, for: identifier, generation: generation)
            }
        }

        pendingCalls[identifier] = PendingCall(task: task, call: call)
    }

    private func deliver(_ outcome: Result<Any, any Error>, for identifier: UUID, generation: Int) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard self.generation == generation,
              !isDisposed,
              let pending = pendingCalls.removeValue(forKey: identifier) else {
            return
        }
        switch outcome {
        case let .success(value): pending.call.resolve(value)
        case let .failure(error): pending.call.reject(NetworkDiagnosticsError(error))
        }
    }

    private func logDebug(_ message: String) {
        display(message, type: 1)
    }

    private func display(_ message: String, type: UInt) {
        context.console?.display(
            LogEntry(message: "[NetworkDiagnosticsPlugin] \(message)", andType: ConsoleEntryType(rawValue: type))
        )
    }
}
