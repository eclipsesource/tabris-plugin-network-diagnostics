import Foundation
import os

func withHardTimeout<Output: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async -> Output
) async -> Output? {
    let operationTask = Task { await operation() }
    let timeoutTask = Task { try? await Task.sleep(for: .seconds(seconds)) }
    let settled = OSAllocatedUnfairLock(initialState: false)

    return await withTaskCancellationHandler {
        await withCheckedContinuation { (continuation: CheckedContinuation<Output?, Never>) in
            Task {
                let output = await operationTask.value

                if settled.claim() {
                    timeoutTask.cancel()
                    continuation.resume(returning: output)
                }
            }
            Task {
                await timeoutTask.value
                if settled.claim() {
                    operationTask.cancel()
                    continuation.resume(returning: nil)
                }
            }
        }
    } onCancel: {
        operationTask.cancel()
        timeoutTask.cancel()
    }
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
