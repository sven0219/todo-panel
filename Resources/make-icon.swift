import AppKit

// 生成 AppIcon.iconset（各尺寸 PNG），用法：swift make-icon.swift <输出目录>
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

for s in sizes {
    let size = CGFloat(s.px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: s.px, pixelsHigh: s.px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(x: 0, y: 0, width: size, height: size)

    let bg = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.02, dy: size * 0.02),
                          xRadius: size * 0.22, yRadius: size * 0.22)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.58, blue: 1.00, alpha: 1),
        NSColor(calibratedRed: 0.04, green: 0.42, blue: 0.90, alpha: 1),
    ])!
    gradient.draw(in: bg, angle: -90)

    let ring = NSBezierPath(ovalIn: rect.insetBy(dx: size * 0.30, dy: size * 0.30))
    NSColor.white.withAlphaComponent(0.95).setStroke()
    ring.lineWidth = size * 0.055
    ring.stroke()

    let check = NSBezierPath()
    check.move(to: NSPoint(x: size * 0.38, y: size * 0.52))
    check.line(to: NSPoint(x: size * 0.47, y: size * 0.61))
    check.line(to: NSPoint(x: size * 0.65, y: size * 0.40))
    check.lineWidth = size * 0.075
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    NSColor.white.setStroke()
    check.stroke()

    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(s.name).png"))
    print("wrote \(s.name).png (\(s.px)px)")
}
