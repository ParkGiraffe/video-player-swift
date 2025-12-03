// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VideoPlayer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "VideoPlayer", targets: ["VideoPlayer"])
    ],
    dependencies: [
        // SQLite for database
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.14.1"),
    ],
    targets: [
        .executableTarget(
            name: "VideoPlayer",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
            ],
            path: "Sources/VideoPlayer",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                // Link mpv library
                .linkedLibrary("mpv"),
                .unsafeFlags(["-L/opt/homebrew/lib", "-I/opt/homebrew/include"])
            ]
        )
    ]
)
