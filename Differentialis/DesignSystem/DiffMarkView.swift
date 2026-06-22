import SwiftUI

/// The Differentialis mark: two offset, overlapping translucent panes whose
/// intersection forms the "difference". Reused in chrome and to render the app icon.
struct DiffMarkView: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Theme.removed.gradient)
                .frame(width: size * 0.66, height: size * 0.66)
                .offset(x: -size * 0.14, y: -size * 0.10)
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Theme.brandAlt.gradient)
                .frame(width: size * 0.66, height: size * 0.66)
                .offset(x: size * 0.14, y: size * 0.10)
                .blendMode(.screen)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.brand.opacity(0.4), radius: size * 0.08, y: size * 0.04)
    }
}
