import Foundation

/// Minimal file logger for debugging the GUI app (unified logging proved hard to
/// read from an ad-hoc app). Appends to /tmp/ugla.log. Dev aid only.
enum Diag {
    private static let url = URL(fileURLWithPath: "/tmp/ugla.log")

    static func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = Data("\(stamp) \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }
}
