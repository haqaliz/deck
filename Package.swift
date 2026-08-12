// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LiveBoxCore",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LiveBoxCore"),
        .testTarget(name: "LiveBoxCoreTests", dependencies: ["LiveBoxCore"]),
    ]
)
