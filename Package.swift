// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Vesila",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Vesila",
            resources: [
                .copy("Resources/vesila-idle.svg"),
                .copy("Resources/vesila-presence.svg"),
                .copy("Resources/vesila-awake.svg"),
                .copy("Resources/vesila-both.svg")
            ],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .testTarget(
            name: "VesilaTests",
            dependencies: ["Vesila"]
        )
    ]
)
