// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenBoxToolsCore",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "OpenBoxToolsCore"),
        .testTarget(name: "OpenBoxToolsCoreTests", dependencies: ["OpenBoxToolsCore"]),
    ]
)
