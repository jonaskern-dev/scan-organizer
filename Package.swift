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
    dependencies: [],
    targets: [
        // Core business logic
        .target(
            name: "ScanOrganizerCore",
            dependencies: [],
            path: "Sources/Core"
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