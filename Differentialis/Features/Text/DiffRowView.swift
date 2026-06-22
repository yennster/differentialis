import SwiftUI

/// Builds an AttributedString with the changed character ranges highlighted.
func highlightedLine(_ text: String, ranges: [Range<Int>], color: Color) -> AttributedString {
    var attr = AttributedString(text)
    let count = text.count
    for range in ranges {
        guard range.lowerBound >= 0, range.upperBound <= count, range.lowerBound < range.upperBound else { continue }
        let lower = attr.characters.index(attr.characters.startIndex, offsetBy: range.lowerBound)
        let upper = attr.characters.index(attr.characters.startIndex, offsetBy: range.upperBound)
        attr[lower..<upper].backgroundColor = color
    }
    return attr
}

/// A single side-by-side diff row: two gutter+text halves sharing one height.
struct DiffRowView: View {
    let row: DiffRow
    var isCurrent: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            half(number: row.leftNumber, text: row.leftText, highlights: row.leftHighlights,
                 kind: leftKind, side: .left)
            Rectangle().fill(.white.opacity(0.06)).frame(width: 1)
            half(number: row.rightNumber, text: row.rightText, highlights: row.rightHighlights,
                 kind: rightKind, side: .right)
        }
        .background(isCurrent ? Theme.brand.opacity(0.12) : .clear)
    }

    private enum Side { case left, right }

    private var leftKind: DiffRow.Kind {
        switch row.kind {
        case .inserted: return .equal    // left is empty for an insertion
        default: return row.kind
        }
    }
    private var rightKind: DiffRow.Kind {
        switch row.kind {
        case .deleted: return .equal     // right is empty for a deletion
        default: return row.kind
        }
    }

    @ViewBuilder
    private func half(number: Int?, text: String?, highlights: [Range<Int>], kind: DiffRow.Kind, side: Side) -> some View {
        let accent = Theme.color(for: kind)
        HStack(spacing: 0) {
            // change bar + line number gutter
            ZStack(alignment: .trailing) {
                Rectangle().fill(kind.isChange ? accent : .clear).frame(width: 2.5)
                Text(number.map(String.init) ?? "")
                    .font(Theme.gutterFont)
                    .foregroundStyle(.secondary.opacity(0.7))
                    .padding(.trailing, 7)
            }
            .frame(width: 46, alignment: .trailing)

            // line content
            lineText(text, highlights: highlights, side: side)
                .padding(.leading, 8)
                .padding(.vertical, 1.5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.fill(for: kind))
    }

    @ViewBuilder
    private func lineText(_ text: String?, highlights: [Range<Int>], side: Side) -> some View {
        if let text {
            let highlightColor = side == .left ? Theme.removedHighlight : Theme.addedHighlight
            Text(highlightedLine(text, ranges: highlights, color: highlightColor))
                .font(Theme.codeFont)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            // empty placeholder for the absent side
            Color.clear.frame(height: 17)
                .frame(maxWidth: .infinity)
        }
    }
}

/// A collapsed run of unchanged lines that can be expanded.
struct DiffGapView: View {
    let count: Int
    let onExpand: () -> Void

    var body: some View {
        Button(action: onExpand) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10, weight: .bold))
                Text("\(count) unchanged line\(count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.03))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(Rectangle().fill(.white.opacity(0.06)).frame(height: 1), alignment: .top)
        .overlay(Rectangle().fill(.white.opacity(0.06)).frame(height: 1), alignment: .bottom)
    }
}
