// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LiveBox",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .library(
            name: "OpenBoxCore",
            targets: ["OpenBoxCore"]
        ),
    ],
    targets: [
        .target(
            name: "OpenBoxCore",
            path: "Sources/OpenBoxCore"
        ),
        .executableTarget(
            name: "LiveBox",
            path: "Sources/LiveBox"
        ),
        .executableTarget(
            name: "OpenBox",
            dependencies: ["OpenBoxCore"],
            path: "Sources/OpenBox"
        ),
        .testTarget(
            name: "OpenBoxCoreTests",
            dependencies: ["OpenBoxCore"],
            path: "Tests/OpenBoxCoreTests"
        ),
    ]
)
