import Foundation
import UglaCore

/// Terminates the bundled helper processes (bridge, ffmpeg) so they are never
/// orphaned: leftovers from a previous crash are cleared at launch, and our own
/// children are killed on quit. Matched by our Helpers directory path, so this
/// only ever targets our binaries. Driven from `UglaApp.init`.
enum HelperProcesses {
    static func killAll() {
        guard let dir = HelperLocator.url(for: .bridge)?
            .deletingLastPathComponent().path else { return }
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-f", dir]
        try? pkill.run()
        pkill.waitUntilExit()
    }
}
