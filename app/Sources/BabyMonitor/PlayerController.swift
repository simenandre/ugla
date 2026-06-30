import AppKit
import AVFoundation
import AVKit

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

    override init() {
        super.init()
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
    }

    /// Host the shared player layer inside `container` (the inline popover view).
    func attach(to container: NSView) {
        container.wantsLayer = true
        if playerLayer.superlayer !== container.layer {
            playerLayer.removeFromSuperlayer()
            container.layer?.addSublayer(playerLayer)
        }
        playerLayer.frame = container.bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        ensurePiPController()
    }

    func play(url: URL) {
        precondition(url.scheme?.hasPrefix("http") == true, "expected an http HLS URL")
        Diag.log("play url=\(url.absoluteString)")
        let item = AVPlayerItem(url: url)
        observe(item)
        player.replaceCurrentItem(with: item)
        player.isMuted = false
        player.play()
        ensurePiPController()
    }

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

    func stop() {
        if pip?.isPictureInPictureActive == true { pip?.stopPictureInPicture() }
        player.pause()
        player.replaceCurrentItem(with: nil)
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

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error) {
        Diag.log("PiP FAILED: \(error.localizedDescription)")
    }
}
