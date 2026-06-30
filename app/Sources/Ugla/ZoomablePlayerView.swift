import AppKit
import AVKit
import UglaCore

/// Hosts the shared `AVPlayerLayer` and adds digital zoom: scroll or pinch to
/// zoom, drag to pan, double-click to reset. Zoom scales the layer within the
/// clipped view (the decoded picture, so it works on any camera).
final class ZoomablePlayerView: NSView {
    private let playerLayer: AVPlayerLayer
    private let maxZoom: CGFloat = 6
    private var zoom: CGFloat = 1
    private var pan: CGPoint = .zero
    private var dragOrigin: CGPoint?

    init(playerLayer: AVPlayerLayer) {
        self.playerLayer = playerLayer
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Ensure the shared layer is our sublayer and laid out for the current zoom.
    func mountLayer() {
        if playerLayer.superlayer !== layer {
            playerLayer.removeFromSuperlayer()
            layer?.addSublayer(playerLayer)
        }
        playerLayer.autoresizingMask = []
        relayout()
    }

    override func layout() {
        super.layout()
        relayout()
    }

    private func relayout() {
        let area = bounds
        guard area.width > 0, area.height > 0 else { return }
        let width = area.width * zoom
        let height = area.height * zoom
        let maxX = max(0, (width - area.width) / 2)
        let maxY = max(0, (height - area.height) / 2)
        pan.x = min(maxX, max(-maxX, pan.x))
        pan.y = min(maxY, max(-maxY, pan.y))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = CGRect(x: (area.width - width) / 2 + pan.x,
                                   y: (area.height - height) / 2 + pan.y,
                                   width: width, height: height)
        CATransaction.commit()
    }

    private func setZoom(_ value: CGFloat) {
        let clamped = min(maxZoom, max(1, value))
        guard clamped != zoom else { return }
        zoom = clamped
        if zoom == 1 { pan = .zero }
        relayout()
    }

    override func scrollWheel(with event: NSEvent) {
        setZoom(zoom * (1 + event.scrollingDeltaY * 0.01))
    }

    override func magnify(with event: NSEvent) {
        setZoom(zoom * (1 + event.magnification))
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard zoom > 1, let origin = dragOrigin else { return }
        let point = convert(event.locationInWindow, from: nil)
        pan.x += point.x - origin.x
        pan.y += point.y - origin.y
        dragOrigin = point
        relayout()
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
        if event.clickCount == 2 { resetZoom() }  // double-click resets
    }

    func resetZoom() {
        zoom = 1
        pan = .zero
        relayout()
    }

    /// The current zoom as a stream crop region (nil when not zoomed). `px`/`py`
    /// are the normalized pan position so the same view can be baked into ffmpeg.
    func currentCrop() -> CropRegion? {
        guard zoom > 1.01 else { return nil }
        let maxX = bounds.width * (zoom - 1) / 2
        let maxY = bounds.height * (zoom - 1) / 2
        let px = maxX > 0 ? (0.5 - pan.x / (2 * maxX)) : 0.5
        // AppKit y is bottom-up; video crop y is top-down, hence the +.
        let py = maxY > 0 ? (0.5 + pan.y / (2 * maxY)) : 0.5
        return CropRegion(zoom: Double(zoom), px: Double(px), py: Double(py))
    }
}
