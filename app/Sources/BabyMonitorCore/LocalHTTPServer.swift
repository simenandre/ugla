import Foundation
import Network

/// A tiny loopback HTTP/1.1 file server for the HLS directory. AVPlayer plays
/// live HLS reliably over http (not file URLs), so we serve the ffmpeg output on
/// 127.0.0.1 with a random port. One GET per connection; no keep-alive.
public final class LocalHTTPServer {
    public enum ServerError: Error { case failedToStart }

    private let directory: URL
    private let queue = DispatchQueue(label: "io.sokkel.babymonitor.http")
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
            conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
        }
    }

    private func response(for request: Data) -> Data {
        guard let path = Self.requestedPath(request) else { return Self.http(404, "text/plain", Data()) }
        guard let fileURL = resolved(path), let body = try? Data(contentsOf: fileURL) else {
            return Self.http(404, "text/plain", Data("not found".utf8))
        }
        return Self.http(200, Self.contentType(for: fileURL), body)
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

    static func requestedPath(_ request: Data) -> String? {
        guard let text = String(data: request, encoding: .utf8),
              let line = text.split(separator: "\r\n", maxSplits: 1).first else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return nil }
        return String(parts[1])
    }

    static func contentType(for url: URL) -> String {
        switch url.pathExtension {
        case "m3u8": return "application/vnd.apple.mpegurl"
        case "ts": return "video/mp2t"
        default: return "application/octet-stream"
        }
    }

    static func http(_ status: Int, _ contentType: String, _ body: Data) -> Data {
        let reason = status == 200 ? "OK" : "Not Found"
        var header = "HTTP/1.1 \(status) \(reason)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Cache-Control: no-store\r\n"
        header += "Connection: close\r\n\r\n"
        return Data(header.utf8) + body
    }
}
