// Draws the MacTerm+ app icon into an .iconset folder. Usage: swift scripts/make-icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func c(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Squircle with a vivid multi-color gradient (cyan → violet → coral).
    let inset = s * 0.09
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: s * 0.2, yRadius: s * 0.2)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = c(0x000000, 0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.shadowBlurRadius = s * 0.03
    shadow.set()
    c(0x000000).setFill(); tilePath.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGradient(colors: [c(0x12C2E9), c(0x6A5CFF), c(0xC471ED), c(0xF64F59)],
               atLocations: [0, 0.38, 0.68, 1], colorSpace: .sRGB)!.draw(in: tilePath, angle: -45)
    // Soft gloss on the top half.
    NSGradient(colors: [c(0xFFFFFF, 0.28), c(0xFFFFFF, 0)])!
        .draw(in: NSBezierPath(roundedRect: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2),
                               xRadius: s * 0.2, yRadius: s * 0.2), angle: -90)

    // Dark terminal window.
    let win = NSRect(x: s * 0.2, y: s * 0.24, width: s * 0.6, height: s * 0.48)
    let winPath = NSBezierPath(roundedRect: win, xRadius: s * 0.055, yRadius: s * 0.055)
    c(0x0E1220, 0.92).setFill(); winPath.fill()
    c(0xFFFFFF, 0.18).setStroke(); winPath.lineWidth = max(1, s * 0.006); winPath.stroke()
    // Traffic lights.
    for (i, col) in [c(0xFF5F57), c(0xFEBC2E), c(0x28C840)].enumerated() {
        let d = s * 0.04
        col.setFill()
        NSBezierPath(ovalIn: NSRect(x: win.minX + s * 0.04 + CGFloat(i) * d * 1.45, y: win.maxY - s * 0.07, width: d, height: d)).fill()
    }
    // Prompt chevron (green) and cursor (yellow).
    let chevron = NSBezierPath()
    chevron.lineWidth = s * 0.05
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    chevron.move(to: NSPoint(x: s * 0.29, y: s * 0.53))
    chevron.line(to: NSPoint(x: s * 0.38, y: s * 0.45))
    chevron.line(to: NSPoint(x: s * 0.29, y: s * 0.37))
    c(0x3DFFA2).setStroke(); chevron.stroke()
    c(0xFFD84D).setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.43, y: s * 0.345, width: s * 0.14, height: s * 0.045),
                 xRadius: s * 0.015, yRadius: s * 0.015).fill()

    // "+" badge (orange circle) at the top-right.
    let badge = NSRect(x: s * 0.62, y: s * 0.6, width: s * 0.22, height: s * 0.22)
    NSGradient(colors: [c(0xFFB347), c(0xFF6A3D)])!.draw(in: NSBezierPath(ovalIn: badge), angle: -90)
    c(0xFFFFFF, 0.9).setStroke()
    let ring = NSBezierPath(ovalIn: badge.insetBy(dx: s * 0.004, dy: s * 0.004)); ring.lineWidth = s * 0.008; ring.stroke()
    let plus = NSBezierPath()
    plus.lineWidth = s * 0.035
    plus.lineCapStyle = .round
    plus.move(to: NSPoint(x: badge.midX, y: badge.minY + s * 0.055)); plus.line(to: NSPoint(x: badge.midX, y: badge.maxY - s * 0.055))
    plus.move(to: NSPoint(x: badge.minX + s * 0.055, y: badge.midY)); plus.line(to: NSPoint(x: badge.maxX - s * 0.055, y: badge.midY))
    c(0xFFFFFF).setStroke(); plus.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
