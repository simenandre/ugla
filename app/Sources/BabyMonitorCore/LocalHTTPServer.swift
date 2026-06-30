import Foundation
import Network

/// A tiny loopback HTTP/1.1 file server for the HLS directory. AVPlayer plays
/// live HLS reliably over http (not file URLs), so we serve the ffmpeg output on
/// 127.0.0.1 with a random port. One GET per connection; no keep-alive.
public final class LocalHTTPServer {
    public enum ServerError: Error { case failedToStart }

    private let directory: URL
    private let queue = DispatchQueue(label: "com.simenandre.babymonitor.http")
    private var listener: NWListener?
    public private(set) var port: UInt16 = 0

    public init(directory: URL) {
        precondition(FileManager.default.fileExists(atPath: directory.path), "serve dir must exist")
        self.directory = directory
    }

    /// Start listening on 127.0.0.1:<random> and return the base URL.
    public func start() throws -> URL {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any) // loopback only
        let listener = try NWListener(using: params)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in self?.serve(conn) }

        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, let p = listener.port?.rawValue else {
            throw ServerError.failedToStart
        }
        port = p
        assert(port != 0, "listening port assigned")
        guard let url = URL(string: "http://127.0.0.1:\(p)/") else { throw ServerError.failedToStart }
        return url
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func serve(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, error in
            guard let self, let data, error == nil else { conn.cancel(); return }
            let response = self.response(for: data)
            // Send as the final message (isComplete) so the framework flushes the
            // whole body and sends FIN before we tear down — cancelling earlier
            // truncates large segments and breaks playback.
            conn.send(content: response, contentContext: .finalMessage, isComplete: true,
                      completion: .contentProcessed { _ in conn.cancel() })
        }
    }

    private struct Request { let method: String; let path: String; let range: (Int, Int?)? }

    private func response(for data: Data) -> Data {
        guard let req = Self.parse(data) else {
            return Self.http(400, "Bad Request", "text/plain", Data(), length: 0, extra: [:])
        }
        guard let fileURL = resolved(req.path), let full = try? Data(contentsOf: fileURL) else {
            let body = Data("not found".utf8)
            return Self.http(404, "Not Found", "text/plain", body, length: body.count, extra: [:])
        }
        let type = Self.contentType(for: fileURL)
        let wantsBody = req.method == "GET"
        // Range request → 206 Partial Content (AVPlayer requires this for media).
        if let range = req.range, let slice = Self.clamp(range, count: full.count) {
            let body = wantsBody ? full.subdata(in: slice) : Data()
            let header = ["Content-Range": "bytes \(slice.lowerBound)-\(slice.upperBound - 1)/\(full.count)"]
            return Self.http(206, "Partial Content", type, body, length: slice.count, extra: header)
        }
        return Self.http(200, "OK", type, wantsBody ? full : Data(), length: full.count, extra: [:])
    }

    /// Map a URL path to a file inside `directory`, rejecting traversal.
    private func resolved(_ path: String) -> URL? {
        let trimmed = path.split(separator: "?").first.map(String.init) ?? path
        let name = trimmed.removingPercentEncoding ?? trimmed
        guard !name.contains(".."), name.hasPrefix("/") else { return nil }
        let fileURL = directory.appendingPathComponent(String(name.dropFirst())).standardized
        guard fileURL.path.hasPrefix(directory.standardized.path) else { return nil }
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    private static func parse(_ data: Data) -> Request? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" || parts[0] == "HEAD" else { return nil }
        var range: (Int, Int?)?
        for line in lines.dropFirst() where line.lowercased().hasPrefix("range:") {
            range = parseRange(line)
            break
        }
        return Request(method: String(parts[0]), path: String(parts[1]), range: range)
    }

    /// Parse "Range: bytes=START-[END]"; END nil means "to the end".
    private static func parseRange(_ line: String) -> (Int, Int?)? {
        guard let eq = line.firstIndex(of: "=") else { return nil }
        let spec = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        let bounds = spec.split(separator: "-", omittingEmptySubsequences: false)
        guard let start = Int(bounds.first ?? "") else { return nil }
        let end = bounds.count > 1 ? Int(bounds[1].trimmingCharacters(in: .whitespaces)) : nil
        return (start, end)
    }

    /// Clamp a (start, end?) byte range to a half-open Range within count.
    private static func clamp(_ range: (Int, Int?), count: Int) -> Range<Int>? {
        let start = max(0, range.0)
        guard start < count else { return nil }
        let endInclusive = min(range.1 ?? (count - 1), count - 1)
        guard endInclusive >= start else { return nil }
        return start ..< (endInclusive + 1)
    }

    static func contentType(for url: URL) -> String {
        switch url.pathExtension {
        case "m3u8": return "application/vnd.apple.mpegurl"
        case "ts": return "video/mp2t"
        default: return "application/octet-stream"
        }
    }

    static func http(_ status: Int, _ reason: String, _ contentType: String, _ body: Data,
                     length: Int, extra: [String: String]) -> Data {
        var header = "HTTP/1.1 \(status) \(reason)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(length)\r\n"
        header += "Accept-Ranges: bytes\r\n"
        for (key, value) in extra { header += "\(key): \(value)\r\n" }
        header += "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        return Data(header.utf8) + body
    }
}
