import Foundation

func withHardTimeout<Output: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async -> Output
) async -> Output? {
    await withTaskGroup(of: Output?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(for: .seconds(seconds))
            return nil
        }
        let first = await group.next().flatMap { $0 }

        group.cancelAll()
        return first
    }
}

extension Duration {
    var milliseconds: Double {
        Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
    }
}
