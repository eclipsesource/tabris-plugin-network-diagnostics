import Foundation
import XCTest

/// `plugin.xml` alone decides which files Cordova compiles into a Tabris app, and
/// the Tabris runtime binds the native class by three strings that live in three
/// different files. None of those mistakes produces a compile error, so these
/// tests make them fail here instead.
final class PluginManifestTests: XCTestCase {
    private let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    func testManifestListsExactlyTheLibraryAndBridgeSourceFiles() throws {
        let manifest = try read("plugin.xml")
        let listed = matches(#"<(?:source|header)-file src="([^"]+)""#, in: manifest)
        let onDisk = try sourceFiles(under: "Sources") + sourceFiles(under: "src/ios")

        XCTAssertEqual(listed.sorted(), onDisk.sorted())
    }

    func testListedBasenamesAreUnique() throws {
        let manifest = try read("plugin.xml")
        let basenames = matches(#"<(?:source|header)-file src="([^"]+)""#, in: manifest)
            .map { URL(fileURLWithPath: $0).lastPathComponent }
        let duplicates = Dictionary(grouping: basenames, by: { $0 }).filter { $0.value.count > 1 }.keys

        XCTAssertTrue(duplicates.isEmpty, "Cordova flattens plugin files by basename; duplicates: \(duplicates)")
    }

    func testBridgingHeaderHasAPluginSpecificName() throws {
        let manifest = try read("plugin.xml")
        let bridgingHeaders = matches(#"<header-file src="([^"]+)" type="BridgingHeader""#, in: manifest)

        XCTAssertEqual(bridgingHeaders, ["src/ios/NetworkDiagnostics-BridgingHeader.h"])
        XCTAssertTrue(try read("src/ios/NetworkDiagnostics-BridgingHeader.h").contains(#"#import "CResolv.h""#))
    }

    func testRegisteredClassNameMatchesTheSwiftClass() throws {
        let manifest = try read("plugin.xml")
        let registered = matches(
            #"TabrisPlugins\.plist"[^>]*>\s*<array>\s*<string>([^<]+)</string>"#,
            in: manifest
        )
        let declared = matches(
            #"@objc\s*\(\s*(\w+)\s*\)\s*(?:public\s+|final\s+|open\s+)*class\s+NetworkDiagnosticsPlugin\b"#,
            in: try read("src/ios/NetworkDiagnosticsPlugin.swift")
        )

        XCTAssertEqual(registered, ["NetworkDiagnosticsPlugin"])
        XCTAssertEqual(declared, ["NetworkDiagnosticsPlugin"])
    }

    func testNativeTypeMatchesBetweenSwiftAndJavaScript() throws {
        let swiftType = matches(
            #"remoteObjectType\(\)[^{]*\{\s*"([^"]+)""#,
            in: try read("src/ios/NetworkDiagnosticsPlugin.swift")
        )
        let javaScriptType = matches(
            #"get _nativeType\(\)\s*\{\s*return '([^']+)'"#,
            in: try read("www/NetworkDiagnostics.js")
        )

        XCTAssertEqual(swiftType, ["com.eclipsesource.NetworkDiagnostics"])
        XCTAssertEqual(javaScriptType, swiftType)
    }

    func testEveryRegisteredCallHasAJavaScriptMethod() throws {
        let registeredCalls = matches(#"forCall: "(\w+)""#, in: try read("src/ios/NetworkDiagnosticsPlugin.swift"))
        let javaScriptCalls = matches(#"_promiseCall\('(\w+)'"#, in: try read("www/NetworkDiagnostics.js"))

        XCTAssertFalse(registeredCalls.isEmpty)
        XCTAssertEqual(registeredCalls.sorted(), javaScriptCalls.sorted())
    }

    func testReadmeDocumentsEveryPublicJavaScriptMethod() throws {
        let readme = try read("README.md")
        let publicMethods = matches(#"\n  ([a-z]\w+)\("#, in: try read("www/NetworkDiagnostics.js"))
            .filter { !$0.hasPrefix("_") }

        XCTAssertFalse(publicMethods.isEmpty)
        for method in publicMethods {
            XCTAssertTrue(
                readme.contains("diagnostics.\(method)("),
                "README.md does not document diagnostics.\(method)()"
            )
        }
    }

    private func read(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func sourceFiles(under directory: String) throws -> [String] {
        let root = repositoryRoot.appendingPathComponent(directory)
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        let extensions: Set<String> = ["swift", "c", "h"]

        return enumerator.compactMap { element in
            guard let url = element as? URL, extensions.contains(url.pathExtension) else { return nil }
            return directory + "/" + url.path.dropFirst(root.path.count + 1)
        }
    }

    private func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            XCTFail("invalid pattern \(pattern)")
            return []
        }
        let range = NSRange(text.startIndex..., in: text)

        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }
}
