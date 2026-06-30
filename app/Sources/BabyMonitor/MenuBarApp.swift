import SwiftUI
import BabyMonitorCore

/// Entry point. A menubar-only app (LSUIElement in Info.plist → no Dock icon).
/// Clicking the menubar icon opens a window-style popover listing the cameras.
@main
struct BabyMonitorApp: App {
    @StateObject private var state = AppState.bootstrap()
    @StateObject private var playback = Playback()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(state)
                .environmentObject(playback)
        } label: {
            // Filled icon while a feed is live, outline when idle.
            Image(systemName: playback.isActive ? "video.fill" : "video")
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

/// Shown once a session exists. Either the camera list, or — once a feed is
/// playing — an inline preview with a Pop out (PiP) control.
struct ConfiguredView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var playback: Playback

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if playback.isActive {
                watchingView
            } else {
                cameraListView
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
        .frame(width: 280)
    }

    private var cameraListView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Baby Monitor").font(.headline)
            if state.cameras.isEmpty {
                Text("No cameras found.").foregroundStyle(.secondary)
            } else {
                ForEach(state.cameras) { camera in
                    Button { playback.watch(camera) } label: {
                        Label(camera.name, systemImage: "video")
                    }
                    .buttonStyle(.plain)
                }
            }
            #if DEBUG
            Button { playback.watchTestPattern() } label: {
                Label("Test (Apple)", systemImage: "waveform")
            }
            .buttonStyle(.plain)
            #endif
        }
    }

    // The inline player stays mounted the whole time a feed is active, so PiP
    // always has a layer to return to (pop in/out toggles smoothly).
    private var watchingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            InlinePlayerView(player: playback.player)
                .frame(width: 252, height: 142)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .center) {
                    if playback.isPoppedOut {
                        Label("Floating", systemImage: "pip")
                            .font(.caption).padding(6)
                            .background(.black.opacity(0.5), in: Capsule())
                    }
                }
            HStack {
                if playback.isPoppedOut {
                    Button { playback.popIn() } label: { Image(systemName: "pip.exit") }
                        .help("Pop in")
                } else {
                    Button { playback.popOut() } label: { Image(systemName: "pip.enter") }
                        .help("Pop out")
                }
                Button { playback.toggleMute() } label: {
                    Image(systemName: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .help(playback.isMuted ? "Unmute" : "Mute")
                Spacer()
                Button("Stop") { playback.stop() }
            }
        }
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
