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

    public func start(rtsp: URL, crop: CropRegion? = nil) throws {
        precondition(rtsp.scheme == "rtsp", "expected an rtsp URL")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        process.executableURL = executable
        process.arguments = Self.arguments(rtsp: rtsp, directory: directory, crop: crop)
        process.standardOutput = FileHandle.nullDevice   // discard; nothing reads it
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw TranscoderError.launchFailed }
        assert(process.isRunning, "ffmpeg should be running after run()")
    }

    public func stop() {
        if process.isRunning { process.terminate() }
    }

    static func arguments(rtsp: URL, directory: URL, crop: CropRegion?) -> [String] {
        let playlist = directory.appendingPathComponent("stream.m3u8").path
        let segments = directory.appendingPathComponent("seg_%05d.ts").path
        return [
            "-nostdin", "-loglevel", "warning",
            "-fflags", "nobuffer",
            "-rtsp_transport", "tcp",
            "-i", rtsp.absoluteString,
        ] + videoArgs(crop: crop) + [
            "-c:a", "aac", "-b:a", "64k",
            "-f", "hls",
            "-hls_time", "1",
            "-hls_list_size", "8",
            "-hls_segment_type", "mpegts",
            // NB: no append_list — it makes AVPlayer reject the live playlist
            // with a spurious "discontinuity value does not match" (-12312).
            "-hls_flags", "delete_segments+independent_segments+omit_endlist",
            "-hls_segment_filename", segments,
            playlist,
        ]
    }

    /// Video args: copy when not zoomed; crop+re-encode (videotoolbox) when a
    /// zoom region is set so the zoom is baked into the stream (and thus PiP).
    private static func videoArgs(crop: CropRegion?) -> [String] {
        guard let crop, crop.zoom > 1 else { return ["-c:v", "copy"] }
        let z = String(format: "%.4f", crop.zoom)
        let px = String(format: "%.4f", crop.px)
        let py = String(format: "%.4f", crop.py)
        let filter = "crop=iw/\(z):ih/\(z):(iw-iw/\(z))*\(px):(ih-ih/\(z))*\(py),scale=-2:720"
        return ["-vf", filter, "-c:v", "h264_videotoolbox", "-b:v", "3M", "-g", "30"]
    }
}
