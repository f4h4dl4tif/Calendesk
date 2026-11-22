import AppKit
// Renders a tear-off calendar page icon to the given PNG path at 1024px.
let out = CommandLine.arguments[1]
let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
    let bg = NSBezierPath(roundedRect: r.insetBy(dx: 90, dy: 90), xRadius: 190, yRadius: 190)
    NSGradient(starting: NSColor(calibratedWhite: 0.20, alpha: 1), ending: NSColor(calibratedWhite: 0.07, alpha: 1))!.draw(in: bg, angle: -90)

    let page = NSRect(x: 220, y: 200, width: 584, height: 600)
    NSGraphicsContext.current?.saveGraphicsState()
    NSBezierPath(roundedRect: page, xRadius: 70, yRadius: 70).addClip()
    NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
    page.fill()
    let band = NSRect(x: page.minX, y: page.maxY - 150, width: page.width, height: 150)
    NSColor(calibratedRed: 1, green: 0.27, blue: 0.23, alpha: 1).setFill()
    band.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    func rounded(_ s: CGFloat, _ w: NSFont.Weight) -> NSFont {
        let f = NSFont.systemFont(ofSize: s, weight: w)
        return NSFont(descriptor: f.fontDescriptor.withDesign(.rounded) ?? f.fontDescriptor, size: s) ?? f
    }
    func draw(_ t: String, _ font: NSFont, _ color: NSColor, centerY: CGFloat, kern: CGFloat = 0) {
        let s = NSAttributedString(string: t, attributes: [.font: font, .foregroundColor: color, .kern: kern])
        let sz = s.size()
        s.draw(at: NSPoint(x: size / 2 - sz.width / 2, y: centerY - sz.height / 2))
    }
    draw("CAL", rounded(96, .heavy), .white, centerY: band.midY, kern: 14)
    draw("20", rounded(330, .bold), NSColor(calibratedWhite: 0.11, alpha: 1), centerY: page.minY + 230)

    // Binder rings
    for x in [380.0, 644.0] {
        let ring = NSBezierPath(roundedRect: NSRect(x: x - 24, y: page.maxY - 50, width: 48, height: 110), xRadius: 24, yRadius: 24)
        NSColor(calibratedWhite: 0.85, alpha: 1).setFill(); ring.fill()
        NSColor(calibratedWhite: 0.55, alpha: 1).setStroke(); ring.lineWidth = 6; ring.stroke()
    }
    return true
}
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
