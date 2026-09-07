import Foundation
import XCTest

/// Shared assertion for the `[String: Any]` shapes that cross the bridge: the
/// object must be serialisable by `JSONSerialization` (the bridge accepts only
/// plain string/number/bool/null/array/dictionary values) and must equal the
/// expected shape once both are written with sorted keys — which is exactly how
/// a JavaScript consumer would see them.
extension XCTestCase {
    func assertTabrisObject(
        _ actual: [String: Any],
        equals expected: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            JSONSerialization.isValidJSONObject(actual),
            "object contains values the bridge cannot encode: \(actual)",
            file: file,
            line: line
        )
        XCTAssertEqual(canonicalJSON(actual), canonicalJSON(expected), file: file, line: line)
    }

    private func canonicalJSON(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let json = String(bytes: data, encoding: .utf8) else {
            return "<not serialisable: \(object)>"
        }
        return json
    }
}
