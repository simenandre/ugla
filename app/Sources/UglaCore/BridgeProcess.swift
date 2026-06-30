import Foundation

/// Runs the bundled `avent-webrtc-bridge direct` for one camera and resolves the
/// local RTSP URL it advertises on startup. One instance owns one OS process.
public final class BridgeProcess {
    public enum BridgeError: Error { case timeout, exited(Int32), launchFailed }

    private let executable: URL
    private let process = Process()
    private let output = Pipe()

    public init(executable: URL) {
        precondition(FileManager.default.isExecutableFile(atPath: executable.path),
                     "bridge must be executable")
        self.executable = executable
    }

    /// Start the bridge and return its RTSP URL once advertised, or throw on
    /// timeout / early exit. Bounded by `timeout`.
    public func start(session: Session, camera: Camera, rtspPort: Int,
                      timeout: TimeInterval = 30) async throws -> URL {
        precondition(session.isValid, "valid session required")
        precondition(!camera.id.isEmpty && rtspPort > 0, "camera + port required")
        process.executableURL = executable
        process.arguments = Self.arguments(session: session, camera: camera, port: rtspPort)
        process.standardOutput = output
        process.standardError = output
        // The bridge creates its `.tuya-data` storage relative to the working
        // directory. A GUI app launched via `open` runs with cwd "/", which is
        // not writable, so point it at a writable Application Support dir.
        process.currentDirectoryURL = Self.workingDirectory()

        let lock = NSLock()
        var done = false
        return try await withCheckedThrowingContinuation { cont in
            func finish(_ result: Result<URL, Error>) {
                lock.lock(); defer { lock.unlock() }
                guard !done else { return }
                done = true
                cont.resume(with: result)
            }
            output.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData                 // drains the pipe too
                guard let text = String(data: data, encoding: .utf8) else { return }
                if let url = Self.parseRTSP(text) { finish(.success(url)) }
            }
            process.terminationHandler = { proc in
                finish(.failure(BridgeError.exited(proc.terminationStatus)))
            }
            do { try process.run() } catch { finish(.failure(BridgeError.launchFailed)); return }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                finish(.failure(BridgeError.timeout))
            }
        }
    }

    public func stop() {
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
    }

    public var isRunning: Bool { process.isRunning }

    /// A writable directory for the bridge to keep its storage in.
    static func workingDirectory() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("Ugla/bridge", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func arguments(session: Session, camera: Camera, port: Int) -> [String] {
        [
            "direct",
            "--signing-key", TuyaConst.signingKey,
            "--sid", session.sid,
            "--ecode", session.ecode,
            "--partner", session.partner,
            "--app-key", TuyaConst.appKey,
            "--device-id", session.deviceID,
            "--ch-key", TuyaConst.chKey,
            "--package", TuyaConst.packageName,
            "--camera-id", camera.id,
            "--camera-name", camera.name,
            "--port", String(port),
        ]
    }

    /// Find `rtsp://localhost:<port>/<path>` in a log chunk, ignoring the `/sd`
    /// sub-stream variant so we return the HD endpoint.
    static func parseRTSP(_ text: String) -> URL? {
        for token in text.split(whereSeparator: { $0.isWhitespace }) {
            let s = String(token)
            guard s.hasPrefix("rtsp://localhost:"), !s.hasSuffix("/sd") else { continue }
            if let url = URL(string: s), url.path.count > 1 { return url }
        }
        return nil
    }
}
