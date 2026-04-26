// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "GeeAgentMac",
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
                ".swift-build",
                "dist",
                "Resources",
                "script",
                "Tests"
            ],
            sources: [
                "Sources/GearKit",
                "Sources/GearHost",
                "Sources/GeeAgentMac"
            ],
            resources: [
                .copy("Gears")
            ]
        ),
        .testTarget(
            name: "GeeAgentMacTests",
            dependencies: ["GeeAgentMac"],
            path: "Tests/GeeAgentMacTests"
        )
    ]
)
