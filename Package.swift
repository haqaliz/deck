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
        .library(
            name: "NetBoxCore",
            targets: ["NetBoxCore"]
        ),
        .library(
            name: "BatBoxCore",
            targets: ["BatBoxCore"]
        ),
    ],
    targets: [
        .target(
            name: "OpenBoxCore",
            path: "Sources/OpenBoxCore"
        ),
        .target(
            name: "NetBoxCore",
            path: "Sources/NetBoxCore"
        ),
        .target(
            name: "BatBoxCore",
            path: "Sources/BatBoxCore"
        ),
        .executableTarget(
            name: "LiveBox",
            path: "Sources/LiveBox"
        ),
        .executableTarget(
            name: "NetBox",
            dependencies: ["NetBoxCore"],
            path: "Sources/NetBox"
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
        .testTarget(
            name: "NetBoxCoreTests",
            dependencies: ["NetBoxCore"],
            path: "Tests/NetBoxCoreTests"
        ),
        .testTarget(
            name: "BatBoxCoreTests",
            dependencies: ["BatBoxCore"],
            path: "Tests/BatBoxCoreTests"
        ),
    ]
)
