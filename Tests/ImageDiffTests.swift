import Testing
import AppKit
import CoreGraphics
@testable import Differentialis

/// `ImageDiffRenderer` works in pixel space on a top-left-aligned canvas (issue #18).
@Suite("Image difference alignment")
struct ImageDiffTests {
    private struct RGBA: Equatable { var r, g, b, a: UInt8 }

    /// A deterministic, non-uniform bitmap so any misalignment produces visible differences.
    /// Rows `0..<patternHeight` (top-down) hold the pattern; any extra rows/columns are white.
    private func makeImage(width: Int, height: Int, patternWidth: Int, patternHeight: Int) -> CGImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<min(height, patternHeight) {
            for x in 0..<min(width, patternWidth) {
                let i = (y * width + x) * 4
                pixels[i] = UInt8((x * 37 + y * 11) % 256)
                pixels[i + 1] = UInt8((x * 5 + y * 53) % 256)
                pixels[i + 2] = UInt8((x * y + 17) % 256)
                pixels[i + 3] = 255
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// Reads `image` back as top-down RGBA8 rows.
    private func pixels(of image: CGImage) -> [[RGBA]] {
        let w = image.width, h = image.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        buffer.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (0..<h).map { y in
            (0..<w).map { x in
                let i = (y * w + x) * 4
                return RGBA(r: buffer[i], g: buffer[i + 1], b: buffer[i + 2], a: buffer[i + 3])
            }
        }
    }

    private func isBlack(_ p: RGBA) -> Bool { p.r <= 1 && p.g <= 1 && p.b <= 1 }

    @Test("Padding at the bottom differs only in the padded strip")
    func bottomPadding() throws {
        let a = makeImage(width: 40, height: 30, patternWidth: 40, patternHeight: 30)
        let b = makeImage(width: 40, height: 32, patternWidth: 40, patternHeight: 30)
        let diff = try #require(ImageDiffRenderer.difference(a, b, amplify: false))
        #expect(diff.width == 40)
        #expect(diff.height == 32)

        let rows = pixels(of: diff)
        for y in 0..<30 {
            for x in 0..<40 {
                #expect(isBlack(rows[y][x]), "overlap pixel (\(x), \(y)) should match: \(rows[y][x])")
            }
        }
        for y in 30..<32 {
            for x in 0..<40 {
                #expect(!isBlack(rows[y][x]) && rows[y][x].a == 255,
                        "padded pixel (\(x), \(y)) should be hatched: \(rows[y][x])")
            }
        }
    }

    @Test("Padding on the right (and argument order) is handled the same way")
    func rightPadding() throws {
        let wide = makeImage(width: 45, height: 30, patternWidth: 40, patternHeight: 30)
        let narrow = makeImage(width: 40, height: 30, patternWidth: 40, patternHeight: 30)
        let diff = try #require(ImageDiffRenderer.difference(wide, narrow, amplify: false))
        #expect(diff.width == 45)
        #expect(diff.height == 30)

        let rows = pixels(of: diff)
        for y in 0..<30 {
            for x in 0..<40 { #expect(isBlack(rows[y][x])) }
            for x in 40..<45 { #expect(!isBlack(rows[y][x])) }
        }
    }

    @Test("An image both wider and taller hatches the right and bottom strips")
    func widerAndTaller() throws {
        let big = makeImage(width: 30, height: 25, patternWidth: 20, patternHeight: 20)
        let small = makeImage(width: 20, height: 20, patternWidth: 20, patternHeight: 20)
        let diff = try #require(ImageDiffRenderer.difference(small, big, amplify: false))
        #expect(diff.width == 30 && diff.height == 25)
        let rows = pixels(of: diff)
        for y in 0..<25 {
            for x in 0..<30 {
                let inOverlap = x < 20 && y < 20
                #expect(isBlack(rows[y][x]) == inOverlap, "pixel (\(x), \(y)): \(rows[y][x])")
            }
        }
    }

    @Test("The amplified (on-screen) path keeps the canvas size and highlights real changes")
    func amplified() throws {
        let a = makeImage(width: 20, height: 20, patternWidth: 20, patternHeight: 20)
        let b = makeImage(width: 20, height: 20, patternWidth: 20, patternHeight: 10) // bottom half white
        let diff = try #require(ImageDiffRenderer.difference(a, b, amplify: true))
        #expect(diff.width == 20 && diff.height == 20)
        let rows = pixels(of: diff)
        func brightness(_ p: RGBA) -> Int { Int(p.r) + Int(p.g) + Int(p.b) }
        let unchanged = rows[0..<10].joined().map(brightness).max() ?? 0
        let changed = rows[10..<20].joined().map(brightness).reduce(0, +) / 200
        #expect(changed > unchanged, "changed rows should glow brighter than matching rows")
    }

    @Test("Identical images of the same size produce no difference and no hatch")
    func identicalImages() throws {
        let a = makeImage(width: 20, height: 20, patternWidth: 20, patternHeight: 20)
        let diff = try #require(ImageDiffRenderer.difference(a, a, amplify: false))
        #expect(pixels(of: diff).joined().allSatisfy(isBlack))
    }

    @Test("A 2x (144 dpi) image and a 1x image with the same pixels compare one-to-one")
    func mixedResolution() throws {
        let cg = makeImage(width: 24, height: 16, patternWidth: 24, patternHeight: 16)

        let retinaRep = NSBitmapImageRep(cgImage: cg)
        retinaRep.size = NSSize(width: 12, height: 8)   // 144 dpi: half as many points as pixels
        let retina = NSImage(size: retinaRep.size)
        retina.addRepresentation(retinaRep)
        let standard = NSImage(cgImage: cg, size: NSSize(width: 24, height: 16))

        #expect(retina.pixelSize == CGSize(width: 24, height: 16))
        let decoded = try #require(ImageDiffRenderer.cgImage(from: retina))
        #expect(decoded.width == 24 && decoded.height == 16)

        let diff = try #require(ImageDiffRenderer.difference(retina, standard, amplify: false))
        #expect(diff.pixelSize == CGSize(width: 24, height: 16))
        let rendered = try #require(ImageDiffRenderer.cgImage(from: diff))
        #expect(pixels(of: rendered).joined().allSatisfy(isBlack))
    }

    @Test("Uncovered canvas regions are the right strip and the strip under the overlap")
    func uncoveredRects() {
        let canvas = CGRect(x: 0, y: 0, width: 100, height: 80)
        // Overlap 60×50 pinned top-left (Core Image coordinates: bottom-left origin).
        let overlap = CGRect(x: 0, y: 30, width: 60, height: 50)
        let rects = ImageDiffRenderer.uncoveredRects(canvas: canvas, overlap: overlap)
        #expect(rects == [CGRect(x: 60, y: 0, width: 40, height: 80),
                          CGRect(x: 0, y: 0, width: 60, height: 30)])
        #expect(ImageDiffRenderer.uncoveredRects(canvas: canvas, overlap: canvas).isEmpty)
    }
}
