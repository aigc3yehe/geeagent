// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "GeeAgentMac",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "GeeAgentMac", targets: ["GeeAgentMac"])
    ],
    targets: [
        .executableTarget(
            name: "GeeAgentMac",
            path: ".",
            exclude: [
                ".codex",
                ".build",
                ".swift-build",
                "dist",
                "script",
                "Tests"
            ],
            sources: [
                "Sources/GearKit",
                "Sources/GearHost",
                "Sources/GeeAgentMac"
            ],
            resources: [
                .copy("Gears"),
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "GeeAgentMacTests",
            dependencies: ["GeeAgentMac"],
            path: "Tests/GeeAgentMacTests"
        )
    ]
)
