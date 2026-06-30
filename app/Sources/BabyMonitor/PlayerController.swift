import AppKit
import AVFoundation
import AVKit

/// Plays an HLS URL and presents it as a native macOS Picture-in-Picture window.
/// macOS PiP requires an `AVPlayerLayer` inside an on-screen window, so we host
/// the layer in a fully transparent, click-through window — PiP is the only
/// thing the user actually sees.
@MainActor
final class PlayerController: NSObject, AVPictureInPictureControllerDelegate {
    private let player = AVPlayer()
    private let playerLayer = AVPlayerLayer()
    private var hostWindow: NSWindow?
    private var pip: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?
    private var startWhenPossible = false

    override init() {
        super.init()
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
    }

    /// Start playback and (optionally) pop into PiP as soon as it is possible.
    func play(url: URL, autoPiP: Bool) {
        precondition(url.scheme?.hasPrefix("http") == true, "expected an http HLS URL")
        ensureHostWindow()
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.isMuted = false
        player.play()
        startWhenPossible = autoPiP
        ensurePiPController()
        assert(pip != nil || !AVPictureInPictureController.isPictureInPictureSupported(),
               "PiP controller should exist where supported")
    }

    /// Toggle PiP in response to a user action.
    func togglePiP() {
        guard let pip else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else if pip.isPictureInPicturePossible {
            pip.startPictureInPicture()
        } else {
            startWhenPossible = true   // start as soon as it becomes possible
        }
    }

    func stop() {
        if pip?.isPictureInPictureActive == true { pip?.stopPictureInPicture() }
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func ensureHostWindow() {
        guard hostWindow == nil else { return }
        let frame = NSRect(x: 0, y: 0, width: 480, height: 270)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.alphaValue = 0            // invisible host; never shown to the user
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        let view = NSView(frame: frame)
        view.wantsLayer = true
        playerLayer.frame = view.bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(playerLayer)
        window.contentView = view
        window.orderFrontRegardless()    // must be on-screen for PiP to be possible
        hostWindow = window
        assert(hostWindow?.contentView?.layer != nil, "host must be layer-backed")
    }

    private func ensurePiPController() {
        guard pip == nil, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        guard let controller = AVPictureInPictureController(playerLayer: playerLayer) else { return }
        controller.delegate = self
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.new]) {
            [weak self] controller, _ in
            DispatchQueue.main.async {
                guard let self, self.startWhenPossible, controller.isPictureInPicturePossible else { return }
                self.startWhenPossible = false
                controller.startPictureInPicture()
            }
        }
        pip = controller
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error) {
        NSLog("[BabyMonitor] PiP failed to start: \(error.localizedDescription)")
    }
}
