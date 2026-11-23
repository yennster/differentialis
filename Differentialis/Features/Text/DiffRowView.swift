import SwiftUI
import AppKit

/// Builds the attributed text for one diff line: syntax token foregrounds first, then the
/// changed-character backgrounds on top, so intra-line highlights stay visible over code colors.
/// `tokens` and `ranges` are Character offsets into `text`.
func highlightedLine(_ text: String, ranges: [Range<Int>], color: Color,
                     tokens: [SyntaxToken] = [], palette: SyntaxPalette? = nil) -> AttributedString {
    var attr = syntaxColoredLine(text, tokens: tokens, palette: palette)
    let count = text.count
    for range in ranges {
        guard range.lowerBound >= 0, range.upperBound <= count, range.lowerBound < range.upperBound else { continue }
        let lower = attr.characters.index(attr.characters.startIndex, offsetBy: range.lowerBound)
        let upper = attr.characters.index(attr.characters.startIndex, offsetBy: range.upperBound)
        attr[lower..<upper].backgroundColor = color
    }
    return attr
}

/// Assembles the line segment by segment (one walk over the string) rather than indexing into
/// an `AttributedString` per token.
private func syntaxColoredLine(_ text: String, tokens: [SyntaxToken], palette: SyntaxPalette?) -> AttributedString {
    guard let palette, !tokens.isEmpty else { return AttributedString(text) }
    var result = AttributedString()
    var cursor = text.startIndex
    var offset = 0
    for token in tokens {
        // Tokens arrive sorted and disjoint; skip anything that isn't (or doesn't fit this text).
        guard token.range.lowerBound >= offset, !token.range.isEmpty,
              let start = text.index(cursor, offsetBy: token.range.lowerBound - offset,
                                     limitedBy: text.endIndex),
              let end = text.index(start, offsetBy: token.range.count, limitedBy: text.endIndex)
        else { continue }
        if cursor < start { result.append(AttributedString(text[cursor..<start])) }
        var piece = AttributedString(text[start..<end])
        piece.foregroundColor = palette.color(for: token.kind)
        result.append(piece)
        cursor = end
        offset = token.range.upperBound
    }
    if cursor < text.endIndex { result.append(AttributedString(text[cursor...])) }
    return result
}

/// A single side-by-side diff row: two gutter+text halves sharing one height.
struct DiffRowView: View {
    let row: DiffRow
    var isCurrent: Bool = false
    /// Fixed width for the left half (the draggable column split); nil splits evenly.
    var leftWidth: CGFloat? = nil
    /// Syntax tokens for each side's line; empty when highlighting is off or unavailable.
    var leftTokens: [SyntaxToken] = []
    var rightTokens: [SyntaxToken] = []

    var body: some View {
        HStack(spacing: 0) {
            half(number: row.leftNumber, text: row.leftText, highlights: row.leftHighlights,
                 tokens: leftTokens, kind: leftKind, side: .left)
                .frame(width: leftWidth)
            Rectangle().fill(.primary.opacity(0.06)).frame(width: 1)
            half(number: row.rightNumber, text: row.rightText, highlights: row.rightHighlights,
                 tokens: rightTokens, kind: rightKind, side: .right)
        }
        .background(isCurrent ? Theme.brand.opacity(0.12) : .clear)
        .contextMenu { DiffRowCopyMenu(left: row.leftText, right: row.rightText) }
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
    private func half(number: Int?, text: String?, highlights: [Range<Int>], tokens: [SyntaxToken],
                      kind: DiffRow.Kind, side: Side) -> some View {
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
            lineText(text, highlights: highlights, tokens: tokens, side: side)
                .padding(.leading, 8)
                .padding(.vertical, 1.5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.fill(for: kind))
    }

    @ViewBuilder
    private func lineText(_ text: String?, highlights: [Range<Int>], tokens: [SyntaxToken], side: Side) -> some View {
        if let text {
            let highlightColor = side == .left ? Theme.removedHighlight : Theme.addedHighlight
            Text(highlightedLine(text, ranges: highlights, color: highlightColor,
                                 tokens: tokens, palette: Theme.syntax))
                .font(Theme.codeFont)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            // empty placeholder for the absent side
            Color.clear.frame(height: Theme.codeEmptyLineHeight)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Copy actions for a diff row. Per-line `textSelection` can't span rows, so this gives an explicit
/// way to copy whichever side you want (or both) without dragging across the split.
struct DiffRowCopyMenu: View {
    let left: String?
    let right: String?

    var body: some View {
        if let left {
            Button("Copy Left") { copy(left) }
        }
        if let right {
            Button("Copy Right") { copy(right) }
        }
        if let left, let right {
            Button("Copy Both") { copy("\(left)\t\(right)") }
        }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
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
            .background(.primary.opacity(0.03))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(Rectangle().fill(.primary.opacity(0.06)).frame(height: 1), alignment: .top)
        .overlay(Rectangle().fill(.primary.opacity(0.06)).frame(height: 1), alignment: .bottom)
    }
}
