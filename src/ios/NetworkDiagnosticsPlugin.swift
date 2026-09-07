import Foundation

@objc(NetworkDiagnosticsPlugin)
public class NetworkDiagnosticsPlugin: BasicObject {
    private struct PendingCall {
        let task: Task<Void, Never>
        let call: NetworkDiagnosticsCall
    }

    private let diagnostics = NetworkDiagnostics()
    private let primitives = DiagnosticPrimitives()
    private var pendingCalls: [UUID: PendingCall] = [:]
    private var generation = 0
    private var run: PendingCall?
    private var runGeneration = 0

    @objc public var stageStartedListener = false
    @objc public var stageFinishedListener = false
    @objc public var gatewayResultListener = false
    @objc public var dnsServerResultListener = false
    @objc public var pingResultListener = false
    @objc public var httpResultListener = false

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
        register(#selector(diagnose(properties:)), forCall: "diagnose")
        register(#selector(cancel(properties:)), forCall: "cancel")
    }

    deinit {
        pendingCalls.values.forEach { $0.task.cancel() }
        run?.task.cancel()
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

    @objc(diagnose:)
    public func diagnose(properties: [String: Any]) {
        guard let call = NetworkDiagnosticsCall(properties: properties, console: context.console),
              let configuration = request(
                { try NetworkDiagnosticsParameters.diagnosticConfiguration(call.parameters) },
                for: call
              ) else {
            return
        }
        guard run == nil else {
            call.reject(
                NetworkDiagnosticsError(
                    code: .alreadyRunning,
                    message: "a diagnosis is already running on this object; call cancel() or wait for it to settle"
                )
            )
            return
        }
        runGeneration += 1
        let generation = runGeneration
        let diagnostics = self.diagnostics
        let task = Task {
            var report: DiagnosticReport?

            for await event in diagnostics.diagnose(configuration) {
                if case let .completed(completed) = event {
                    report = completed
                }
                await MainActor.run { [weak self] in
                    self?.handle(event, generation: generation)
                }
            }
            await MainActor.run { [weak self] in
                self?.finishRun(report: report, generation: generation)
            }
        }

        run = PendingCall(task: task, call: call)
    }

    @objc(cancel:)
    public func cancel(properties: [String: Any]) {
        guard let call = NetworkDiagnosticsCall(properties: properties, console: context.console) else { return }

        cancelRun(rejectingWith: NetworkDiagnosticsError(code: .cancelled, message: "cancelled"))
        call.resolve(nil)
    }

    override public func destroy() {
        let disposed = NetworkDiagnosticsError(code: .disposed, message: "NetworkDiagnostics object was disposed")
        let calls = pendingCalls

        generation += 1
        pendingCalls.removeAll()
        cancelRun(rejectingWith: disposed)
        for pending in calls.values {
            pending.task.cancel()
            pending.call.reject(disposed)
        }
        logDebug("destroyed, \(calls.count) pending call(s) rejected")
        super.destroy()
    }

    private func cancelRun(rejectingWith error: NetworkDiagnosticsError) {
        guard let run else { return }

        runGeneration += 1
        self.run = nil
        run.task.cancel()
        run.call.reject(error)
        logDebug("run \(error.code.rawValue)")
    }

    private func handle(_ event: DiagnosticEvent, generation: Int) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard runGeneration == generation, !isDisposed, let tabrisEvent = event.tabrisEvent else { return }
        guard isListening(to: tabrisEvent.name) else { return }

        fireEventNamed(tabrisEvent.name, withAttributes: tabrisEvent.attributes)
    }

    private func finishRun(report: DiagnosticReport?, generation: Int) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard runGeneration == generation, !isDisposed, let run else { return }

        self.run = nil
        if let report {
            run.call.resolve(report.tabrisObject)
        } else {
            run.call.reject(NetworkDiagnosticsError(code: .cancelled, message: "the run ended without a report"))
        }
    }

    private func isListening(to eventName: String) -> Bool {
        switch eventName {
        case "stageStarted": stageStartedListener
        case "stageFinished": stageFinishedListener
        case "gatewayResult": gatewayResultListener
        case "dnsServerResult": dnsServerResultListener
        case "pingResult": pingResultListener
        case "httpResult": httpResultListener
        default: false
        }
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
