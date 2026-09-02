import SwiftUI

/// Lays out [A chip] [arrow + B chip] [controls] so the A side fills the left half of the
/// bar and the B group starts exactly at the midpoint — lining the headings up with the
/// two columns of a split comparison below. Controls sit at the trailing edge of B's half;
/// when they would crowd the B heading, they drop to a second trailing row instead.
private struct PathBarLayout: Layout {
    var minimumSideWidth: CGFloat = 160
    var horizontalSpacing: CGFloat = 16
    var rowSpacing: CGFloat = 10
    /// Breathing room between the A-side arrow and the midpoint where B begins.
    var midGap: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                     cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        let controlSize = subviews[2].sizeThatFits(.unspecified)

        guard let width = proposal.width.flatMap({ $0.isFinite ? $0 : nil }) else {
            let leftNatural = subviews[0].sizeThatFits(.unspecified)
            let rightNatural = subviews[1].sizeThatFits(.unspecified)
            let naturalWidth = leftNatural.width + midGap + rightNatural.width
                + (hasControls(controlSize) ? horizontalSpacing + controlSize.width : 0)
            return CGSize(width: naturalWidth,
                          height: max(leftNatural.height, rightNatural.height, controlSize.height))
        }

        let halfWidth = width / 2
        if shouldStack(width: width, controls: controlSize) {
            let rowHeight = sideRowHeight(halfWidth: halfWidth, rightWidth: halfWidth, subviews: subviews)
            return CGSize(width: width, height: rowHeight + rowSpacing + controlSize.height)
        }
        let rightWidth = rightSideWidth(halfWidth: halfWidth, controls: controlSize)
        let rowHeight = sideRowHeight(halfWidth: halfWidth, rightWidth: rightWidth, subviews: subviews)
        return CGSize(width: width, height: max(rowHeight, controlSize.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        guard subviews.count == 3 else { return }
        let controlSize = subviews[2].sizeThatFits(.unspecified)
        let halfWidth = bounds.width / 2

        if shouldStack(width: bounds.width, controls: controlSize) {
            let rowHeight = sideRowHeight(halfWidth: halfWidth, rightWidth: halfWidth, subviews: subviews)
            let rowMidY = bounds.minY + rowHeight / 2
            subviews[0].place(at: CGPoint(x: bounds.minX, y: rowMidY), anchor: .leading,
                              proposal: .init(width: halfWidth - midGap, height: nil))
            subviews[1].place(at: CGPoint(x: bounds.minX + halfWidth, y: rowMidY), anchor: .leading,
                              proposal: .init(width: halfWidth, height: nil))
            subviews[2].place(at: CGPoint(x: bounds.maxX, y: bounds.minY + rowHeight + rowSpacing),
                              anchor: .topTrailing, proposal: .unspecified)
            return
        }

        let rightWidth = rightSideWidth(halfWidth: halfWidth, controls: controlSize)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                          proposal: .init(width: halfWidth - midGap, height: nil))
        subviews[1].place(at: CGPoint(x: bounds.minX + halfWidth, y: bounds.midY), anchor: .leading,
                          proposal: .init(width: rightWidth, height: nil))
        subviews[2].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing,
                          proposal: .unspecified)
    }

    private func rightSideWidth(halfWidth: CGFloat, controls: CGSize) -> CGFloat {
        max(0, halfWidth - (hasControls(controls) ? horizontalSpacing + controls.width : 0))
    }

    private func sideRowHeight(halfWidth: CGFloat, rightWidth: CGFloat, subviews: Subviews) -> CGFloat {
        let left = subviews[0].sizeThatFits(.init(width: halfWidth - midGap, height: nil))
        let right = subviews[1].sizeThatFits(.init(width: rightWidth, height: nil))
        return max(left.height, right.height)
    }

    private func shouldStack(width: CGFloat, controls: CGSize) -> Bool {
        hasControls(controls) && rightSideWidth(halfWidth: width / 2, controls: controls) < minimumSideWidth
    }

    private func hasControls(_ size: CGSize) -> Bool {
        size.width > 0.5 || size.height > 0.5
    }
}

/// The A ↔ B header shown above a comparison, styled as floating glass.
struct PathBar<Trailing: View>: View {
    let a: ComparisonSource
    let b: ComparisonSource
    var leftAccent: Color = Theme.removed
    var rightAccent: Color = Theme.modified
    @ViewBuilder var trailing: Trailing

    var body: some View {
        PathBarLayout {
            sideChip(a, accent: leftAccent, label: "A")
            // The arrow leads the B group so the whole B heading starts flush with the
            // right column's left edge instead of the arrow dangling over the left column.
            HStack(spacing: 12) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                sideChip(b, accent: rightAccent, label: "B")
            }
            controls
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 16)
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    private var controls: some View {
        HStack(spacing: 12) { trailing }
            .fixedSize(horizontal: true, vertical: false)
    }

    private func sideChip(_ source: ComparisonSource, accent: Color, label: String) -> some View {
        HStack(spacing: 9) {
            Text(label)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(Theme.badgeForeground)
                .frame(width: 18, height: 18)
                .background(accent, in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 1) {
                Text(source.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(source.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
    }
}

extension PathBar where Trailing == EmptyView {
    init(a: ComparisonSource, b: ComparisonSource,
         leftAccent: Color = Theme.removed, rightAccent: Color = Theme.modified) {
        self.init(a: a, b: b, leftAccent: leftAccent, rightAccent: rightAccent) { EmptyView() }
    }
}
