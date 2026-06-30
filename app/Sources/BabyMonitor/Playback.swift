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
    /// Whether the feed is currently floating as Picture-in-Picture.
    @Published private(set) var isPoppedOut = false

    let player = PlayerController()
    private let coordinator = StreamCoordinator()
    private let test = TestStream()

    init() {
        player.onPiPActiveChange = { [weak self] active in self?.isPoppedOut = active }
    }

    var activeCamera: Camera? {
        if case .watching(let camera) = state { return camera }
        if case .connecting = state { return nil }
        return nil
    }

    var isActive: Bool {
        switch state { case .idle, .failed: return false; default: return true }
    }


    /// Start watching a real camera (plays inline in the popover).
    func watch(_ camera: Camera) {
        precondition(!camera.id.isEmpty, "camera id required")
        stop()
        state = .connecting(camera.name)
        Task {
            guard let session = SessionStore.load(), session.isValid else {
                Diag.log("watch(\(camera.name)): no valid session in keychain")
                state = .failed("Please sign in again"); return
            }
            Diag.log("watch(\(camera.name)): starting pipeline")
            do {
                let url = try await coordinator.start(session: session, camera: camera)
                Diag.log("watch(\(camera.name)): HLS ready at \(url.absoluteString)")
                player.play(url: url)
                player.setMuted(isMuted)
                state = .watching(camera)
            } catch {
                Diag.log("watch(\(camera.name)): FAILED \(error)")
                state = .failed(message(for: error))
            }
        }
    }

    /// Dev: play an offline synthetic stream (our own ffmpeg HLS) to validate
    /// the full local pipeline + PiP without a camera.
    func watchTestPattern() {
        stop()
        state = .connecting("Test pattern")
        Task {
            do {
                let url = try await test.start()
                player.play(url: url)
                player.setMuted(isMuted)
                state = .watching(Camera(id: "test", name: "Test pattern", category: ""))
            } catch {
                state = .failed(message(for: error))
            }
        }
    }

    /// Pop out to PiP. If zoomed, bake the current zoom into the stream first so
    /// the (system-rendered) PiP window shows the zoomed view.
    func popOut() {
        guard let crop = player.currentCrop() else { player.popOut(); return }
        Task {
            do {
                let url = try await coordinator.applyCrop(crop)
                player.play(url: url)
                player.setMuted(isMuted)
                player.resetInlineZoom()   // stream is now pre-cropped
            } catch {
                Diag.log("popOut: applyCrop failed \(error)")
            }
            player.popOut()
        }
    }

    /// Return from PiP to the inline preview, restoring the full (uncropped)
    /// stream so smooth inline zoom is available again.
    func popIn() {
        player.endPiP()
        Task {
            do {
                let url = try await coordinator.applyCrop(nil)
                player.play(url: url)
                player.setMuted(isMuted)
            } catch {
                Diag.log("popIn: applyCrop failed \(error)")
            }
        }
    }

    func toggleMute() {
        isMuted.toggle()
        player.setMuted(isMuted)
    }

    func stop() {
        player.stop()
        coordinator.stop()
        test.stop()
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
