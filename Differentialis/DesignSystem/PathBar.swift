import SwiftUI

/// The A ↔ B header shown above a comparison, styled as floating glass.
struct PathBar<Trailing: View>: View {
    let a: ComparisonSource
    let b: ComparisonSource
    var leftAccent: Color = Theme.removed
    var rightAccent: Color = Theme.modified
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            sideChip(a, accent: leftAccent, label: "A")
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
            sideChip(b, accent: rightAccent, label: "B")
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassCard(cornerRadius: 14)
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    private func sideChip(_ source: ComparisonSource, accent: Color, label: String) -> some View {
        HStack(spacing: 7) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(accent, in: RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 0) {
                Text(source.displayName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Text(source.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: 240, alignment: .leading)
    }
}

extension PathBar where Trailing == EmptyView {
    init(a: ComparisonSource, b: ComparisonSource,
         leftAccent: Color = Theme.removed, rightAccent: Color = Theme.modified) {
        self.init(a: a, b: b, leftAccent: leftAccent, rightAccent: rightAccent) { EmptyView() }
    }
}
