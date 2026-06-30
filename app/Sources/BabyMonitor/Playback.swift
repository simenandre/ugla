import SwiftUI
import BabyMonitorCore

/// Owns live playback: turns a chosen camera into a running stream shown inline
/// in the popover, with a "Pop out" that floats it as native PiP. Separate from
/// `AppState` (account/UI state) so concerns stay unbraided.
@MainActor
final class Playback: ObservableObject {
    enum State: Equatable {
        case idle
        case connecting(String)
        case watching(Camera)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// Whether audio is muted. A baby monitor defaults to sound on.
    @Published private(set) var isMuted = false

    let player = PlayerController()
    private let coordinator = StreamCoordinator()

    var activeCamera: Camera? {
        if case .watching(let camera) = state { return camera }
        if case .connecting = state { return nil }
        return nil
    }

    var isActive: Bool {
        switch state { case .idle, .failed: return false; default: return true }
    }

    var isPiPActive: Bool { player.isPiPActive }

    /// Start watching a real camera (plays inline in the popover).
    func watch(_ camera: Camera) {
        precondition(!camera.id.isEmpty, "camera id required")
        stop()
        state = .connecting(camera.name)
        Task {
            guard let session = SessionStore.load(), session.isValid else {
                state = .failed("Please sign in again"); return
            }
            do {
                let url = try await coordinator.start(session: session, camera: camera)
                player.play(url: url)
                player.setMuted(isMuted)
                state = .watching(camera)
            } catch {
                state = .failed(message(for: error))
            }
        }
    }

    /// Dev: play a known-good reference HLS to validate inline playback + PiP.
    func watchTestPattern() {
        stop()
        state = .connecting("Test (Apple)")
        let url = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8")!
        player.play(url: url)
        player.setMuted(isMuted)
        state = .watching(Camera(id: "test", name: "Test (Apple)", category: ""))
    }

    func popOut() { player.popOut() }

    func toggleMute() {
        isMuted.toggle()
        player.setMuted(isMuted)
    }

    func stop() {
        player.stop()
        coordinator.stop()
        state = .idle
    }

    // The stream intentionally keeps running when the popover closes (a baby
    // monitor should keep monitoring — audio continues, and reopening the menu
    // resumes the inline video). Use Stop to tear it down.

    private func message(for error: Error) -> String {
        if case HelperLocator.LocatorError.notFound(let helper) = error {
            return "Missing bundled \(helper.rawValue)"
        }
        return "Couldn't start the stream"
    }
}
