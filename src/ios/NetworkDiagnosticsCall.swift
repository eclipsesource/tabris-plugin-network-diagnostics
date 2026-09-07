import Foundation

struct NetworkDiagnosticsCall {
    let parameters: [String: Any]
    private let completion: JSFunctionValue

    init?(properties: [String: Any], console: (any Console)?) {
        guard let completion = properties["completion"] as? JSFunctionValue else {
            console?.display(
                LogEntry(
                    message: "[NetworkDiagnosticsPlugin] completion callback is missing in the call parameters",
                    andType: ConsoleEntryType(rawValue: 5)
                )
            )
            return nil
        }
        self.completion = completion
        parameters = properties["parameters"] as? [String: Any] ?? [:]
    }

    func resolve(_ value: Any?) {
        completion.call(withParameters: [NSNull(), value ?? NSNull()])
    }

    func reject(_ error: NetworkDiagnosticsError) {
        completion.call(withParameters: [error.tabrisObject])
    }
}
