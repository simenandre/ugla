import SwiftUI
import UglaCore

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
        // Process lifecycle (kill stale/own helpers at launch/quit) is handled
        // by AppDelegate, which runs reliably regardless of UI state.
        player.onPiPActiveChange = { [weak self] active in
            guard let self else { return }
            self.isPoppedOut = active
            // PiP ended (via our button OR the system close button) while still
            // streaming → restore the full, uncropped stream so we aren't stuck
            // at the baked-in zoom.
            if !active && self.isActive { self.restoreFullStream() }
        }
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
        let crop = player.currentCrop()
        player.popOut()                 // show PiP immediately (current frame)
        guard let crop else { return }  // not zoomed → nothing more to do
        Task {
            do {
                // Swap in the zoomed (cropped) stream behind the live PiP window.
                let url = try await coordinator.applyCrop(crop)
                player.play(url: url)
                player.setMuted(isMuted)
                player.resetInlineZoom()
            } catch {
                Diag.log("popOut: applyCrop failed \(error)")
            }
        }
    }

    /// Return from PiP to the inline preview. Stopping PiP triggers
    /// `restoreFullStream()` via the PiP-state handler.
    func popIn() { player.endPiP() }

    /// Restore the full (uncropped) stream and reset inline zoom. Runs whenever
    /// PiP ends while still streaming.
    private func restoreFullStream() {
        Task {
            do {
                let url = try await coordinator.applyCrop(nil)
                player.play(url: url)
                player.setMuted(isMuted)
            } catch {
                Diag.log("restoreFullStream: \(error)")  // e.g. test pattern has no coordinator
            }
            player.resetInlineZoom()
        }
    }

    func toggleMute() {
        isMuted.toggle()
        player.setMuted(isMuted)
    }

    func stop() {
        // Set idle first so the PiP-stop handler sees we are no longer active
        // and does not try to restore the stream during teardown.
        state = .idle
        player.stop()
        coordinator.stop()
        test.stop()
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
