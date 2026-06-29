import SwiftUI
import BabyMonitorCore

/// Entry point. A menubar-only app (LSUIElement in Info.plist → no Dock icon).
/// Clicking the menubar icon opens a window-style popover listing the cameras.
@main
struct BabyMonitorApp: App {
    @StateObject private var state = AppState.bootstrap()

    var body: some Scene {
        MenuBarExtra("Baby Monitor", systemImage: "video.fill") {
            PopoverView()
                .environmentObject(state)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The popover shown from the menubar: setup until configured, then the camera
/// list. Per-camera PiP actions are wired in Phase 3.
struct PopoverView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        if state.isConfigured {
            ConfiguredView()
        } else {
            SetupView()
        }
    }
}

/// Shown once a session exists: the list of cameras (children) plus controls.
struct ConfiguredView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Baby Monitor").font(.headline)

            if state.cameras.isEmpty {
                Text("No cameras found.").foregroundStyle(.secondary)
            } else {
                ForEach(state.cameras) { camera in
                    Label(camera.name, systemImage: "video")
                }
            }

            Divider()
            HStack {
                Text(state.status).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Sign out") { state.reset() }
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 260)
    }
}
