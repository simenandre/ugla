import Foundation

/// Owns one camera's full pipeline: bridge (WebRTC→RTSP) → ffmpeg (RTSP→HLS) →
/// local HTTP. `start` returns the HLS URL for AVPlayer; `applyCrop` restarts
/// only the transcode (keeping the bridge/WebRTC connection) to bake a zoom into
/// the stream; `stop` tears the whole chain down. Single-purpose parts, composed.
public final class StreamCoordinator {
    public enum StreamError: Error { case playlistTimedOut, notStreaming }

    private let rtspPort: Int
    private var bridge: BridgeProcess?
    private var transcoder: Transcoder?
    private var server: LocalHTTPServer?
    private var tempDir: URL?
    private var rtsp: URL?
    private var ffmpegExe: URL?

    public init(rtspPort: Int = 8554) {
        precondition(rtspPort > 0, "rtsp port required")
        self.rtspPort = rtspPort
    }

    /// Start streaming `camera` and return its local HLS URL.
    public func start(session: Session, camera: Camera) async throws -> URL {
        precondition(session.isValid, "valid session required")
        stop()  // never run two pipelines from one coordinator

        let bridgeExe = try HelperLocator.require(.bridge)
        ffmpegExe = try HelperLocator.require(.ffmpeg)

        let bridge = BridgeProcess(executable: bridgeExe)
        self.bridge = bridge
        rtsp = try await bridge.start(session: session, camera: camera, rtspPort: rtspPort)

        return try await startTranscode(crop: nil)
    }

    /// Restart the transcode with a new zoom region (or nil for full frame),
    /// keeping the bridge/WebRTC connection alive. Returns the new HLS URL.
    public func applyCrop(_ crop: CropRegion?) async throws -> URL {
        guard rtsp != nil, ffmpegExe != nil else { throw StreamError.notStreaming }
        return try await startTranscode(crop: crop)
    }

    /// (Re)start ffmpeg + HTTP in a fresh directory for the given crop.
    private func startTranscode(crop: CropRegion?) async throws -> URL {
        precondition(rtsp != nil && ffmpegExe != nil, "bridge must be started first")
        server?.stop(); server = nil
        transcoder?.stop(); transcoder = nil
        if let dir = tempDir { try? FileManager.default.removeItem(at: dir); tempDir = nil }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("babymon-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDir = dir

        let transcoder = Transcoder(executable: ffmpegExe!, directory: dir)
        self.transcoder = transcoder
        try transcoder.start(rtsp: rtsp!, crop: crop)

        guard await HLS.waitForPlaylist(at: transcoder.playlistURL, timeout: 25) else {
            stop()
            throw StreamError.playlistTimedOut
        }

        let server = LocalHTTPServer(directory: dir)
        self.server = server
        let base = try server.start()
        assert(transcoder.isRunning, "transcoder should be live")
        return base.appendingPathComponent("stream.m3u8")
    }

    /// Stop everything and clean up. Safe to call repeatedly.
    public func stop() {
        server?.stop(); server = nil
        transcoder?.stop(); transcoder = nil
        bridge?.stop(); bridge = nil
        rtsp = nil
        if let dir = tempDir { try? FileManager.default.removeItem(at: dir); tempDir = nil }
    }

    public var isStreaming: Bool { bridge?.isRunning == true && transcoder?.isRunning == true }
}
