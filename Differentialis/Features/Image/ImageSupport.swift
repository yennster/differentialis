import SwiftUI
import Observation
import CoreImage
import CoreImage.CIFilterBuiltins

/// Shared zoom/pan state so two image panes stay in sync.
@Observable
final class ZoomPanState {
    static let minimumScale: CGFloat = 0.1
    static let maximumScale: CGFloat = 24

    var scale: CGFloat = 1
    var offset: CGSize = .zero

    func reset() {
        scale = 1
        offset = .zero
    }

    func zoom(by factor: CGFloat) {
        scale = min(Self.maximumScale, max(Self.minimumScale, scale * factor))
    }
}

/// A zoomable, pannable image that drives a shared `ZoomPanState`.
struct ZoomableImageView: View {
    let image: NSImage
    let zoom: ZoomPanState

    var body: some View {
        GeometryReader { geo in
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .scaleEffect(zoom.scale)
                .offset(zoom.offset)
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .zoomPanGestures(zoom)
        }
        .background(CheckerboardBackground())
        .clipped()
    }
}

/// One gesture implementation shared by regular image panes and the split-reveal canvas. Each
/// consumer keeps a local gesture base, then follows external changes while idle. In a two-up view
/// this prevents the second pane from jumping back to its stale pre-pan offset when the user starts
/// dragging it after panning the first pane.
private struct ZoomPanGestureModifier: ViewModifier {
    let zoom: ZoomPanState

    @State private var baseScale: CGFloat = 1
    @State private var baseOffset: CGSize = .zero
    @State private var isZooming = false
    @State private var isPanning = false

    func body(content: Content) -> some View {
        content
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        if !isZooming {
                            isZooming = true
                            baseScale = zoom.scale
                        }
                        zoom.scale = min(ZoomPanState.maximumScale,
                                         max(ZoomPanState.minimumScale,
                                             baseScale * value.magnification))
                    }
                    .onEnded { _ in
                        isZooming = false
                        baseScale = zoom.scale
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        if !isPanning {
                            isPanning = true
                            baseOffset = zoom.offset
                        }
                        zoom.offset = CGSize(width: baseOffset.width + value.translation.width,
                                             height: baseOffset.height + value.translation.height)
                    }
                    .onEnded { _ in
                        isPanning = false
                        baseOffset = zoom.offset
                    }
            )
            .onAppear {
                baseScale = zoom.scale
                baseOffset = zoom.offset
            }
            .onChange(of: zoom.scale) { _, newValue in
                if !isZooming { baseScale = newValue }
            }
            .onChange(of: zoom.offset) { _, newValue in
                if !isPanning { baseOffset = newValue }
            }
    }
}

extension View {
    func zoomPanGestures(_ zoom: ZoomPanState) -> some View {
        modifier(ZoomPanGestureModifier(zoom: zoom))
    }
}

/// Subtle transparency checkerboard behind images.
struct CheckerboardBackground: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 12
            let cols = Int(size.width / tile) + 1
            let rows = Int(size.height / tile) + 1
            for row in 0..<rows {
                for col in 0..<cols {
                    if (row + col).isMultiple(of: 2) {
                        let rect = CGRect(x: CGFloat(col) * tile, y: CGFloat(row) * tile, width: tile, height: tile)
                        context.fill(Path(rect), with: .color(.primary.opacity(0.035)))
                    }
                }
            }
        }
        .background(Theme.wellDeep)
    }
}

/// Renders image comparisons that require pixel math.
///
/// Everything here works in **pixel space**: a 144-dpi export and a 72-dpi export with the same
/// pixel dimensions compare one-to-one. Images of different sizes are pinned to the **top-left**
/// of a shared canvas (matching how people read a screenshot that was cropped or padded at the
/// bottom or right), so only the strip that one side lacks differs. That strip is painted with a
/// diagonal hatch rather than diffed, so a size change reads as "missing" instead of as content.
enum ImageDiffRenderer {
    private static let context = CIContext(options: nil)

