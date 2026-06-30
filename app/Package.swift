// swift-tools-version: 5.10
import PackageDescription

// Language mode 5 (not Swift 6 strict concurrency) is a deliberate, pragmatic
// choice for now: it keeps AppKit/AVKit delegate interop friction-free while we
// build out the app. Concurrency can be tightened later.
//
// Structure: a plain `UglaCore` library holds the testable logic (models,
// crypto, the Tuya client, process control); the `Ugla` executable is the
// SwiftUI menubar app; `SelfTest` is a CLT-friendly assertion runner (XCTest and
// swift-testing both require full Xcode, which we deliberately avoid).
let package = Package(
    name: "Ugla",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "UglaCore",
            path: "Sources/UglaCore"
        ),
        .executableTarget(
            name: "Ugla",
            dependencies: ["UglaCore"],
            path: "Sources/Ugla"
        ),
        .executableTarget(
            name: "SelfTest",
            dependencies: ["UglaCore"],
            path: "Sources/SelfTest"
        ),
        // Dev-only: runs the full pipeline for the saved session and prints the
        // HLS URL so it can be probed with ffprobe/ffplay. Not shipped.
        .executableTarget(
            name: "StreamProbe",
            dependencies: ["UglaCore"],
            path: "Sources/StreamProbe"
        ),
        // Dev-only: runs ffmpeg with given HLS flags and validates the output
        // with a real AVPlayer (AVPlayer is the strictest HLS client). Not shipped.
        .executableTarget(
            name: "HLSCheck",
            dependencies: ["UglaCore"],
            path: "Sources/HLSCheck"
        ),
    ]
)
