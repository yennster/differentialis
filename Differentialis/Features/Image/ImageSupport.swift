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
                        context.fill(Path(rect), with: .color(.white.opacity(0.035)))
                    }
                }
            }
        }
        .background(.black.opacity(0.22))
    }
}

/// Renders image comparisons that require pixel math.
enum ImageDiffRenderer {
    private static let context = CIContext(options: nil)

    static func cgImage(from image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    /// False-color difference: pixels that match appear dark, differences glow.
    static func difference(_ a: NSImage, _ b: NSImage, amplify: Bool = true) -> NSImage? {
        guard let ca = cgImage(from: a), let cb = cgImage(from: b) else { return nil }
        let ia = CIImage(cgImage: ca)
        let ib = CIImage(cgImage: cb)

        let blend = CIFilter.differenceBlendMode()
        blend.inputImage = ia
        blend.backgroundImage = ib
        guard var output = blend.outputImage else { return nil }

        if amplify {
            let boost = CIFilter.colorControls()
            boost.inputImage = output
            boost.brightness = 0.06
            boost.contrast = 1.9
            boost.saturation = 1.4
            if let boosted = boost.outputImage { output = boosted }
        }

        let extent = ia.extent.intersection(ib.extent).isEmpty ? ia.extent : ia.extent.union(ib.extent)
        guard let result = context.createCGImage(output, from: extent) else { return nil }
        return NSImage(cgImage: result, size: extent.size)
    }
}

extension NSImage {
    var pixelSize: CGSize {
        guard let rep = representations.first else { return size }
        return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }

    var pixelDescription: String {
        let p = pixelSize
        return "\(Int(p.width)) × \(Int(p.height)) px"
    }
}
