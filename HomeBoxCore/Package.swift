// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "HomeBoxCore",
    products: [
        .library(name: "HomeBoxCore", targets: ["HomeBoxCore"])
    ],
    targets: [
        .target(name: "HomeBoxCore"),
        .testTarget(
            name: "HomeBoxCoreTests",
            dependencies: ["HomeBoxCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
