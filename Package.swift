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
        .library(
            name: "GitBoxCore",
            targets: ["GitBoxCore"]
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
        .target(
            name: "GitBoxCore",
            path: "Sources/GitBoxCore"
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
            name: "BatBox",
            dependencies: ["BatBoxCore"],
            path: "Sources/BatBox"
        ),
        .executableTarget(
            name: "OpenBox",
            dependencies: ["OpenBoxCore"],
            path: "Sources/OpenBox"
        ),
        .executableTarget(
            name: "GitBox",
            dependencies: ["GitBoxCore"],
            path: "Sources/GitBox"
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
        .testTarget(
            name: "GitBoxCoreTests",
            dependencies: ["GitBoxCore"],
            path: "Tests/GitBoxCoreTests"
        ),
    ]
)
