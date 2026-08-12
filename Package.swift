// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DevBoxCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DevBoxCore", targets: ["DevBoxCore"])
    ],
    targets: [
        .target(name: "DevBoxCore"),
        .testTarget(name: "DevBoxCoreTests", dependencies: ["DevBoxCore"])
    ]
)
