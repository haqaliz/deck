// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ShipBoxCore",
    products: [
        .library(name: "ShipBoxCore", targets: ["ShipBoxCore"])
    ],
    targets: [
        .target(name: "ShipBoxCore"),
        .testTarget(name: "ShipBoxCoreTests", dependencies: ["ShipBoxCore"])
    ]
)
