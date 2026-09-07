enum NetworkDiagnosticsErrorCode: String {
    case invalidParameter
    case unavailable
    case alreadyRunning
    case cancelled
    case disposed
}

struct NetworkDiagnosticsError: Error, Equatable {
    let code: NetworkDiagnosticsErrorCode
    let message: String

    init(code: NetworkDiagnosticsErrorCode, message: String) {
        self.code = code
        self.message = message
    }

    init(_ error: any Error) {
        switch error {
        case let error as Self:
            self = error
        case let error as NetworkDiagnosticsParameterError:
            self.init(code: .invalidParameter, message: error.errorDescription ?? "invalid parameter")
        case let failure as ServiceFailure:
            self.init(code: .unavailable, message: failure.description)
        case is CancellationError:
            self.init(code: .cancelled, message: "cancelled")
        default:
            self.init(code: .unavailable, message: String(describing: error))
        }
    }
}

extension NetworkDiagnosticsError: NetworkDiagnosticsRepresentable {
    var tabrisObject: [String: Any] {
        ["code": code.rawValue, "message": message]
    }
}
