import Foundation

/// Runs the bundled ffmpeg to repackage the bridge's RTSP into HLS (video
/// copied, G.711 audio transcoded to AAC) in a directory the local HTTP server
/// serves. One instance owns one ffmpeg process.
public final class Transcoder {
    public enum TranscoderError: Error { case launchFailed }

    private let executable: URL
    private let process = Process()
    public let directory: URL

    public init(executable: URL, directory: URL) {
        precondition(FileManager.default.isExecutableFile(atPath: executable.path),
                     "ffmpeg must be executable")
        self.executable = executable
        self.directory = directory
    }

    public var playlistURL: URL { directory.appendingPathComponent("stream.m3u8") }
    public var isRunning: Bool { process.isRunning }

    public func start(rtsp: URL) throws {
        precondition(rtsp.scheme == "rtsp", "expected an rtsp URL")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        process.executableURL = executable
        process.arguments = Self.arguments(rtsp: rtsp, directory: directory)
        process.standardOutput = FileHandle.nullDevice   // discard; nothing reads it
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw TranscoderError.launchFailed }
        assert(process.isRunning, "ffmpeg should be running after run()")
    }

    public func stop() {
        if process.isRunning { process.terminate() }
    }

    static func arguments(rtsp: URL, directory: URL) -> [String] {
        let playlist = directory.appendingPathComponent("stream.m3u8").path
        let segments = directory.appendingPathComponent("seg_%05d.ts").path
        return [
            "-nostdin", "-loglevel", "warning",
            "-fflags", "nobuffer",
            "-rtsp_transport", "tcp",
            "-i", rtsp.absoluteString,
            "-c:v", "copy",
            "-c:a", "aac", "-b:a", "64k",
            "-f", "hls",
            "-hls_time", "1",
            "-hls_list_size", "8",
            "-hls_segment_type", "mpegts",
            "-hls_flags", "delete_segments+append_list+independent_segments+omit_endlist",
            "-hls_segment_filename", segments,
            playlist,
        ]
    }
}
