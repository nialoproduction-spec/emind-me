// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RemindMe",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "RemindMe",
            path: "Sources/RemindMe",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "RemindMeTests",
            dependencies: ["RemindMe"],
            path: "Tests/RemindMeTests"
        )
    ]
)
