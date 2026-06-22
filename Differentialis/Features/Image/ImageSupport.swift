import SwiftUI
import Observation
import CoreImage
import CoreImage.CIFilterBuiltins

/// Shared zoom/pan state so two image panes stay in sync.
@Observable
final class ZoomPanState {
    var scale: CGFloat = 1
    var offset: CGSize = .zero

    func reset() {
        scale = 1
        offset = .zero
    }
}

/// A zoomable, pannable image that drives a shared `ZoomPanState`.
struct ZoomableImageView: View {
    let image: NSImage
    let zoom: ZoomPanState

    @State private var baseScale: CGFloat = 1
    @State private var baseOffset: CGSize = .zero

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
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            zoom.scale = max(0.1, min(24, baseScale * value.magnification))
                        }
                        .onEnded { _ in baseScale = zoom.scale }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            zoom.offset = CGSize(width: baseOffset.width + value.translation.width,
                                                 height: baseOffset.height + value.translation.height)
                        }
                        .onEnded { _ in baseOffset = zoom.offset }
                )
                .onChange(of: zoom.scale) { _, newValue in
                    baseScale = newValue
                    if newValue == 1 { baseOffset = .zero }
                }
        }
        .background(CheckerboardBackground())
        .clipped()
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
