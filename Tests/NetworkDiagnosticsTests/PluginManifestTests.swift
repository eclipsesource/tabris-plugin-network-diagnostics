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

    /// The plugin configures nothing in the host application, so the three entries an app
    /// must declare itself live in exactly two places that have to agree: the README block
    /// a reader copies from, and the example app that proves the block works. Rationale:
    /// docs/decisions/2026-09-08T1200Z-host-app-owns-required-configuration.md
    func testTheHostAppAndNotThePluginDeclaresTheRequiredConfiguration() throws {
        let manifest = try read("plugin.xml")
        let exampleConfigurations = try [
            "example/cordova/config.xml", "example_typescript/cordova/config.xml",
        ].map { ($0, try read($0)) }
        let readme = try read("README.md")

        XCTAssertTrue(
            matches(#"<config-file target="(config\.xml|\*-Info\.plist)""#, in: manifest).isEmpty,
            "plugin.xml must not configure the host application; README.md and the example declare it"
        )
        XCTAssertFalse(
            manifest.contains("LOCAL_NETWORK_USAGE_DESCRIPTION"),
            "the usage description variable went with the Info.plist munge that used it"
        )

        for entry in [
            #"<preference name="deployment-target" value="16.0" />"#,
            #"<preference name="SwiftVersion" value="5.0" />"#,
            #"<edit-config target="NSLocalNetworkUsageDescription" file="*-Info.plist" mode="merge">"#,
        ] {
            for (path, configuration) in exampleConfigurations {
                XCTAssertTrue(configuration.contains(entry), "\(path) is missing \(entry)")
            }
            XCTAssertTrue(readme.contains(entry), "README.md does not document \(entry)")
        }
    }

    /// The type declarations are hand-written next to the JavaScript module, and nothing
    /// compiles the two against each other: a method or event added to `www/` without its
    /// declaration is invisible to a TypeScript app, which is exactly the situation the
    /// declarations exist to prevent. Rationale:
    /// docs/decisions/2026-09-16T1530Z-typescript-declarations-and-dual-install.md
    func testTypeDeclarationsCoverEveryPublicMethodAndEvent() throws {
        let javaScript = try read("www/NetworkDiagnostics.js")
        let declarations = try read("types/index.d.ts")
        let publicMethods = matches(#"\n  ([a-z]\w+)\([^)]*\)\s*\{"#, in: javaScript)
        let events = matches(#"\n  (\w+): \{native: true\}"#, in: javaScript)

        XCTAssertEqual(
            matches(#""types":\s*"([^"]+)""#, in: try read("package.json")),
            ["./types/index.d.ts"]
        )
        XCTAssertFalse(publicMethods.isEmpty)
        XCTAssertFalse(events.isEmpty)
        for method in publicMethods {
            XCTAssertTrue(
                declarations.contains("\n      \(method)("),
                "types/index.d.ts does not declare \(method)()"
            )
        }
        for event in events {
            XCTAssertTrue(
                declarations.contains("\n      \(event): "),
                "types/index.d.ts does not declare the \(event) event"
            )
        }
    }

    /// Tabris ships buffered JavaScript-to-native operations only on `tabris.flush()`, and
    /// a promise settlement arrives through a `JSFunctionValue` callback, which — unlike the
    /// event path — does not flush. Without this every widget write the continuation makes
    /// sits in the buffer and the interface freezes on a result that already arrived. The
    /// flush has to be scheduled on a *timer*: `resolve()` only queues the continuation as a
    /// microtask, so flushing synchronously ships nothing. Rationale, and the measurement
    /// that ruled out the synchronous variants:
    /// docs/decisions/2026-09-08T1130Z-flush-after-promise-settlement.md
    func testEverySettlementSchedulesAFlushOnATimer() throws {
        let javaScript = try read("www/NetworkDiagnostics.js")

        XCTAssertEqual(
            matches(
                #"function (flushAfterContinuations)\(\)\s*\{\s*setTimeout\([^;]*tabris\.flush\(\)"#,
                in: javaScript
            ),
            ["flushAfterContinuations"],
            "the flush must be scheduled on a timer; a synchronous one runs before the continuation"
        )
        XCTAssertEqual(
            matches(#"\s(flushAfterContinuations)\(\);"#, in: javaScript),
            ["flushAfterContinuations"],
            "every settled native call must schedule the flush exactly once"
        )
    }

    func testReadmeDocumentsEveryPublicJavaScriptMethod() throws {
        let readme = try read("README.md")
        let publicMethods = matches(#"\n  ([a-z]\w+)\([^)]*\)\s*\{"#, in: try read("www/NetworkDiagnostics.js"))
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
