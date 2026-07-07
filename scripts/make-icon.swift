import AppKit

// Draws the Ugla owl app icon at 1024×1024 and writes a PNG to argv[1].
// A flat, friendly owl on a dark rounded-rect (night-owl theme).

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let S: CGFloat = 1024

let image = NSImage(size: NSSize(width: S, height: S))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no ctx") }

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a)
}

// Background: rounded rect with a vertical gradient.
let margin: CGFloat = S * 0.055
let bgRect = NSRect(x: margin, y: margin, width: S - 2*margin, height: S - 2*margin)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: (S - 2*margin) * 0.235,
                          yRadius: (S - 2*margin) * 0.235)
ctx.saveGState()
bgPath.addClip()
let grad = NSGradient(colors: [color(58, 74, 120), color(24, 30, 54)])!
grad.draw(in: bgRect, angle: -90)
ctx.restoreGState()

let cx = S / 2

// Ear tufts (behind the body).
let cream = color(240, 234, 220)
func tuft(_ x: CGFloat) {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: x, y: 760))
    p.line(to: NSPoint(x: x - 70, y: 620))
    p.line(to: NSPoint(x: x + 70, y: 620))
    p.close()
    cream.setFill(); p.fill()
}
tuft(cx - 150)
tuft(cx + 150)

// Body: a rounded egg shape.
let body = NSBezierPath(roundedRect: NSRect(x: cx - 280, y: 200, width: 560, height: 500),
                        xRadius: 270, yRadius: 260)
cream.setFill(); body.fill()

// Belly highlight (slightly lighter).
let belly = NSBezierPath(ovalIn: NSRect(x: cx - 150, y: 220, width: 300, height: 380))
color(250, 246, 238).setFill(); belly.fill()

// Wings (soft grey), tucked at the sides.
let wing = color(210, 202, 186)
for sign: CGFloat in [-1, 1] {
    let w = NSBezierPath(ovalIn: NSRect(x: cx + sign * 175 - 70, y: 250, width: 140, height: 320))
    wing.setFill(); w.fill()
}

// Eyes: big white discs with amber irises, dark pupils, catchlight.
func eye(_ x: CGFloat) {
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: x - 115, y: 470, width: 230, height: 230)).fill()
    color(240, 168, 54).setFill()
    NSBezierPath(ovalIn: NSRect(x: x - 78, y: 507, width: 156, height: 156)).fill()
    color(28, 28, 36).setFill()
    NSBezierPath(ovalIn: NSRect(x: x - 46, y: 539, width: 92, height: 92)).fill()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: x - 8, y: 592, width: 34, height: 34)).fill()
}
eye(cx - 128)
eye(cx + 128)

// Beak: small downward orange triangle between the eyes.
let beak = NSBezierPath()
beak.move(to: NSPoint(x: cx - 42, y: 505))
beak.line(to: NSPoint(x: cx + 42, y: 505))
beak.line(to: NSPoint(x: cx, y: 430))
beak.close()
color(240, 140, 46).setFill(); beak.fill()

// Feet: two little orange feet at the bottom.
for sign: CGFloat in [-1, 1] {
    let f = NSBezierPath(roundedRect: NSRect(x: cx + sign * 90 - 34, y: 168, width: 68, height: 54),
                         xRadius: 22, yRadius: 22)
    color(240, 140, 46).setFill(); f.fill()
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { fatalError("encode") }
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
