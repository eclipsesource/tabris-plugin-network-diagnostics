// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NetworkDiagnostics",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "NetworkDiagnostics", targets: ["NetworkDiagnostics"]),
    ],
    targets: [
        .target(
            name: "CResolv",
            linkerSettings: [.linkedLibrary("resolv")]
        ),
        .target(
            name: "NetworkDiagnostics",
            dependencies: ["CResolv"]
        ),
        .testTarget(
            name: "NetworkDiagnosticsTests",
            dependencies: ["NetworkDiagnostics"]
        ),
        .testTarget(
            name: "NetworkDiagnosticsIntegrationTests",
            dependencies: ["NetworkDiagnostics"]
        ),
    ]
)
