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

/// Shown in place of a collapsed panel: a thin rail with an expand control at the top.
struct CollapsedRail: View {
    var expand: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Button(action: expand) {
                Image(systemName: "sidebar.left").font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .padding(.vertical, 9)
            .help("Show panel")
            Divider().opacity(0.3)
            Spacer()
        }
        .frame(width: 34, alignment: .top)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.18))
    }
}

/// A pill-shaped count/stat chip.
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