    /// The full-resolution pixels of `image`. Prefers the largest bitmap representation so the
    /// result doesn't depend on the image's point size (DPI); falls back to rendering at the
    /// representation's pixel size for vector or otherwise non-bitmap images.
    static func cgImage(from image: NSImage) -> CGImage? {
        let bitmaps = image.representations.compactMap { $0 as? NSBitmapImageRep }
        if let best = bitmaps.max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }),
           let cg = best.cgImage {
            return cg
        }
        // An identity CTM keeps AppKit from picking up the main screen's backing scale, so the
        // fallback rasterizes at the same size on every Mac.
        var rect = CGRect(origin: .zero, size: image.pixelSize)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: NSAffineTransform()])
    }

    /// False-color difference: pixels that match appear dark, differences glow.
    static func difference(_ a: NSImage, _ b: NSImage, amplify: Bool = true) -> NSImage? {
        guard let ca = cgImage(from: a), let cb = cgImage(from: b),
              let result = difference(ca, cb, amplify: amplify) else { return nil }
        return NSImage(cgImage: result, size: CGSize(width: result.width, height: result.height))
    }

    /// Pixel-space difference of two bitmaps on a top-left-aligned canvas of
    /// `max(widths) × max(heights)`. The overlapping region holds the (optionally amplified)
    /// difference; the rest of the canvas, which only one side or neither side covers, is hatched.
    static func difference(_ a: CGImage, _ b: CGImage, amplify: Bool = true) -> CGImage? {
        let canvas = canvasSize(a, b)
        guard canvas.width > 0, canvas.height > 0 else { return nil }
        // Core Image's origin is bottom-left: lift the shorter image so the top edges line up.
        let ia = topAligned(CIImage(cgImage: a), canvasHeight: canvas.height)
        let ib = topAligned(CIImage(cgImage: b), canvasHeight: canvas.height)
        let overlap = ia.extent.intersection(ib.extent)

        let blend = CIFilter.differenceBlendMode()
        blend.inputImage = ia
        blend.backgroundImage = ib
        guard var output = blend.outputImage?.cropped(to: overlap) else { return nil }

        if amplify {
            let boost = CIFilter.colorControls()
            boost.inputImage = output
            boost.brightness = 0.06
            boost.contrast = 1.9
            boost.saturation = 1.4
            if let boosted = boost.outputImage { output = boosted.cropped(to: overlap) }
        }

        let bounds = CGRect(origin: .zero, size: canvas)
        if overlap != bounds, let hatch = sizeMismatchHatch(scale: max(canvas.width, canvas.height)) {
            for rect in uncoveredRects(canvas: bounds, overlap: overlap) {
                output = hatch.cropped(to: rect).composited(over: output)
            }
        }

        return context.createCGImage(output, from: bounds)
    }

    static func canvasSize(_ a: CGImage, _ b: CGImage) -> CGSize {
        CGSize(width: max(a.width, b.width), height: max(a.height, b.height))
    }

    private static func topAligned(_ image: CIImage, canvasHeight: CGFloat) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: 0, y: canvasHeight - image.extent.height))
    }

    /// The parts of `canvas` outside `overlap`, as disjoint rectangles. Both images are pinned to
    /// the top-left, so the overlap is the canvas's top-left corner: the rest is a strip on the
    /// right (full height) and a strip along the bottom (under the overlap). Requires that pinning:
    /// `overlap.minX == canvas.minX` and `overlap.maxY == canvas.maxY`.
    static func uncoveredRects(canvas: CGRect, overlap: CGRect) -> [CGRect] {
        guard !overlap.isNull, !overlap.isEmpty else { return [canvas] }
        var rects: [CGRect] = []
        if overlap.maxX < canvas.maxX {
            rects.append(CGRect(x: overlap.maxX, y: canvas.minY,
                                width: canvas.maxX - overlap.maxX, height: canvas.height))
        }
        if overlap.minY > canvas.minY {
            rects.append(CGRect(x: canvas.minX, y: canvas.minY,
                                width: overlap.maxX - canvas.minX, height: overlap.minY - canvas.minY))
        }
        return rects
    }

    /// Infinite diagonal hatch for canvas areas only one image covers. Stripe width scales with
    /// the canvas so it stays visible when a large image is fit to the window.
    private static func sizeMismatchHatch(scale: CGFloat) -> CIImage? {
        let stripes = CIFilter.stripesGenerator()
        stripes.color0 = CIColor(red: 0.42, green: 0.30, blue: 0.55, alpha: 1)
        stripes.color1 = CIColor(red: 0.20, green: 0.15, blue: 0.27, alpha: 1)
        stripes.width = Float(max(4, (scale / 120).rounded()))
        stripes.sharpness = 1
        return stripes.outputImage?.transformed(by: CGAffineTransform(rotationAngle: .pi / 4))
    }
}

extension NSImage {
    /// Pixel dimensions of the largest representation, independent of the image's DPI. Vector
    /// reps (PDF) can report 0 pixels, so those fall back to points.
    var pixelSize: CGSize {
        let best = representations
            .filter { $0.pixelsWide > 0 && $0.pixelsHigh > 0 }
            .max { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }
        guard let best else { return size }
        return CGSize(width: best.pixelsWide, height: best.pixelsHigh)
    }

    var pixelDescription: String {
        let p = pixelSize
        return "\(Int(p.width)) × \(Int(p.height)) px"
    }
}
