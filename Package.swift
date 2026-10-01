// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Vesila",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .executableTarget(
            name: "Vesila",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            resources: [
                .copy("Resources/vesila-idle.svg"),
                .copy("Resources/vesila-presence.svg"),
                .copy("Resources/vesila-awake.svg"),
                .copy("Resources/vesila-both.svg"),
                .copy("Resources/ReleaseNotes.json")
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "VesilaTests",
            dependencies: ["Vesila"]
        )
    ]
)
