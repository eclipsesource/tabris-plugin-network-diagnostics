import Foundation

@objc(NetworkDiagnosticsPlugin)
public class NetworkDiagnosticsPlugin: BasicObject {
    private struct PendingCall {
        let task: Task<Void, Never>
        let call: TabrisCall
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
    }

    deinit {
        pendingCalls.values.forEach { $0.task.cancel() }
    }

    @objc(interfaces:)
    public func interfaces(properties: [String: Any]) {
        guard let call = TabrisCall(properties: properties, console: context.console) else { return }
        let primitives = self.primitives

        perform(call) { try primitives.enumerateInterfaces().tabrisObjects }
    }

    override public func destroy() {
        generation += 1
        let calls = pendingCalls

        pendingCalls.removeAll()
        for pending in calls.values {
            pending.task.cancel()
            pending.call.reject(TabrisError(code: .disposed, message: "NetworkDiagnostics object was disposed"))
        }
        logDebug("destroyed, \(calls.count) pending call(s) rejected")
        super.destroy()
    }

    private func perform(_ call: TabrisCall, _ work: @escaping @Sendable () async throws -> Any) {
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
                self?.deliver(outcome, for: identifier, generation: generation, to: call)
            }
        }

        pendingCalls[identifier] = PendingCall(task: task, call: call)
    }

    private func deliver(
        _ outcome: Result<Any, any Error>,
        for identifier: UUID,
        generation: Int,
        to call: TabrisCall
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard self.generation == generation, !isDisposed, pendingCalls.removeValue(forKey: identifier) != nil else {
            return
        }
        switch outcome {
        case let .success(value): call.resolve(value)
        case let .failure(error): call.reject(TabrisError(error))
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
