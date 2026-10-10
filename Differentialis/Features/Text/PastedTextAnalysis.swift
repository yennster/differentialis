import Foundation

/// What one editor of a pasted-text comparison should paint, in UTF-16 offsets into its text.
struct EditorDecorations: Equatable {
    struct LineFill: Equatable {
        /// The whole line, terminator included, so empty lines still have a glyph to paint.
        var range: NSRange
        var kind: DiffRow.Kind
    }

    var lineFills: [LineFill] = []
    /// Changed characters inside modified lines.
    var characterHighlights: [NSRange] = []
    /// This side's span of each hunk, in hunk order. A zero-length range is an insertion point:
    /// the other side has lines that would be inserted here.
    var hunkRanges: [NSRange] = []
}

/// A diff of the two pasted texts, shaped for side-by-side editors. Computed off the main actor.
struct PastedTextAnalysis {
    var aText: String
    var bText: String
    var stats: DiffStats
    var formatDifferences: [String]
    var hunks: [TextHunk]
    var a: EditorDecorations
    var b: EditorDecorations
    var aToB: [LineLink]
    var bToA: [LineLink]

    var isIdentical: Bool { stats.isIdentical }

    static func make(a: String, b: String, whitespace: WhitespacePolicy) -> PastedTextAnalysis {
        let rows = LineDiff.rows(a, b, whitespace: whitespace)
        let hunks = TwoWayMerge.hunks(in: rows)
        let links = TwoWayMerge.lineLinks(in: rows)
        let aSpans = TwoWayMerge.lineSpans(in: a)
        let bSpans = TwoWayMerge.lineSpans(in: b)

        var aDecorations = EditorDecorations()
        var bDecorations = EditorDecorations()
        for row in rows where row.kind != .equal {
            if let number = row.leftNumber, number - 1 < aSpans.count {
                let span = aSpans[number - 1]
                aDecorations.lineFills.append(.init(range: fullRange(span), kind: row.kind))
                aDecorations.characterHighlights += highlights(row.leftHighlights, row.leftText, span)
            }
            if let number = row.rightNumber, number - 1 < bSpans.count {
                let span = bSpans[number - 1]
                bDecorations.lineFills.append(.init(range: fullRange(span), kind: row.kind))
                bDecorations.characterHighlights += highlights(row.rightHighlights, row.rightText, span)
            }
        }
        aDecorations.hunkRanges = hunks.map { range(of: $0.a, in: aSpans, textLength: a.utf16.count) }
        bDecorations.hunkRanges = hunks.map { range(of: $0.b, in: bSpans, textLength: b.utf16.count) }

        return PastedTextAnalysis(aText: a, bText: b,
                                  stats: LineDiff.stats(for: rows),
                                  formatDifferences: textFormatDifferences(a, b),
                                  hunks: hunks, a: aDecorations, b: bDecorations,
                                  aToB: links.aToB, bToA: links.bToA)
    }

    /// The hunk whose span on `side` contains the UTF-16 `location`, if any.
    func hunkIndex(containing location: Int, on side: PastedTextSide) -> Int? {
        let ranges = side == .a ? a.hunkRanges : b.hunkRanges
        return ranges.firstIndex { range in
            range.length == 0 ? location == range.location
                              : location >= range.location && location < NSMaxRange(range)
        }
    }

    private static func fullRange(_ span: TextLineSpan) -> NSRange {
        NSRange(location: span.start, length: span.fullEnd - span.start)
    }

    private static func highlights(_ ranges: [Range<Int>], _ line: String?,
                                   _ span: TextLineSpan) -> [NSRange] {
        guard let line, !ranges.isEmpty else { return [] }
        return TwoWayMerge.utf16Ranges(ranges, in: line).map {
            NSRange(location: span.start + $0.lowerBound, length: $0.count)
        }
    }

    private static func range(of lines: Range<Int>, in spans: [TextLineSpan], textLength: Int) -> NSRange {
        guard !lines.isEmpty else {
            let location = lines.lowerBound < spans.count ? spans[lines.lowerBound].start : textLength
            return NSRange(location: location, length: 0)
        }
        let lower = min(lines.lowerBound, spans.count - 1)
        let upper = min(lines.upperBound, spans.count) - 1
        let start = spans[lower].start
        return NSRange(location: start, length: max(0, spans[upper].fullEnd - start))
    }
}

enum PastedTextSide: Hashable {
    case a, b

    var other: PastedTextSide { self == .a ? .b : .a }
}
