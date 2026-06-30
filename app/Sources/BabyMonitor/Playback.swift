import SwiftUI
import BabyMonitorCore

/// Owns live playback: turns a chosen camera into a running stream + PiP window.
/// Separate from `AppState` (which holds account/UI state) so concerns stay
/// unbraided. The view observes `state`; the work is delegated to the pipeline
/// and the player.
@MainActor
final class Playback: ObservableObject {
    enum State: Equatable {
        case idle
        case connecting(String)
        case watching(Camera)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let player = PlayerController()
    private let coordinator = StreamCoordinator()
    private let test = TestStream()

    var activeCamera: Camera? {
        if case .watching(let camera) = state { return camera }
        return nil
    }

    /// Start watching a real camera, then auto-pop into PiP.
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
                player.play(url: url, autoPiP: true)
                state = .watching(camera)
            } catch {
                state = .failed(message(for: error))
            }
        }
    }

    /// Dev: play a synthetic stream to exercise the player + PiP offline.
    func watchTestPattern() {
        stop()
        state = .connecting("Test pattern")
        do {
            let url = try test.start()
            player.play(url: url, autoPiP: true)
            state = .watching(Camera(id: "test", name: "Test pattern", category: ""))
        } catch {
            state = .failed(message(for: error))
        }
    }

    func popOut() { player.togglePiP() }

    func stop() {
        player.stop()
        coordinator.stop()
        test.stop()
        state = .idle
    }

    private func message(for error: Error) -> String {
        if case HelperLocator.LocatorError.notFound(let helper) = error {
            return "Missing bundled \(helper.rawValue)"
        }
        return "Couldn't start the stream"
    }
}
