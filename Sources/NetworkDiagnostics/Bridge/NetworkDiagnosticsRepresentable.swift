import Foundation

protocol NetworkDiagnosticsRepresentable {
    var tabrisObject: [String: Any] { get }
}

func networkDiagnosticsOptional<Value>(_ value: Value?) -> Any {
    if let value { value } else { NSNull() }
}

extension Array where Element: NetworkDiagnosticsRepresentable {
    var tabrisObjects: [[String: Any]] {
        map(\.tabrisObject)
    }
}
