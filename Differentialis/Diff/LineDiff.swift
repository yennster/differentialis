import Foundation

enum LineDiff {
    /// Number of unchanged context lines kept around each change before collapsing.
    static let context = 3
    /// Collapse a run of equal lines only when it is longer than this.
    static let collapseThreshold = context * 2 + 1

    static func split(_ text: String) -> [String] {
        // Normalize CRLF and split on newlines (keeps a trailing empty line if present).
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    /// Build aligned side-by-side rows from two texts.
    static func rows(_ aText: String, _ bText: String) -> [DiffRow] {
        let a = split(aText)
        let b = split(bText)
        let edits = myersDiff(a, b)

        var rows: [DiffRow] = []
        var pendingDeletes: [(Int, String)] = []
        var pendingInserts: [(Int, String)] = []

        func flushPending() {
            let count = max(pendingDeletes.count, pendingInserts.count)
            for i in 0..<count {
                let del = i < pendingDeletes.count ? pendingDeletes[i] : nil
                let ins = i < pendingInserts.count ? pendingInserts[i] : nil
                switch (del, ins) {
                case let (d?, n?):
                    let sim = similarity(d.1, n.1)
                    let (lh, rh) = sim > 0.25 ? charHighlights(d.1, n.1) : ([], [])
                    rows.append(DiffRow(kind: .modified,
                                        leftNumber: d.0 + 1, rightNumber: n.0 + 1,
                                        leftText: d.1, rightText: n.1,
                                        leftHighlights: sim > 0.25 ? lh : [],
                                        rightHighlights: sim > 0.25 ? rh : []))
                case let (d?, nil):
                    rows.append(DiffRow(kind: .deleted,
                                        leftNumber: d.0 + 1, rightNumber: nil,
                                        leftText: d.1, rightText: nil))
                case let (nil, n?):
                    rows.append(DiffRow(kind: .inserted,
                                        leftNumber: nil, rightNumber: n.0 + 1,
                                        leftText: nil, rightText: n.1))
                case (nil, nil):
                    break
                }
            }
            pendingDeletes.removeAll(keepingCapacity: true)
            pendingInserts.removeAll(keepingCapacity: true)
        }

        for edit in edits {
            switch edit {
            case let .equal(i, j):
                flushPending()
                rows.append(DiffRow(kind: .equal,
                                    leftNumber: i + 1, rightNumber: j + 1,
                                    leftText: a[i], rightText: b[j]))
            case let .delete(i):
                pendingDeletes.append((i, a[i]))
            case let .insert(j):
                pendingInserts.append((j, b[j]))
            }
        }
        flushPending()
        return rows
    }

    /// Build a full diff document with collapsible gaps and statistics.
    static func document(_ aText: String, _ bText: String) -> DiffDocument {
        let rows = rows(aText, bText)

        var insertions = 0, deletions = 0, modifications = 0
        for row in rows {
            switch row.kind {
            case .inserted: insertions += 1
            case .deleted: deletions += 1
            case .modified: modifications += 1
            case .equal: break
            }
        }
        let stats = DiffStats(insertions: insertions, deletions: deletions, modifications: modifications)

        // Group into sections, collapsing long equal runs.
        var sections: [DiffDocument.Section] = []
        var buffer: [DiffRow] = []
        var equalRun: [DiffRow] = []

        func flushEqualRun(atDocumentEdge: Bool) {
            guard !equalRun.isEmpty else { return }
            if equalRun.count > collapseThreshold {
                let leading = atDocumentEdge && buffer.isEmpty ? 0 : context
                let trailing = context
                let head = Array(equalRun.prefix(leading))
                let tail = Array(equalRun.suffix(trailing))
                let hidden = Array(equalRun.dropFirst(leading).dropLast(trailing))
                buffer.append(contentsOf: head)
                if !buffer.isEmpty { sections.append(.rows(buffer)); buffer = [] }
                sections.append(.gap(id: UUID(), hiddenCount: hidden.count, rows: hidden))
                buffer.append(contentsOf: tail)
            } else {
                buffer.append(contentsOf: equalRun)
            }
            equalRun.removeAll(keepingCapacity: true)
        }

        for row in rows {
            if row.kind == .equal {
                equalRun.append(row)
            } else {
                flushEqualRun(atDocumentEdge: false)
                buffer.append(row)
            }
        }
        flushEqualRun(atDocumentEdge: true)
        if !buffer.isEmpty { sections.append(.rows(buffer)) }

        return DiffDocument(sections: sections, stats: stats, allRows: rows)
    }
}
