import Foundation
import UglaCore

// Dev verification: start the full pipeline for the saved session's first camera
// (or a camera named by argv[1]) and print the HLS URL, then keep running so it
// can be probed:  ffprobe <url>  /  ffplay <url>
// Requires BABYMON_HELPERS_DIR to point at app/helpers.

guard let session = SessionStore.load(), session.isValid else {
    FileHandle.standardError.write(Data("no saved session — sign in via the app first\n".utf8))
    exit(1)
}
let wanted = CommandLine.arguments.dropFirst().first
let camera = session.cameras.first { wanted == nil || $0.name == wanted } ?? session.cameras.first
guard let camera else {
    FileHandle.standardError.write(Data("no cameras in session\n".utf8))
    exit(1)
}

let coordinator = StreamCoordinator()
let sema = DispatchSemaphore(value: 0)

Task {
    do {
        let url = try await coordinator.start(session: session, camera: camera)
        print("BABYMON_HLS \(camera.name) \(url.absoluteString)")
        fflush(stdout)
    } catch {
        FileHandle.standardError.write(Data("pipeline failed: \(error)\n".utf8))
        exit(1)
    }
    sema.signal()
}

sema.wait()
print("streaming… Ctrl-C to stop")
RunLoop.main.run()
