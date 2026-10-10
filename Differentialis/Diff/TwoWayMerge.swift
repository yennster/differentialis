import Foundation

/// A contiguous run of changed rows in a two-way diff, as half-open 0-based line ranges on each
/// side. An empty range is an insertion point: the other side has lines this side lacks there.
struct TextHunk: Hashable {
    var a: Range<Int>
    var b: Range<Int>
}

/// Where one line sits inside a text, in UTF-16 offsets (NSString / NSTextView coordinates).
/// Lines follow `LineDiff.split`: LF, CR, and CRLF each end a line, and the empty segment after a
/// final newline is not a line of its own.
struct TextLineSpan: Hashable {
    var start: Int
    /// Length of the line's content, excluding its terminator.
    var length: Int
    var terminatorLength: Int

    var end: Int { start + length }
    var fullEnd: Int { start + length + terminatorLength }
}

/// The line on the other side that a line lines up with. Unmatched lines (deleted or inserted)
/// point at the other side's insertion point, which may equal its line count.
struct LineLink: Hashable {
    var line: Int
    var matched: Bool
}

enum TwoWayMerge {
    enum Direction { case aToB, bToA }

    /// Groups the changed rows of a two-way diff into hunks.
    static func hunks(in rows: [DiffRow]) -> [TextHunk] {
        var hunks: [TextHunk] = []
        var nextA = 0, nextB = 0
        var open: (a: Int, b: Int)?
        for row in rows {
            if row.kind == .equal {
                if let start = open {
                    hunks.append(TextHunk(a: start.a..<nextA, b: start.b..<nextB))
                    open = nil
                }
            } else if open == nil {
                open = (nextA, nextB)
            }
            // Row numbers are 1-based, so after a row the next line index on that side is its number.
            if let number = row.leftNumber { nextA = number }
            if let number = row.rightNumber { nextB = number }
        }
        if let start = open {
            hunks.append(TextHunk(a: start.a..<nextA, b: start.b..<nextB))
        }
        return hunks
    }

    /// Per-line correspondence in both directions, used to keep two editors scrolled together.
    static func lineLinks(in rows: [DiffRow]) -> (aToB: [LineLink], bToA: [LineLink]) {
        var aToB: [LineLink] = [], bToA: [LineLink] = []
        var nextA = 0, nextB = 0
        for row in rows {
            switch (row.leftNumber, row.rightNumber) {
            case let (left?, right?):
                aToB.append(LineLink(line: right - 1, matched: true))
                bToA.append(LineLink(line: left - 1, matched: true))
            case (_?, nil):
                aToB.append(LineLink(line: nextB, matched: false))
            case (nil, _?):
                bToA.append(LineLink(line: nextA, matched: false))
            case (nil, nil):
                break
            }
            if let number = row.leftNumber { nextA = number }
            if let number = row.rightNumber { nextB = number }
        }
        return (aToB, bToA)
    }

    /// Splits `text` into line spans, matching `LineDiff.split` line for line.
    static func lineSpans(in text: String) -> [TextLineSpan] {
        let units = Array(text.utf16)
        var spans: [TextLineSpan] = []
        var start = 0
        var index = 0
        while index < units.count {
            switch units[index] {
            case 0x0D:   // CR, or the CR of a CRLF
                let terminator = index + 1 < units.count && units[index + 1] == 0x0A ? 2 : 1
                spans.append(TextLineSpan(start: start, length: index - start, terminatorLength: terminator))
                index += terminator
                start = index
            case 0x0A:   // LF
                spans.append(TextLineSpan(start: start, length: index - start, terminatorLength: 1))
                index += 1
                start = index
            default:
                index += 1
            }
        }
        spans.append(TextLineSpan(start: start, length: units.count - start, terminatorLength: 0))
        if spans.count > 1, spans[spans.count - 1].length == 0 { spans.removeLast() }
        return spans
    }

    /// Copies one hunk's lines from the source side over the target side's lines for that hunk.
    static func apply(_ hunk: TextHunk, _ direction: Direction,
                      a: String, b: String) -> (a: String, b: String) {
        switch direction {
        case .aToB:
            let lines = slice(LineDiff.split(a), hunk.a)
            return (a, replacingLines(hunk.b, in: b, with: lines,
                                      fallbackEnding: ThreeWayMerge.lineStyle(of: a).ending))
        case .bToA:
            let lines = slice(LineDiff.split(b), hunk.b)
            return (replacingLines(hunk.a, in: a, with: lines,
                                   fallbackEnding: ThreeWayMerge.lineStyle(of: b).ending), b)
        }
    }

    /// Replaces the lines in `range` with `lines`. Untouched lines keep their exact terminators;
    /// new lines use the text's dominant line ending (or `fallbackEnding` when it has none), and
    /// the text keeps its final-newline state unless it now ends in an empty line.
    static func replacingLines(_ range: Range<Int>, in text: String, with lines: [String],
                               fallbackEnding: String = "\n") -> String {
        let spans = lineSpans(in: text)
        let source = text as NSString
        var parts: [(content: String, terminator: String)] = spans.map { span in
            (source.substring(with: NSRange(location: span.start, length: span.length)),
             source.substring(with: NSRange(location: span.end, length: span.terminatorLength)))
        }
        let hasTerminators = spans.contains { $0.terminatorLength > 0 }
        let ending = hasTerminators ? ThreeWayMerge.lineStyle(of: text).ending : fallbackEnding
        let finalNewline = (spans.last?.terminatorLength ?? 0) > 0

        let lower = min(max(range.lowerBound, 0), parts.count)
        let upper = min(max(range.upperBound, lower), parts.count)
        parts.replaceSubrange(lower..<upper, with: lines.map { (content: $0, terminator: "") })

        for index in parts.indices {
            // The last line keeps the text's final-newline state — except an empty last line, which
            // is only a line at all when it's terminated (otherwise it reads as the final newline).
            let isLast = index == parts.count - 1
            let needsTerminator = !isLast || finalNewline || (parts[index].content.isEmpty && parts.count > 1)
            if !needsTerminator {
                parts[index].terminator = ""
            } else if parts[index].terminator.isEmpty {
                parts[index].terminator = ending
            }
        }
        return parts.map { $0.content + $0.terminator }.joined()
    }

    /// Converts character-offset ranges within `line` (as `charDiff` reports them) to UTF-16.
    static func utf16Ranges(_ ranges: [Range<Int>], in line: String) -> [Range<Int>] {
        guard !ranges.isEmpty else { return [] }
        var boundaries = [0]
        var offset = 0
        for character in line {
            offset += character.utf16.count
            boundaries.append(offset)
        }
        return ranges.compactMap { range in
            guard range.lowerBound >= 0, range.lowerBound < range.upperBound,
                  range.upperBound < boundaries.count else { return nil }
            return boundaries[range.lowerBound]..<boundaries[range.upperBound]
        }
    }

    private static func slice(_ lines: [String], _ range: Range<Int>) -> [String] {
        let lower = min(max(range.lowerBound, 0), lines.count)
        let upper = min(max(range.upperBound, lower), lines.count)
        return Array(lines[lower..<upper])
    }
}
