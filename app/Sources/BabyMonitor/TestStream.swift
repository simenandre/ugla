import Foundation
import BabyMonitorCore

/// Dev-only: generates a synthetic HLS stream (test pattern + tone) with the
/// bundled ffmpeg, served over the local HTTP server. Lets us validate the
/// AVPlayer + PiP path without a live camera. Not shown in release builds.
@MainActor
final class TestStream {
    private let process = Process()
    private var server: LocalHTTPServer?
    private var directory: URL?

    func start() throws -> URL {
        let ffmpeg = try HelperLocator.require(.ffmpeg)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("babymon-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        directory = dir

        process.executableURL = ffmpeg
        process.arguments = Self.arguments(directory: dir)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        assert(process.isRunning, "test ffmpeg should be running")

        let server = LocalHTTPServer(directory: dir)
        self.server = server
        return try server.start().appendingPathComponent("stream.m3u8")
    }

    func stop() {
        server?.stop(); server = nil
        if process.isRunning { process.terminate() }
        if let dir = directory { try? FileManager.default.removeItem(at: dir); directory = nil }
    }

    private static func arguments(directory: URL) -> [String] {
        [
            "-nostdin", "-loglevel", "error", "-re",
            "-f", "lavfi", "-i", "testsrc=size=640x360:rate=15",
            "-f", "lavfi", "-i", "sine=frequency=440",
            "-c:v", "h264_videotoolbox", "-g", "30",
            "-c:a", "aac", "-b:a", "64k",
            "-f", "hls", "-hls_time", "1", "-hls_list_size", "6",
            "-hls_segment_type", "mpegts",
            "-hls_flags", "delete_segments+append_list+omit_endlist",
            "-hls_segment_filename", directory.appendingPathComponent("seg_%05d.ts").path,
            directory.appendingPathComponent("stream.m3u8").path,
        ]
    }
}
