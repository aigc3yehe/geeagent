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
            path: "Sources/GeeAgentMac",
            resources: [
                .copy("gears")
            ]
        ),
        .testTarget(
            name: "GeeAgentMacTests",
            dependencies: ["GeeAgentMac"],
            path: "Tests/GeeAgentMacTests"
        )
    ]
)
