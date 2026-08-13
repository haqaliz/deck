// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClipBoxCore",
    products: [
        .library(name: "ClipBoxCore", targets: ["ClipBoxCore"])
    ],
    targets: [
        .target(name: "ClipBoxCore"),
        .testTarget(name: "ClipBoxCoreTests", dependencies: ["ClipBoxCore"])
    ]
)
