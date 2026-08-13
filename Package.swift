// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenBoxCostCore",
    products: [
        .library(name: "OpenBoxCostCore", targets: ["OpenBoxCostCore"]),
    ],
    targets: [
        .target(name: "OpenBoxCostCore"),
        .testTarget(name: "OpenBoxCostCoreTests", dependencies: ["OpenBoxCostCore"]),
    ]
)
