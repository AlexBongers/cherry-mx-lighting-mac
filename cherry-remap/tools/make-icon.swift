// Draws the app icon and writes Resources/AppIcon.icns.
// Run from the cherry-remap folder: swift tools/make-icon.swift
import AppKit

let size: CGFloat = 1024

func renderMaster() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext

    // macOS icon grid: 824 pt tile centred in 1024, soft drop shadow underneath.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    NSColor.black.setFill()
    tilePath.fill()
    ctx.restoreGState()

    ctx.saveGState()
    tilePath.addClip()

    // Dark background with a faint cool glow at the top.
    let bg = NSGradient(colors: [NSColor(red: 0.13, green: 0.14, blue: 0.20, alpha: 1),
                                 NSColor(red: 0.04, green: 0.04, blue: 0.08, alpha: 1)])!
    bg.draw(in: tile, angle: -90)

    // Keycap grid: three rows, the last one a spacebar.
    let key: CGFloat = 112, gap: CGFloat = 20
    let cols = 5
    let gridW = CGFloat(cols) * key + CGFloat(cols - 1) * gap
    let gridH = 3 * key + 2 * gap
    let x0 = tile.midX - gridW / 2
    let y0 = tile.midY - gridH / 2 + 6

    func color(_ hue: CGFloat, _ bright: CGFloat = 1) -> NSColor {
        NSColor(hue: hue.truncatingRemainder(dividingBy: 1), saturation: 0.82, brightness: bright, alpha: 1)
    }

    func drawKey(_ r: NSRect, hue: CGFloat) {
        let path = NSBezierPath(roundedRect: r, xRadius: 26, yRadius: 26)

        // Light bleeding out from under the keycap.
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 46, color: color(hue).withAlphaComponent(0.9).cgColor)
        color(hue, 0.9).setFill()
        path.fill()
        ctx.restoreGState()

        // Keycap face: lit colour at the edges, darker towards the centre of the cap.
        NSGradient(colors: [color(hue, 1.0), color(hue + 0.03, 0.62)])!.draw(in: path, angle: -90)

        let inner = NSBezierPath(roundedRect: r.insetBy(dx: 14, dy: 14), xRadius: 16, yRadius: 16)
        NSGradient(colors: [NSColor(red: 0.16, green: 0.17, blue: 0.24, alpha: 1),
                            NSColor(red: 0.08, green: 0.08, blue: 0.13, alpha: 1)])!.draw(in: inner, angle: -90)

        // Top highlight.
        let hl = NSBezierPath(roundedRect: NSRect(x: r.minX + 22, y: r.maxY - 30, width: r.width - 44, height: 8), xRadius: 4, yRadius: 4)
        NSColor.white.withAlphaComponent(0.16).setFill()
        hl.fill()
    }

    // Rows are drawn top to bottom; hue runs left to right like the Wave effect, shifted per row.
    for row in 0..<2 {
        for col in 0..<cols {
            let y = y0 + gridH - key - CGFloat(row) * (key + gap)
            let r = NSRect(x: x0 + CGFloat(col) * (key + gap), y: y, width: key, height: key)
            drawKey(r, hue: 0.0 + CGFloat(col) * 0.17 + CGFloat(row) * 0.05)
        }
    }
    let space = NSRect(x: x0 + (key + gap), y: y0, width: gridW - 2 * (key + gap), height: key)
    drawKey(space, hue: 0.55)

    // Subtle top sheen over the whole tile.
    let sheen = NSGradient(colors: [NSColor.white.withAlphaComponent(0.10), NSColor.white.withAlphaComponent(0)])!
    sheen.draw(in: NSRect(x: tile.minX, y: tile.midY + 120, width: tile.width, height: tile.height / 2 - 120), angle: -90)

    ctx.restoreGState()

    // Thin rim so the tile reads on light backgrounds.
    NSColor.white.withAlphaComponent(0.10).setStroke()
    tilePath.lineWidth = 3
    tilePath.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func png(_ rep: NSBitmapImageRep, pixels: Int) -> Data {
    let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: out)!
    NSGraphicsContext.current = gc
    gc.imageInterpolation = .high
    rep.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return out.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = "build/AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let master = renderMaster()
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sizes {
    try png(master, pixels: px).write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
}
try png(master, pixels: 1024).write(to: URL(fileURLWithPath: "build/AppIcon-1024.png"))
print("iconset written")
