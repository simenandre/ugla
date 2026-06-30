import AppKit
import AVFoundation
import AVKit
import BabyMonitorCore

/// Plays an HLS URL into an `AVPlayerLayer` that is hosted inline (in the
/// popover) and can pop out into a native Picture-in-Picture window. Hosting the
/// layer in the on-screen popover means PiP animates naturally from there.
@MainActor
final class PlayerController: NSObject, AVPictureInPictureControllerDelegate {
    private let player = AVPlayer()
    let playerLayer = AVPlayerLayer()
    private var pip: AVPictureInPictureController?
    private var statusObservation: NSKeyValueObservation?
    private var possibleObservation: NSKeyValueObservation?
    private var startWhenPossible = false
    /// Notified (on main) when PiP starts/stops so the UI can track it.
    var onPiPActiveChange: ((Bool) -> Void)?
    /// The zoom view currently hosting the layer (for reading/resetting zoom).
    private weak var zoomView: ZoomablePlayerView?

    override init() {
        super.init()
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
    }

    /// Host the shared player layer inside `container` (the inline popover view).
    /// The container (a ZoomablePlayerView) owns the layer's frame/zoom.
    func attach(to container: NSView) {
        container.wantsLayer = true
        if playerLayer.superlayer !== container.layer {
            playerLayer.removeFromSuperlayer()
            container.layer?.addSublayer(playerLayer)
        }
        zoomView = container as? ZoomablePlayerView
        ensurePiPController()
    }

    /// The current inline zoom expressed as a stream crop region (nil if 1x).
    func currentCrop() -> CropRegion? { zoomView?.currentCrop() }

    /// Reset the inline zoom to fit (used after baking zoom into the stream).
    func resetInlineZoom() { zoomView?.resetZoom() }

    func play(url: URL) {
        precondition(url.scheme?.hasPrefix("http") == true, "expected an http HLS URL")
        Diag.log("play url=\(url.absoluteString)")
        let item = AVPlayerItem(url: url)
        observe(item)
        player.replaceCurrentItem(with: item)
        player.play()
        ensurePiPController()
    }

    func setMuted(_ muted: Bool) { player.isMuted = muted }

    /// Start PiP in response to the user clicking "Pop out".
    func popOut() {
        ensurePiPController()
        guard let pip else { Diag.log("popOut: no PiP controller"); return }
        if pip.isPictureInPicturePossible {
            Diag.log("popOut: starting")
            pip.startPictureInPicture()
        } else {
            startWhenPossible = true
            Diag.log("popOut: not yet possible, will start when ready")
        }
    }

    var isPiPActive: Bool { pip?.isPictureInPictureActive ?? false }

    /// Exit PiP but keep playing (returns to inline preview).
    func endPiP() {
        if pip?.isPictureInPictureActive == true { pip?.stopPictureInPicture() }
    }

    func stop() {
        // Tear playback down first so nothing keeps playing once PiP closes.
        player.pause()
        player.replaceCurrentItem(with: nil)
        if pip?.isPictureInPictureActive == true { pip?.stopPictureInPicture() }
        startWhenPossible = false
    }

    private func observe(_ item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.new]) { item, _ in
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay: Diag.log("item readyToPlay")
                case .failed:
                    let ns = item.error as NSError?
                    Diag.log("item FAILED: \(ns?.domain ?? "?") \(ns?.code ?? 0)")
                    for event in item.errorLog()?.events ?? [] {
                        Diag.log("  errlog status=\(event.errorStatusCode) uri=\(event.uri ?? "?") comment=\(event.errorComment ?? "?")")
                    }
                default: break
                }
            }
        }
    }

    private func ensurePiPController() {
        guard pip == nil, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        guard let controller = AVPictureInPictureController(playerLayer: playerLayer) else {
            Diag.log("failed to create AVPictureInPictureController"); return
        }
        controller.delegate = self
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.new]) {
            controller, _ in
            DispatchQueue.main.async {
                guard self.startWhenPossible, controller.isPictureInPicturePossible else { return }
                self.startWhenPossible = false
                Diag.log("starting PiP (deferred)")
                controller.startPictureInPicture()
            }
        }
        pip = controller
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) {
        DispatchQueue.main.async { self.onPiPActiveChange?(true) }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        DispatchQueue.main.async { self.onPiPActiveChange?(false) }
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completion: @escaping (Bool) -> Void) {
        completion(true)  // app UI is the menubar popover; nothing to restore
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error) {
        Diag.log("PiP FAILED: \(error.localizedDescription)")
    }
}
