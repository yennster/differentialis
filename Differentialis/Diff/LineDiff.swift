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

/// How lines are matched against each other: which differences count as changes. Ignored
/// differences change only the comparison keys and row classification; every line is still shown
/// with its original text, so nothing is hidden silently.
struct LineMatchOptions: Hashable, Sendable {
    var whitespace: WhitespacePolicy = .significant
    /// Lines that differ only in letter case match. Matched lines keep both spellings and are
    /// marked `isIgnored` when their text differs, so views can dim them.
    var ignoreCase = false
    /// Lines that are empty or whitespace-only never count as insertions or deletions. They still
    /// appear, as ignored rows, so the line numbers on each side stay continuous.
    var ignoreBlankLines = false

    static let exact = LineMatchOptions()

    var isExact: Bool { self == .exact }

    /// The active relaxations as a lowercase phrase, e.g. "ignoring case and blank lines".
    var ignoredSummary: String? {
        var parts: [String] = []
        switch whitespace {
        case .significant: break
        case .trimEdges: parts.append("edge whitespace")
        case .ignoreAll: parts.append("all whitespace")
        }
        if ignoreCase { parts.append("case") }
        if ignoreBlankLines { parts.append("blank lines") }
        guard !parts.isEmpty else { return nil }
        let list = parts.count == 1 ? parts[0]
            : parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        return "ignoring " + list
    }

    func comparisonKey(for line: String) -> String {
        let key = whitespace.comparisonKey(for: line)
        // Case folding, not just lowercasing: "STRASSE" matches "straße", "ΟΔΟΣ" matches "οδος".
        return ignoreCase ? key.folding(options: .caseInsensitive, locale: nil) : key
    }

    static func isBlank(_ line: String) -> Bool {
        line.allSatisfy(\.isWhitespace)
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
        rows(aText, bText, options: LineMatchOptions(whitespace: whitespace))
    }

