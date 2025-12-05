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
        // System library for libmpv
        .systemLibrary(
            name: "Clibmpv",
            path: "Sources/Clibmpv",
            pkgConfig: "mpv",
            providers: [
                .brew(["mpv"])
            ]
        ),
        .executableTarget(
            name: "VideoPlayer",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
                "Clibmpv"
            ],
            path: "Sources/VideoPlayer",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-I/opt/homebrew/include"])
            ],
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/lib"])
            ]
        )
    ]
)
