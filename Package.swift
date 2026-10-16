// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacUtils",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacUtils", targets: ["MacUtils"])
    ],
    targets: [
        .executableTarget(
            name: "MacUtils",
            path: "MacUtils",
            exclude: ["Tests", "App/Info.plist"],
            sources: [
                "App",
                "Core",
                "Driver",
                "Features",
                "UI"
            ],
            resources: [
                .copy("Resources/AppIcon.png")
            ]
        ),
        .testTarget(
            name: "MacUtilsTests",
            dependencies: ["MacUtils"],
            path: "MacUtils/Tests"
        )
    ]
)
