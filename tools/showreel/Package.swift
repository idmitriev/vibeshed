// swift-tools-version: 6.0

import PackageDescription

// Screenshot and video tooling for the website and social media. One binary
// plays both roles: on the host it drives a UTM macOS VM over SSH and
// post-processes recordings with ffmpeg; inside the VM, started by
// ShowreelAgent.app, it sets up the scene, plays the actions and records.
let package = Package(
    name: "Showreel",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.0"),
    ],
    targets: [
        .target(
            name: "ShowreelCore",
            dependencies: ["Yams"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "showreel",
            dependencies: ["ShowreelCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // ShowreelAgent.app's executable, kept apart so it rarely changes.
        .executableTarget(
            name: "ShowreelAgentLauncher",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ShowreelCoreTests",
            dependencies: ["ShowreelCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
