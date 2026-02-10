// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Vibeshed",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.0"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.58.0"),
        .package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.55.0"),
    ],
    targets: [
        .executableTarget(
            name: "Vibeshed",
            dependencies: ["Yams"],
            path: "Vibeshed",
            exclude: ["Info.plist", "Vibeshed.entitlements"],
            plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")]
        ),
    ]
)
