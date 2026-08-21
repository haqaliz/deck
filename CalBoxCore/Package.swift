// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "CalBoxCore",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CalBoxCore"),
        .testTarget(name: "CalBoxCoreTests", dependencies: ["CalBoxCore"]),
    ]
)
