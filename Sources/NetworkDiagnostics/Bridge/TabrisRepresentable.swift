import Foundation

protocol TabrisRepresentable {
    var tabrisObject: [String: Any] { get }
}

func tabrisOptional<Value>(_ value: Value?) -> Any {
    if let value { value } else { NSNull() }
}

extension Array where Element: TabrisRepresentable {
    var tabrisObjects: [[String: Any]] {
        map(\.tabrisObject)
    }
}
