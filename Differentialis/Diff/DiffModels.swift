import Foundation

/// A single alignment row in a two-way diff, suitable for side-by-side rendering.
struct DiffRow: Identifiable, Hashable {
    enum Kind: Hashable {
        case equal
        case inserted   // present only on the right (B)
        case deleted    // present only on the left (A)
        case modified   // changed line pair (A ↔ B) with intra-line highlights
    }

    let id = UUID()
    var kind: Kind
    var leftNumber: Int?
    var rightNumber: Int?
    var leftText: String?
    var rightText: String?
    /// Character-offset ranges (into `leftText` / `rightText`) that differ.
    var leftHighlights: [Range<Int>] = []
    var rightHighlights: [Range<Int>] = []

    static func == (lhs: DiffRow, rhs: DiffRow) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A diff document broken into visible row groups and collapsible gaps.
struct DiffDocument {
    enum Section: Identifiable {
        case rows([DiffRow])
        case gap(id: UUID, hiddenCount: Int, rows: [DiffRow])

        var id: String {
            switch self {
            case .rows(let r): return "rows-\(r.first?.id.uuidString ?? "empty")-\(r.count)"
            case .gap(let id, _, _): return "gap-\(id.uuidString)"
            }
        }
    }

    var sections: [Section]
    var stats: DiffStats
    /// Flattened rows that are not collapsed, in order — used for next/prev navigation.
    var allRows: [DiffRow]

    var isIdentical: Bool { stats.insertions == 0 && stats.deletions == 0 && stats.modifications == 0 }
}

extension DiffRow.Kind {
    var isChange: Bool { self != .equal }
}
