import Foundation

/// Owns one camera's full pipeline: bridge (WebRTC→RTSP) → ffmpeg (RTSP→HLS) →
/// local HTTP. `start` returns the HLS URL for AVPlayer; `stop` tears the whole
/// chain down and deletes the temp directory. Single-purpose parts, composed.
public final class StreamCoordinator {
    public enum StreamError: Error { case playlistTimedOut }

    private let rtspPort: Int
    private var bridge: BridgeProcess?
    private var transcoder: Transcoder?
    private var server: LocalHTTPServer?
    private var tempDir: URL?

    public init(rtspPort: Int = 8554) {
        precondition(rtspPort > 0, "rtsp port required")
        self.rtspPort = rtspPort
    }

    /// Start streaming `camera` and return its local HLS URL.
    public func start(session: Session, camera: Camera) async throws -> URL {
        precondition(session.isValid, "valid session required")
        stop()  // never run two pipelines from one coordinator

        let bridgeExe = try HelperLocator.require(.bridge)
        let ffmpegExe = try HelperLocator.require(.ffmpeg)

        let bridge = BridgeProcess(executable: bridgeExe)
        self.bridge = bridge
        let rtsp = try await bridge.start(session: session, camera: camera, rtspPort: rtspPort)

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("babymon-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.tempDir = dir

        let transcoder = Transcoder(executable: ffmpegExe, directory: dir)
        self.transcoder = transcoder
        try transcoder.start(rtsp: rtsp)

        // Wait for ffmpeg to produce a playable playlist before handing it to
        // AVPlayer (a 404 manifest is a permanent failure there).
        guard await HLS.waitForPlaylist(at: transcoder.playlistURL, timeout: 25) else {
            stop()
            throw StreamError.playlistTimedOut
        }

        let server = LocalHTTPServer(directory: dir)
        self.server = server
        let base = try server.start()

        assert(bridge.isRunning && transcoder.isRunning, "pipeline should be live")
        return base.appendingPathComponent("stream.m3u8")
    }

    /// Stop everything and clean up. Safe to call repeatedly.
    public func stop() {
        server?.stop(); server = nil
        transcoder?.stop(); transcoder = nil
        bridge?.stop(); bridge = nil
        if let dir = tempDir { try? FileManager.default.removeItem(at: dir); tempDir = nil }
    }

    public var isStreaming: Bool { bridge?.isRunning == true && transcoder?.isRunning == true }
}
