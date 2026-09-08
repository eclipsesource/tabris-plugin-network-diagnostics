import Foundation
import os

func withHardTimeout<Output: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async -> Output
) async -> Output? {
    let settled = OSAllocatedUnfairLock(initialState: false)
    let tasks = OSAllocatedUnfairLock<TimeoutTasks>(initialState: TimeoutTasks())

    return await withTaskCancellationHandler {
        await withCheckedContinuation { (continuation: CheckedContinuation<Output?, Never>) in
            let operationTask = Task {
                let output = await operation()

                if settled.claim() {
                    tasks.withLock { $0.timeout?.cancel() }
                    continuation.resume(returning: output)
                }
            }
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(seconds))
                if settled.claim() {
                    tasks.withLock { $0.operation?.cancel() }
                    continuation.resume(returning: nil)
                }
            }

            tasks.withLock { $0 = TimeoutTasks(operation: operationTask, timeout: timeoutTask) }
            if Task.isCancelled || settled.withLock({ $0 }) {
                operationTask.cancel()
                timeoutTask.cancel()
            }
        }
    } onCancel: {
        let current = tasks.withLock { $0 }

        current.operation?.cancel()
        current.timeout?.cancel()
    }
}

private struct TimeoutTasks {
    var operation: Task<Void, Never>?
    var timeout: Task<Void, Never>?
}

private extension OSAllocatedUnfairLock where State == Bool {
    func claim() -> Bool {
        withLock { claimed in
            if claimed {
                return false
            }
            claimed = true
            return true
        }
    }
}

extension Duration {
    var networkDiagnosticsMilliseconds: Double {
        Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
    }
}
