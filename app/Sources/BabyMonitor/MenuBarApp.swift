import SwiftUI
import BabyMonitorCore

/// Entry point. A menubar-only app (LSUIElement in Info.plist → no Dock icon).
/// Clicking the menubar icon opens a window-style popover listing the cameras.
@main
struct BabyMonitorApp: App {
    @StateObject private var state = AppState.bootstrap()
    @StateObject private var playback = Playback()

    var body: some Scene {
        MenuBarExtra("Baby Monitor", systemImage: "video.fill") {
            PopoverView()
                .environmentObject(state)
                .environmentObject(playback)
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
/// Tap a child to start its feed and pop it into a floating PiP window.
struct ConfiguredView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var playback: Playback

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Baby Monitor").font(.headline)

            if state.cameras.isEmpty {
                Text("No cameras found.").foregroundStyle(.secondary)
            } else {
                ForEach(state.cameras) { camera in
                    cameraRow(camera)
                }
            }

            #if DEBUG
            Button { playback.watchTestPattern() } label: {
                Label("Test pattern", systemImage: "waveform")
            }
            .buttonStyle(.plain)
            #endif

            if playback.activeCamera != nil {
                Divider()
                Button { playback.popOut() } label: { Label("Pop out (PiP)", systemImage: "pip.enter") }
                Button("Stop") { playback.stop() }
            }

            Divider()
            HStack {
                Text(statusText).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Sign out") { playback.stop(); state.reset() }
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    private func cameraRow(_ camera: Camera) -> some View {
        Button { playback.watch(camera) } label: {
            HStack {
                Label(camera.name, systemImage: "video")
                Spacer()
                if playback.activeCamera == camera {
                    Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(.red)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var statusText: String {
        switch playback.state {
        case .idle: return state.status
        case .connecting(let name): return "Connecting to \(name)…"
        case .watching(let camera): return "Watching \(camera.name)"
        case .failed(let message): return message
        }
    }
}
