// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScanOrganizer",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .executable(
            name: "scan-organizer",
            targets: ["ScanOrganizerCLI"]
        ),
        .executable(
            name: "ScanOrganizerApp",
            targets: ["ScanOrganizerApp"]
        ),
        .library(
            name: "ScanOrganizerCore",
            targets: ["ScanOrganizerCore"]
        ),
        .library(
            name: "ScanOrganizerAppIntents",
            targets: ["ScanOrganizerAppIntents"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/stephencelis/SQLite.swift", from: "0.14.0")
    ],
    targets: [
        // Core business logic
        .target(
            name: "ScanOrganizerCore",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift")
            ],
            path: "Sources/Core"
        ),

        // CLI executable
        .executableTarget(
            name: "ScanOrganizerCLI",
            dependencies: [
                "ScanOrganizerCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/CLI"
        ),

        // GUI App executable
        .executableTarget(
            name: "ScanOrganizerApp",
            dependencies: [
                "ScanOrganizerCore",
                "ScanOrganizerAppIntents"
            ],
            path: "Sources/App",
            exclude: ["Info.plist"]
        ),

        // App Intents for Quick Actions
        .target(
            name: "ScanOrganizerAppIntents",
            dependencies: [],
            path: "Sources/AppIntents"
        ),

        // Tests
        .testTarget(
            name: "ScanOrganizerTests",
            dependencies: ["ScanOrganizerCore"],
            path: "Tests"
        )
    ]
)