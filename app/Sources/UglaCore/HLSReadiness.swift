import Foundation

/// Waits for an HLS playlist to become playable. ffmpeg needs a second or two to
/// produce the first segment; handing the URL to AVPlayer before then yields a
/// 404 it treats as a permanent failure. We poll until the playlist lists at
/// least one segment.
public enum HLS {
    /// Returns true once `playlist` exists and references a segment, or false on
    /// timeout. Bounded by both an attempt cap and a wall-clock deadline.
    public static func waitForPlaylist(at playlist: URL, timeout: TimeInterval) async -> Bool {
        precondition(timeout > 0, "timeout must be positive")
        let deadline = Date().addingTimeInterval(timeout)
        let maxAttempts = 600  // hard cap (Power of Ten: bounded loop)
        var attempts = 0
        while attempts < maxAttempts {
            attempts += 1
            if let text = try? String(contentsOf: playlist, encoding: .utf8),
               text.contains("#EXTINF") {
                return true
            }
            if Date() >= deadline { return false }
            try? await Task.sleep(nanoseconds: 200_000_000)  // 0.2s
        }
        return false
    }
}
