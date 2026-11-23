import Foundation

/// Options for Find in a diff or merge.
struct TextSearchOptions: Hashable, Sendable {
    var caseSensitive = false
    /// Search only the lines a diff marks as changed (merge: only the hunks that changed).
    var changedLinesOnly = false
}

/// A side of a two-way diff, as Find and Go to Line see it.
enum DiffSide: Hashable, Sendable {
    case left, right
}

/// One Find match in a two-way diff: a character range in one side of one row.
struct DiffSearchMatch: Hashable, Sendable {
    let rowID: UUID
    let side: DiffSide
    /// Character offsets into that side's text, the same coordinates as the row's change highlights.
    let range: Range<Int>
}

/// Which lines of a merge hunk a match is in. Mirrors what merge Review shows for the hunk:
/// the chosen lines, or the Left and Right columns of an unresolved conflict.
enum MergeSearchPart: Hashable, Sendable {
    case chosen, left, right
}

/// One Find match in merge Review.
struct MergeSearchMatch: Hashable, Sendable {
    let hunkID: UUID
    let part: MergeSearchPart
    /// 0-based index into that part's lines.
    let line: Int
    let range: Range<Int>
}

/// Pure Find and Go to Line logic, shared by the text diff, unified view, and merge.
enum TextSearch {
    /// Find stops collecting after this many matches, so a one-letter query on a huge file can't
    /// build millions of highlights. The count then reads "10,000+".
    static let matchLimit = 10_000

    /// Character-offset ranges of every non-overlapping occurrence of `query` in `text`, in order.
    /// Offsets count Swift `Character`s, like the diff's change highlights, so a match after an
    /// emoji or a combining sequence lands where it is drawn.
    static func ranges(of query: String, in text: String, caseSensitive: Bool) -> [Range<Int>] {
        guard !query.isEmpty, !text.isEmpty else { return [] }
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var result: [Range<Int>] = []
        var searchStart = text.startIndex
        var offset = 0  // Character offset of `searchStart`.
        while searchStart < text.endIndex,
              let found = text.range(of: query, options: options, range: searchStart..<text.endIndex) {
            let lower = offset + text.distance(from: searchStart, to: found.lowerBound)
            let length = text.distance(from: found.lowerBound, to: found.upperBound)
            if length > 0 { result.append(lower..<(lower + length)) }
            // Always move forward, even if a match rounds to no whole characters.
            let next = length > 0 ? found.upperBound : text.index(after: found.lowerBound)
            offset = lower + text.distance(from: found.lowerBound, to: next)
            searchStart = next
        }
        return result
    }

    /// Every match in `rows`, in display order: row by row, the left (A) text before the right (B).
    /// Split and unified layouts both draw a modified row's A line before its B line. The unified
    /// layout draws an unchanged row once, from A, so its B text is not searched there.
    static func matches(of query: String, in rows: [DiffRow], options: TextSearchOptions,
                        unified: Bool = false, limit: Int = matchLimit) -> [DiffSearchMatch] {
        guard !query.isEmpty else { return [] }
        var result: [DiffSearchMatch] = []
        for row in rows {
            if result.count >= limit { break }
            if options.changedLinesOnly && !row.kind.isChange { continue }
            if let text = row.leftText {
                for range in ranges(of: query, in: text, caseSensitive: options.caseSensitive) {
                    result.append(DiffSearchMatch(rowID: row.id, side: .left, range: range))
                }
            }
            if let text = row.rightText, !(unified && row.kind == .equal) {
                for range in ranges(of: query, in: text, caseSensitive: options.caseSensitive) {
                    result.append(DiffSearchMatch(rowID: row.id, side: .right, range: range))
                }
            }
        }
        return Array(result.prefix(limit))
    }

    /// The lines merge Review shows for a hunk, with the part each belongs to.
    static func reviewParts(of hunk: MergeHunk) -> [(part: MergeSearchPart, lines: [String])] {
        if hunk.isConflict && !hunk.resolved {
            return [(.left, hunk.leftLines), (.right, hunk.rightLines)]
        }
        return [(.chosen, hunk.chosen)]
    }

    /// Every match in merge Review, in display order. "Changed lines only" skips unchanged context.
    static func matches(of query: String, in hunks: [MergeHunk], options: TextSearchOptions,
                        limit: Int = matchLimit) -> [MergeSearchMatch] {
        guard !query.isEmpty else { return [] }
        var result: [MergeSearchMatch] = []
        for hunk in hunks {
            if result.count >= limit { break }
            if options.changedLinesOnly && !hunk.isChange { continue }
            for (part, lines) in reviewParts(of: hunk) {
                for (index, line) in lines.enumerated() where result.count < limit {
                    for range in ranges(of: query, in: line, caseSensitive: options.caseSensitive) {
                        result.append(MergeSearchMatch(hunkID: hunk.id, part: part, line: index, range: range))
                    }
                }
            }
        }
        return Array(result.prefix(limit))
    }

    /// Where Find starts after a search: the first match at or after `anchor` (a position in
    /// display order, such as the row of the previous current match or of the change being
    /// viewed), wrapping to the first match; nil when there are none. `position` gives each
    /// match's display position.
    static func startIndex<Match>(of matches: [Match], at anchor: Int?, position: (Match) -> Int) -> Int? {
        guard !matches.isEmpty else { return nil }
        guard let anchor else { return 0 }
        return matches.firstIndex { position($0) >= anchor } ?? 0
    }

    /// The match index after stepping `delta` (1 next, -1 previous) from `current` in `count`
    /// matches, wrapping around. With no current match, next goes to the first and previous to
    /// the last.
    static func step(from current: Int?, by delta: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let current else { return delta >= 0 ? 0 : count - 1 }
        return ((current + delta) % count + count) % count
    }

    /// The row showing 1-based `line` of one side. A line past the end goes to that side's last
    /// line and a line before 1 to its first; nil only when no row has a line on that side.
    static func row(forLine line: Int, side: DiffSide, in rows: [DiffRow]) -> UUID? {
        var last: UUID?
        for row in rows {
            guard let number = side == .left ? row.leftNumber : row.rightNumber else { continue }
            if number >= line { return row.id }
            last = row.id
        }
        return last
    }

    /// The UTF-16 range of 1-based `line` in `text`, without its terminator, for selecting it in
    /// an `NSTextView`. LF, CRLF, and CR all end a line. A line past the end clamps to the last
    /// line and a line before 1 to the first.
    static func utf16Range(ofLine line: Int, in text: String) -> NSRange {
        let units = Array(text.utf16)
        var starts = [0]
        var index = 0
        while index < units.count {
            let unit = units[index]
            if unit == 0x0D, index + 1 < units.count, units[index + 1] == 0x0A {
                index += 2
                starts.append(index)
            } else if unit == 0x0A || unit == 0x0D {
                index += 1
                starts.append(index)
            } else {
                index += 1
            }
        }
        // A final terminator ends the last line; it doesn't start an empty one.
        if starts.count > 1, starts.last == units.count { starts.removeLast() }
        let target = min(max(line, 1), starts.count) - 1
        let start = starts[target]
        var end = target + 1 < starts.count ? starts[target + 1] : units.count
        // Drop the terminator.
        if end > start, units[end - 1] == 0x0A { end -= 1 }
        if end > start, units[end - 1] == 0x0D { end -= 1 }
        return NSRange(location: start, length: end - start)
    }
}
