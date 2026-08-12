// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SettingsCore",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SettingsCore"),
        .testTarget(name: "SettingsCoreTests", dependencies: ["SettingsCore"]),
    ]
)
