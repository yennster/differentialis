import SwiftUI

private struct AdaptivePathBarLayout: Layout {
    var minimumSourceWidth: CGFloat = 640
    var horizontalSpacing: CGFloat = 16
    var rowSpacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                     cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let sourceNatural = subviews[0].sizeThatFits(.unspecified)
        let controlSize = subviews[1].sizeThatFits(.unspecified)
        let naturalWidth = sourceNatural.width + (hasControls(controlSize) ? horizontalSpacing + controlSize.width : 0)
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? naturalWidth

        if shouldStack(width: width, controls: controlSize) {
            let sourceSize = subviews[0].sizeThatFits(.init(width: width, height: nil))
            return CGSize(width: width, height: sourceSize.height + rowSpacing + controlSize.height)
        }

        let sourceWidth = max(0, width - (hasControls(controlSize) ? horizontalSpacing + controlSize.width : 0))
        let sourceSize = subviews[0].sizeThatFits(.init(width: sourceWidth, height: nil))
        return CGSize(width: width, height: max(sourceSize.height, controlSize.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        guard subviews.count == 2 else { return }
        let controlSize = subviews[1].sizeThatFits(.unspecified)

        if shouldStack(width: bounds.width, controls: controlSize) {
            let sourceProposal = ProposedViewSize(width: bounds.width, height: nil)
            let sourceSize = subviews[0].sizeThatFits(sourceProposal)
            subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: sourceProposal)
            subviews[1].place(
                at: CGPoint(x: bounds.maxX, y: bounds.minY + sourceSize.height + rowSpacing),
                anchor: .topTrailing,
                proposal: .unspecified)
            return
        }

        let sourceWidth = max(0, bounds.width - (hasControls(controlSize) ? horizontalSpacing + controlSize.width : 0))
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.midY),
            anchor: .leading,
            proposal: .init(width: sourceWidth, height: nil))
        subviews[1].place(
            at: CGPoint(x: bounds.maxX, y: bounds.midY),
            anchor: .trailing,
            proposal: .unspecified)
    }

    private func shouldStack(width: CGFloat, controls: CGSize) -> Bool {
        hasControls(controls) && width < minimumSourceWidth + horizontalSpacing + controls.width
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
        AdaptivePathBarLayout {
            sources
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

    private var sources: some View {
        HStack(spacing: 14) {
            sideChip(a, accent: leftAccent, label: "A")
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            sideChip(b, accent: rightAccent, label: "B")
        }
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
        .frame(minWidth: 150, idealWidth: 280, maxWidth: .infinity, alignment: .leading)
    }
}

extension PathBar where Trailing == EmptyView {
    init(a: ComparisonSource, b: ComparisonSource,
         leftAccent: Color = Theme.removed, rightAccent: Color = Theme.modified) {
        self.init(a: a, b: b, leftAccent: leftAccent, rightAccent: rightAccent) { EmptyView() }
    }
}
