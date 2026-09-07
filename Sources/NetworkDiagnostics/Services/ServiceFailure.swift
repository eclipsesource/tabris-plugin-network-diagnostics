struct ServiceFailure: Error, CustomStringConvertible {
    let component: String
    let operation: String
    let reason: String

    var description: String {
        "\(component).\(operation) failed: \(reason)"
    }
}
