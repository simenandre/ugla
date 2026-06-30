import AppKit
import AVFoundation
import AVKit

/// Plays an HLS URL and presents it as a native macOS Picture-in-Picture window.
/// macOS PiP requires an `AVPlayerLayer` inside an on-screen window, so we host
/// the layer in a transparent (alpha 0), click-through window — PiP is the only
/// thing the user actually sees.
@MainActor
final class PlayerController: NSObject, AVPictureInPictureControllerDelegate {
    private let player = AVPlayer()
    private let playerLayer = AVPlayerLayer()
    private var hostWindow: NSWindow?
    private var pip: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?
    private var startWhenPossible = false

    override init() {
        super.init()
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
    }

    /// Start playback and (optionally) pop into PiP as soon as it is possible.
    func play(url: URL, autoPiP: Bool) {
        precondition(url.scheme?.hasPrefix("http") == true, "expected an http HLS URL")
        Diag.log("play url=\(url.absoluteString) autoPiP=\(autoPiP)")
        ensureHostWindow()
        let item = AVPlayerItem(url: url)
        observe(item)
        player.replaceCurrentItem(with: item)
        player.isMuted = false
        player.play()
        startWhenPossible = autoPiP
        ensurePiPController()
    }

    /// Toggle PiP in response to a user action.
    func togglePiP() {
        guard let pip else { Diag.log("togglePiP: no controller"); return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else if pip.isPictureInPicturePossible {
            Diag.log("togglePiP: starting")
            pip.startPictureInPicture()
        } else {
            startWhenPossible = true
            Diag.log("togglePiP: not yet possible, will start when ready")
        }
    }

    func stop() {
        if pip?.isPictureInPictureActive == true { pip?.stopPictureInPicture() }
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func observe(_ item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.new]) { item, _ in
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay: Diag.log("item readyToPlay")
                case .failed: Diag.log("item FAILED: \(item.error?.localizedDescription ?? "?")")
                default: Diag.log("item status=unknown")
                }
            }
        }
    }

    private func ensureHostWindow() {
        guard hostWindow == nil else { return }
        let frame = NSRect(x: 0, y: 0, width: 480, height: 270)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.alphaValue = 0            // invisible host; PiP is the visible surface
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        let view = NSView(frame: frame)
        view.wantsLayer = true
        playerLayer.frame = view.bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(playerLayer)
        window.contentView = view
        window.orderFrontRegardless()    // on-screen (rendered) so PiP is possible
        hostWindow = window
        assert(hostWindow?.contentView?.layer != nil, "host must be layer-backed")
    }

    private func ensurePiPController() {
        let supported = AVPictureInPictureController.isPictureInPictureSupported()
        Diag.log("PiP supported=\(supported)")
        guard pip == nil, supported else { return }
        guard let controller = AVPictureInPictureController(playerLayer: playerLayer) else {
            Diag.log("failed to create AVPictureInPictureController"); return
        }
        controller.delegate = self
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.new]) {
            controller, _ in
            DispatchQueue.main.async {
                Diag.log("isPictureInPicturePossible=\(controller.isPictureInPicturePossible)")
                guard self.startWhenPossible, controller.isPictureInPicturePossible else { return }
                self.startWhenPossible = false
                Diag.log("starting PiP")
                controller.startPictureInPicture()
            }
        }
        pip = controller
    }

    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ c: AVPictureInPictureController) {
        Diag.log("PiP willStart")
    }
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) {
        Diag.log("PiP didStart")
    }
    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error) {
        Diag.log("PiP FAILED: \(error.localizedDescription)")
    }
}
