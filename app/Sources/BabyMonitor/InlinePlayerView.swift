import SwiftUI
import AppKit

/// Hosts the shared `AVPlayerLayer` from `PlayerController` inside the popover so
/// the feed plays inline. Re-attaches on each appearance.
struct InlinePlayerView: NSViewRepresentable {
    let player: PlayerController

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        player.attach(to: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        player.attach(to: view)
    }
}
