// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LiveBox",
    platforms: [
        .macOS("15.0")
    ],
    targets: [
        .executableTarget(
            name: "LiveBox",
            path: "Sources/LiveBox"
        ),
        .executableTarget(
            name: "OpenBox",
            path: "Sources/OpenBox"
        ),
    ]
)
