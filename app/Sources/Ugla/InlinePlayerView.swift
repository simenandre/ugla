import SwiftUI
import AppKit

/// Hosts the shared `AVPlayerLayer` from `PlayerController` inside the popover
/// (via a zoomable view) so the feed plays inline. Re-attaches on each update.
struct InlinePlayerView: NSViewRepresentable {
    let player: PlayerController

    func makeNSView(context: Context) -> ZoomablePlayerView {
        let view = ZoomablePlayerView(playerLayer: player.playerLayer)
        player.attach(to: view)
        view.mountLayer()
        return view
    }

    func updateNSView(_ view: ZoomablePlayerView, context: Context) {
        player.attach(to: view)
        view.mountLayer()
    }
}
