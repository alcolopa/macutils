// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacMonitor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacMonitor", targets: ["MacMonitor"])
    ],
    targets: [
        .executableTarget(
            name: "MacMonitor",
            path: "MacMonitor",
            exclude: ["Tests", "App/Info.plist"],
            sources: [
                "App",
                "Core",
                "Driver",
                "UI"
            ],
            resources: [
                .copy("Resources/AppIcon.jpg")
            ]
        ),
        .testTarget(
            name: "MacMonitorTests",
            dependencies: ["MacMonitor"],
            path: "MacMonitor/Tests"
        )
    ]
)
