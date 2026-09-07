enum TabrisErrorCode: String {
    case invalidParameter
    case unavailable
    case alreadyRunning
    case cancelled
    case disposed
}

struct TabrisError: Error, Equatable {
    let code: TabrisErrorCode
    let message: String

    init(code: TabrisErrorCode, message: String) {
        self.code = code
        self.message = message
    }

    init(_ error: any Error) {
        switch error {
        case let error as Self:
            self = error
        case let failure as ServiceFailure:
            self.init(code: .unavailable, message: failure.description)
        case is CancellationError:
            self.init(code: .cancelled, message: "cancelled")
        default:
            self.init(code: .unavailable, message: String(describing: error))
        }
    }
}

extension TabrisError: TabrisRepresentable {
    var tabrisObject: [String: Any] {
        ["code": code.rawValue, "message": message]
    }
}