    /// Build aligned side-by-side rows from two texts, matching lines as `options` describes.
    static func rows(_ aText: String, _ bText: String, options: LineMatchOptions) -> [DiffRow] {
        let a = split(aText)
        let b = split(bText)
        // With blank lines ignored, they take no part in the alignment at all: Myers runs on the
        // remaining lines only, so blank lines can never pull content out of alignment. They are
        // woven back in afterwards (see `flushPending`).
        let aLines = options.ignoreBlankLines ? a.indices.filter { !LineMatchOptions.isBlank(a[$0]) }
                                              : Array(a.indices)
        let bLines = options.ignoreBlankLines ? b.indices.filter { !LineMatchOptions.isBlank(b[$0]) }
                                              : Array(b.indices)
        let edits = myersDiff(aLines.map { options.comparisonKey(for: a[$0]) },
                              bLines.map { options.comparisonKey(for: b[$0]) })

        var rows: [DiffRow] = []
        var pendingDeletes: [(Int, String)] = []
        var pendingInserts: [(Int, String)] = []

        // With case ignored, compare characters case-insensitively too, so an edit that also
        // changes case only highlights the real change. Lowercasing can change the character
        // count (rarely), which would misalign the ranges; fall back to the exact diff then.
        func characterDiff(_ left: String, _ right: String) -> CharDiffResult {
            guard options.ignoreCase else { return charDiff(left, right) }
            let lowerLeft = left.lowercased(), lowerRight = right.lowercased()
            guard lowerLeft.count == left.count, lowerRight.count == right.count else {
                return charDiff(left, right)
            }
            return charDiff(lowerLeft, lowerRight)
        }

        /// An unchanged row. It is marked ignored when the two sides' text differs (a match
        /// only under the options) or when only one side has the line (an ignored blank line).
        func equalRow(left: (Int, String)?, right: (Int, String)?) -> DiffRow {
            DiffRow(kind: .equal, leftNumber: left.map { $0.0 + 1 }, rightNumber: right.map { $0.0 + 1 },
                    leftText: left?.1, rightText: right?.1,
                    isIgnored: left == nil || right == nil || left?.1 != right?.1)
        }

        func appendChangeRows() {
            let count = max(pendingDeletes.count, pendingInserts.count)
            for i in 0..<count {
                let del = i < pendingDeletes.count ? pendingDeletes[i] : nil
                let ins = i < pendingInserts.count ? pendingInserts[i] : nil
                switch (del, ins) {
                case let (d?, n?):
                    // One char diff yields both the similarity gate and the highlight ranges.
                    let cd = characterDiff(d.1, n.1)
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

        func flushPending() {
            guard options.ignoreBlankLines else {
                appendChangeRows()
                return
            }
            // Blank lines leave the change run and become unchanged rows. The remaining lines pair
            // up as usual; each blank row is then placed before the first change row that comes
            // after it on its side, so line numbers stay in order in both columns. Blank lines
            // due on both sides at once share a row; leftovers get a dimmed one-sided row.
            let blankDeletes = pendingDeletes.filter { LineMatchOptions.isBlank($0.1) }
            let blankInserts = pendingInserts.filter { LineMatchOptions.isBlank($0.1) }
            guard !blankDeletes.isEmpty || !blankInserts.isEmpty else {
                appendChangeRows()
                return
            }
            pendingDeletes.removeAll { LineMatchOptions.isBlank($0.1) }
            pendingInserts.removeAll { LineMatchOptions.isBlank($0.1) }
            let start = rows.count
            appendChangeRows()
            let changeRows = Array(rows[start...])
            rows.removeSubrange(start...)

            var nextDelete = 0, nextInsert = 0
            func emitBlanks(beforeLeft left: Int?, beforeRight right: Int?) {
                while true {
                    let leftDue = nextDelete < blankDeletes.count
                        && left.map({ blankDeletes[nextDelete].0 < $0 - 1 }) ?? false
                    let rightDue = nextInsert < blankInserts.count
                        && right.map({ blankInserts[nextInsert].0 < $0 - 1 }) ?? false
                    guard leftDue || rightDue else { return }
                    rows.append(equalRow(left: leftDue ? blankDeletes[nextDelete] : nil,
                                         right: rightDue ? blankInserts[nextInsert] : nil))
                    if leftDue { nextDelete += 1 }
                    if rightDue { nextInsert += 1 }
                }
            }
            for row in changeRows {
                emitBlanks(beforeLeft: row.leftNumber, beforeRight: row.rightNumber)
                rows.append(row)
            }
            emitBlanks(beforeLeft: .max, beforeRight: .max)
        }

        // Lines skipped by the alignment (blank lines, when ignored) join the pending run once
        // the edit script passes them, keeping each pending list in line order.
        var nextA = 0, nextB = 0
        func catchUp(a upToA: Int, b upToB: Int) {
            while nextA < upToA { pendingDeletes.append((nextA, a[nextA])); nextA += 1 }
            while nextB < upToB { pendingInserts.append((nextB, b[nextB])); nextB += 1 }
        }

        for edit in edits {
            switch edit {
            case let .equal(fi, fj):
                let i = aLines[fi], j = bLines[fj]
                catchUp(a: i, b: j)
                flushPending()
                rows.append(equalRow(left: (i, a[i]), right: (j, b[j])))
                nextA = i + 1
                nextB = j + 1
            case let .delete(fi):
                let i = aLines[fi]
                catchUp(a: i, b: nextB)
                pendingDeletes.append((i, a[i]))
                nextA = i + 1
            case let .insert(fj):
                let j = bLines[fj]
                catchUp(a: nextA, b: j)
                pendingInserts.append((j, b[j]))
                nextB = j + 1
            }
        }
        catchUp(a: a.count, b: b.count)
        flushPending()
        return rows
    }

    static func stats(for rows: [DiffRow]) -> DiffStats {
        var insertions = 0, deletions = 0, modifications = 0
        for row in rows {
            switch row.kind {
            case .inserted: insertions += 1
            case .deleted: deletions += 1
            case .modified: modifications += 1
            case .equal: break
            }
        }
        return DiffStats(insertions: insertions, deletions: deletions, modifications: modifications)
    }

    /// Build a full diff document with collapsible gaps and statistics.
    static func document(_ aText: String, _ bText: String,
                         whitespace: WhitespacePolicy = .significant) -> DiffDocument {
        document(aText, bText, options: LineMatchOptions(whitespace: whitespace))
    }

    /// Build a full diff document, matching lines as `options` describes.
    static func document(_ aText: String, _ bText: String, options: LineMatchOptions) -> DiffDocument {
        let rows = rows(aText, bText, options: options)
        let stats = stats(for: rows)

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
