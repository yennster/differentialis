import Foundation

enum WhitespacePolicy: String, CaseIterable, Hashable {
    case significant
    case trimEdges
    case ignoreAll

    var label: String {
        switch self {
        case .significant: return "Compare Exactly"
        case .trimEdges: return "Ignore Edge Whitespace"
        case .ignoreAll: return "Ignore All Whitespace"
        }
    }

    fileprivate func comparisonKey(for line: String) -> String {
        switch self {
        case .significant:
            return line
        case .trimEdges:
            return line.trimmingCharacters(in: .whitespaces)
        case .ignoreAll:
            return String(line.filter { !$0.isWhitespace })
        }
    }
}

enum LineDiff {
    /// Number of unchanged context lines kept around each change before collapsing.
    static let context = 3
    /// Collapse a run of equal lines only when it is longer than this.
    static let collapseThreshold = context * 2 + 1

    static func split(_ text: String) -> [String] {
        // Normalize CR/CRLF to LF, then split. A single trailing empty component (the final
        // newline every well-formed text file ends with) is dropped so the diff doesn't show a
        // phantom blank numbered row at the end of the file. An empty input stays one empty line.
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        if lines.count > 1 && lines.last == "" { lines.removeLast() }
        return lines
    }

    /// Build aligned side-by-side rows from two texts.
    static func rows(_ aText: String, _ bText: String,
                     whitespace: WhitespacePolicy = .significant) -> [DiffRow] {
        let a = split(aText)
        let b = split(bText)
        let aKeys = a.map(whitespace.comparisonKey)
        let bKeys = b.map(whitespace.comparisonKey)
        let edits = myersDiff(aKeys, bKeys)

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
                    // One char diff yields both the similarity gate and the highlight ranges.
                    let cd = charDiff(d.1, n.1)
                    // A case-only edit has a zero case-sensitive LCS score but is still an obvious
                    // line modification rather than an unrelated delete/insert pair.
                    let similar = cd.similarity > 0.25 || d.1.caseInsensitiveCompare(n.1) == .orderedSame
                    if similar {
                        rows.append(DiffRow(kind: .modified,
                                            leftNumber: d.0 + 1, rightNumber: n.0 + 1,
                                            leftText: d.1, rightText: n.1,
                                            leftHighlights: cd.left,
                                            rightHighlights: cd.right))
                    } else {
                        // Unrelated lines only happen to be adjacent in the edit script. Keeping
                        // them as separate rows avoids presenting a semantic replacement where
                        // there is no useful correspondence between the two sides.
                        rows.append(DiffRow(kind: .deleted,
                                            leftNumber: d.0 + 1, rightNumber: nil,
                                            leftText: d.1, rightText: nil))
                        rows.append(DiffRow(kind: .inserted,
                                            leftNumber: nil, rightNumber: n.0 + 1,
                                            leftText: nil, rightText: n.1))
                    }
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
    static func document(_ aText: String, _ bText: String,
                         whitespace: WhitespacePolicy = .significant) -> DiffDocument {
        let rows = rows(aText, bText, whitespace: whitespace)

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
