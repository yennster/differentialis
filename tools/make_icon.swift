import AppKit

// Renders the Differentialis app icon: two overlapping translucent panes whose
// intersection is the "difference", on a dark squircle.

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Differentialis/Resources/Assets.xcassets/AppIcon.appiconset"

func draw(px: Int) -> Data {
    let size = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gctx
    let ctx = gctx.cgContext

    // Background squircle with a dark gradient.
    let inset = size * 0.06
    let bgRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: size * 0.2237, yRadius: size * 0.2237)
    bgPath.addClip()
    let bg = NSGradient(colors: [
        NSColor(srgbRed: 0.14, green: 0.10, blue: 0.24, alpha: 1),
        NSColor(srgbRed: 0.04, green: 0.03, blue: 0.07, alpha: 1),
    ])!
    bg.draw(in: bgRect, angle: -90)

    // Two overlapping rounded panes.
    let pane = size * 0.34
    let radius = size * 0.085
    let off = size * 0.072
    let center = CGPoint(x: size / 2, y: size / 2)

    func paneRect(dx: CGFloat, dy: CGFloat) -> CGRect {
        CGRect(x: center.x - pane / 2 + dx, y: center.y - pane / 2 + dy, width: pane, height: pane)
    }

    // Red pane (upper-left).
    ctx.setBlendMode(.normal)
    let red = NSBezierPath(roundedRect: paneRect(dx: -off, dy: off), xRadius: radius, yRadius: radius)
    NSColor(srgbRed: 0.96, green: 0.40, blue: 0.50, alpha: 0.95).setFill()
    red.fill()

    // Blue pane (lower-right), screen-blended so the overlap glows.
    ctx.setBlendMode(.screen)
    let blue = NSBezierPath(roundedRect: paneRect(dx: off, dy: -off), xRadius: radius, yRadius: radius)
    NSColor(srgbRed: 0.36, green: 0.78, blue: 0.98, alpha: 0.95).setFill()
    blue.fill()
    ctx.setBlendMode(.normal)

    // Soft top highlight.
    let glossRect = CGRect(x: inset, y: size * 0.55, width: size - inset * 2, height: size * 0.4)
    let gloss = NSGradient(colors: [
        NSColor(white: 1, alpha: 0.10), NSColor(white: 1, alpha: 0),
    ])!
    gloss.draw(in: glossRect, angle: -90)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, px) in sizes {
    let data = draw(px: px)
    let url = URL(fileURLWithPath: "\(outDir)/\(name).png")
    try! data.write(to: url)
}

let contents = """
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try! contents.write(toFile: "\(outDir)/Contents.json", atomically: true, encoding: .utf8)
print("Wrote \(sizes.count) icon images + Contents.json to \(outDir)")
