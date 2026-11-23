import Testing
import AppKit
import SwiftUI
@testable import Differentialis

/// Split and One-Up lay A and B out on one top-left-aligned canvas with a shared fit factor, the
/// same way Difference does (issue #50).
@Suite("Image alignment in Split and One-Up")
struct ImageAlignmentTests {
    private struct RGBA: Equatable { var r, g, b, a: UInt8 }

    /// A deterministic, non-uniform bitmap; rows `0..<patternHeight` repeat between images.
    private func makeImage(width: Int, height: Int) -> NSImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                pixels[i] = UInt8((x * 37 + y * 11) % 256)
                pixels[i + 1] = UInt8((x * 5 + y * 53) % 256)
                pixels[i + 2] = UInt8((x * y + 17) % 256)
                pixels[i + 3] = 255
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                         bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                         provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
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

    @MainActor
    private func render(_ image: NSImage, layout: AlignedCanvasLayout, viewSize: CGSize) throws -> [[RGBA]] {
        let renderer = ImageRenderer(content: AlignedImageLayer(image: image, layout: layout,
                                                                zoom: ZoomPanState(), viewSize: viewSize))
        renderer.scale = 1
        let cg = try #require(renderer.cgImage)
        #expect(cg.width == Int(viewSize.width) && cg.height == Int(viewSize.height))
        return pixels(of: cg)
    }

    @Test("The canvas is the largest width and height, fit with one scale")
    func canvasAndScale() {
        let layout = AlignedCanvasLayout([CGSize(width: 40, height: 30), CGSize(width: 50, height: 20)])
        #expect(layout.canvas == CGSize(width: 50, height: 30))
        #expect(layout.fitScale(in: CGSize(width: 100, height: 300)) == 2)
        #expect(layout.fitScale(in: CGSize(width: 500, height: 60)) == 2)
        #expect(layout.fitScale(in: .zero) == 0)
        #expect(AlignedCanvasLayout([]).fitScale(in: CGSize(width: 10, height: 10)) == 0)
    }

    @Test("Uncovered regions are the right strip and the strip under the image, top-down")
    func uncoveredRects() {
        let layout = AlignedCanvasLayout([CGSize(width: 100, height: 80), CGSize(width: 60, height: 50)])
        #expect(layout.uncoveredRects(for: CGSize(width: 100, height: 80)).isEmpty)
        #expect(layout.uncoveredRects(for: CGSize(width: 60, height: 50)) ==
                [CGRect(x: 60, y: 0, width: 40, height: 80), CGRect(x: 0, y: 50, width: 60, height: 30)])
        #expect(layout.uncoveredRects(for: CGSize(width: 100, height: 50)) ==
                [CGRect(x: 0, y: 50, width: 100, height: 30)])
        #expect(layout.uncoveredRects(for: .zero) == [CGRect(x: 0, y: 0, width: 100, height: 80)])

        // Same regions Difference hatches, once Core Image's bottom-up rects are flipped.
        let canvas = CGRect(origin: .zero, size: layout.canvas)
        let flipped = ImageDiffRenderer.uncoveredRects(canvas: canvas, overlap: CGRect(x: 0, y: 30, width: 60, height: 50))
            .map { CGRect(x: $0.minX, y: canvas.height - $0.maxY, width: $0.width, height: $0.height) }
        #expect(flipped == layout.uncoveredRects(for: CGSize(width: 60, height: 50)))
    }

    @Test("A shorter image keeps its pixels where the taller one has them and hatches the rest")
    @MainActor
    func sharedCanvasRendering() throws {
        // B is A cropped 10 px shorter at the bottom. Fit independently, B would be scaled and
        // centered differently from A; on the shared canvas its rows must land on A's rows.
        let a = makeImage(width: 40, height: 30)
        let b = makeImage(width: 40, height: 20)
        let layout = AlignedCanvasLayout([a.pixelSize, b.pixelSize])
        let viewSize = CGSize(width: 80, height: 60)   // fit scale 2, no letterboxing
        let ra = try render(a, layout: layout, viewSize: viewSize)
        let rb = try render(b, layout: layout, viewSize: viewSize)

        func close(_ p: RGBA, _ q: RGBA) -> Bool {
            abs(Int(p.r) - Int(q.r)) <= 3 && abs(Int(p.g) - Int(q.g)) <= 3 && abs(Int(p.b) - Int(q.b)) <= 3
        }
        // Rows away from B's bottom edge (where interpolation could differ) must match.
        for y in 0..<36 {
            for x in 0..<80 {
                #expect(close(ra[y][x], rb[y][x]), "pixel (\(x), \(y)): A \(ra[y][x]) vs B \(rb[y][x])")
            }
        }
        // Below B (canvas rows 20..<30, view rows 40..<60) is the purple size-mismatch hatch.
        for y in 42..<58 {
            for x in 2..<78 {
                let p = rb[y][x]
                #expect(p.a == 255 && p.b > p.g && p.r > p.g && p.b < 170,
                        "pixel (\(x), \(y)) should be hatched: \(p)")
            }
        }
    }
}
