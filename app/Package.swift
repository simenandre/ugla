// swift-tools-version: 5.10
import PackageDescription

// Language mode 5 (not Swift 6 strict concurrency) is a deliberate, pragmatic
// choice for now: it keeps AppKit/AVKit delegate interop friction-free while we
// build out the app. Concurrency can be tightened later.
//
// Structure: a plain `BabyMonitorCore` library holds the testable logic (models,
// crypto, the Tuya client, process control); the `BabyMonitor` executable is the
// SwiftUI menubar app; `SelfTest` is a CLT-friendly assertion runner (XCTest and
// swift-testing both require full Xcode, which we deliberately avoid).
let package = Package(
    name: "BabyMonitor",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "BabyMonitorCore",
            path: "Sources/BabyMonitorCore"
        ),
        .executableTarget(
            name: "BabyMonitor",
            dependencies: ["BabyMonitorCore"],
            path: "Sources/BabyMonitor"
        ),
        .executableTarget(
            name: "SelfTest",
            dependencies: ["BabyMonitorCore"],
            path: "Sources/SelfTest"
        ),
        // Dev-only: runs the full pipeline for the saved session and prints the
        // HLS URL so it can be probed with ffprobe/ffplay. Not shipped.
        .executableTarget(
            name: "StreamProbe",
            dependencies: ["BabyMonitorCore"],
            path: "Sources/StreamProbe"
        ),
    ]
)
