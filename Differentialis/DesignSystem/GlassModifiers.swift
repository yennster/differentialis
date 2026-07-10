import SwiftUI

/// A floating glass panel (toolbars, popovers, mode switchers).
struct GlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

extension View {
    /// Standard glass card used throughout the app.
    func glassCard(cornerRadius: CGFloat = 18) -> some View {
        glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }

    /// Tinted, interactive glass — used for accent chips and active controls.
    func tintedGlass(_ color: Color, cornerRadius: CGFloat = 12) -> some View {
        glassEffect(.regular.tint(color.opacity(0.55)).interactive(),
                    in: .rect(cornerRadius: cornerRadius))
    }

    /// Apply when a view should sit on the app's dark gradient canvas.
    func diffCanvasBackground() -> some View {
        background(Theme.canvas.ignoresSafeArea())
    }
}

extension Animation {
    /// Shared animation for sidebar/panel collapse and expand — slightly slower than `.snappy`
    /// so the transition reads as deliberate rather than instantaneous.
    static let panel: Animation = .snappy(duration: 0.45)
}

/// Shown in place of a collapsed panel: a thin rail with an expand control at the top and an
/// optional title rendered vertically (rotated 90°) so the panel's purpose is visible at a glance.
struct CollapsedRail: View {
    var title: String? = nil
    var expand: () -> Void

    // Width of the title text in its font, used as the height of the rotated frame.
    // rotationEffect is render-only, so we reserve a swapped-dimension slot by measuring the
    // text's natural (horizontal) width and using it as the rotated view's height.
    private var titleWidth: CGFloat {
        guard let title else { return 0 }
        let base = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        let font = NSFont(descriptor: descriptor, size: 11) ?? base
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        return (title.uppercased() as NSString).size(withAttributes: attrs).width + 2
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: expand) {
                Image(systemName: "sidebar.left").font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .padding(.vertical, 9)
            .help("Show panel")
            Divider().opacity(0.3)
            if let title {
                // rotationEffect is render-only — it doesn't change layout bounds. We give the
                // rotated text a frame whose height equals the text's natural (horizontal) width,
                // so the vertical glyphs have room and don't overlap the divider/button above.
                // Top-aligned: the VStack(alignment: .top) on the outer frame pins it just below
                // the divider, with Spacer filling the rest.
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.7))
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
                    .frame(width: 34, height: titleWidth)
                    .padding(.top, 12)
                Spacer()
            } else {
                Spacer()
            }
        }
        .frame(width: 34, alignment: .top)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.18))
    }
}

struct StatChip: View {
    let text: String
    var color: Color = .secondary
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .bold)) }
            Text(text).font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(color.opacity(0.14), in: Capsule())
    }
}
