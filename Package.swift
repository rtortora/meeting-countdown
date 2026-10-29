// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeetingCountdown",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure, EventKit-free logic so it can be unit tested.
        .target(name: "MeetingCountdownCore"),
        .executableTarget(
            name: "MeetingCountdown",
            dependencies: ["MeetingCountdownCore"]
        ),
        .testTarget(
            name: "MeetingCountdownCoreTests",
            dependencies: ["MeetingCountdownCore"]
        ),
    ]
)
