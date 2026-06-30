import Foundation
import AVFoundation
import BabyMonitorCore

// Dev tool: run ffmpeg test pattern with given HLS flags, serve via the local
// HTTP server, and validate with a real AVPlayer.
//   HLSCheck "<hls_flags>" <hls_time> <hls_list_size>
// Requires BABYMON_HELPERS_DIR pointing at app/helpers.

let args = CommandLine.arguments
let flags = args.count > 1 ? args[1] : "delete_segments+independent_segments"
let htime = args.count > 2 ? args[2] : "2"
let lsize = args.count > 3 ? args[3] : "8"

let ffmpeg = try! HelperLocator.require(.ffmpeg)
let dir = FileManager.default.temporaryDirectory
    .appendingPathComponent("hlscheck-\(UUID().uuidString)", isDirectory: true)
try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

let proc = Process()
proc.executableURL = ffmpeg
proc.arguments = [
    "-nostdin", "-loglevel", "error", "-re",
    "-f", "lavfi", "-i", "testsrc=size=640x360:rate=15",
    "-f", "lavfi", "-i", "sine=frequency=440",
    "-c:v", "h264_videotoolbox", "-g", "30", "-pix_fmt", "yuv420p",
    "-c:a", "aac", "-b:a", "64k",
    "-f", "hls", "-hls_time", htime, "-hls_list_size", lsize, "-hls_segment_type", "mpegts",
    "-hls_flags", flags,
    "-hls_segment_filename", dir.appendingPathComponent("seg_%05d.ts").path,
    dir.appendingPathComponent("stream.m3u8").path,
]
proc.standardError = FileHandle.nullDevice
proc.standardOutput = FileHandle.nullDevice
try! proc.run()

let playlist = dir.appendingPathComponent("stream.m3u8")
let ready = DispatchSemaphore(value: 0)
Task { _ = await HLS.waitForPlaylist(at: playlist, timeout: 15); ready.signal() }
ready.wait()

let server = LocalHTTPServer(directory: dir)
let base = try! server.start()
let url = base.appendingPathComponent("stream.m3u8")
print("flags=\(flags) time=\(htime) list=\(lsize)")

let item = AVPlayerItem(url: url)
let player = AVPlayer(playerItem: item)
player.play()
let deadline = Date().addingTimeInterval(20)
while Date() < deadline {
    switch item.status {
    case .readyToPlay:
        print("RESULT: READY ✅"); proc.terminate(); exit(0)
    case .failed:
        print("RESULT: FAILED \((item.error as NSError?)?.code ?? 0)")
        for e in item.errorLog()?.events ?? [] { print("  status=\(e.errorStatusCode) \(e.errorComment ?? "")") }
        proc.terminate(); exit(1)
    default: break
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
}
print("RESULT: TIMEOUT"); proc.terminate(); exit(2)
