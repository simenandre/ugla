import SwiftUI
import BabyMonitorCore

/// The app's observable UI state. Single source of truth for what the menubar
/// view renders. Holds values only; behaviour lives in dedicated types.
@MainActor
final class AppState: ObservableObject {
    /// Whether a stored session exists (drives Setup vs camera list).
    @Published private(set) var isConfigured: Bool
    /// Cameras discovered on the account. Empty until first-run setup completes.
    @Published private(set) var cameras: [Camera]
    /// A short human-readable status line for the popover footer.
    @Published private(set) var status: String

    init(isConfigured: Bool = false, cameras: [Camera] = []) {
        self.isConfigured = isConfigured
        self.cameras = cameras
        self.status = isConfigured ? "Ready" : "Not set up"
    }

    /// Build the initial state from a previously saved session, if any.
    static func bootstrap() -> AppState {
        guard let session = SessionStore.load(), session.isValid else { return AppState() }
        return AppState(isConfigured: true, cameras: session.cameras)
    }

    /// Forget the saved session (sign out).
    func reset() {
        SessionStore.clear()
        isConfigured = false
        cameras = []
        status = "Not set up"
    }

    /// Replace the camera list after a successful discovery.
    func setCameras(_ cameras: [Camera]) {
        // Discovery only runs once we are configured; a non-empty list here with
        // no session would be a programming error in the call sequence.
        assert(isConfigured || cameras.isEmpty, "cameras set before configuration")
        self.cameras = cameras
        self.status = cameras.isEmpty ? "No cameras found" : "\(cameras.count) camera(s)"
    }

    /// Mark the app as configured (a session was saved).
    func markConfigured() {
        isConfigured = true
        if status == "Not set up" { status = "Ready" }
    }
}
