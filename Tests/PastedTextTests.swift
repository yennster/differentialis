import Testing
import Foundation
@testable import Differentialis

@Suite("Two-way merge")
struct TwoWayMergeTests {
    private let samples = ["", "a", "a\n", "\n", "\n\n", "a\r\nb", "a\rb\r", "a\r\r\nb",
                           "x\n\ny\n", "e\u{301}\n👋 hi", "a\n\r"]

    @Test("line spans match LineDiff.split line for line")
    func spansMatchSplit() {
        for text in samples {
            let spans = TwoWayMerge.lineSpans(in: text)
            let lines = LineDiff.split(text)
            #expect(spans.count == lines.count, "\(text.debugDescription)")
            let ns = text as NSString
            let contents = spans.map { ns.substring(with: NSRange(location: $0.start, length: $0.length)) }
            #expect(contents == lines, "\(text.debugDescription)")
        }
    }

    @Test("line count matches LineDiff.split without allocating lines")
    func lineCountMatchesSplit() {
        for text in samples {
            #expect(ComparisonSource.lineCount(of: text) == LineDiff.split(text).count, "\(text.debugDescription)")
        }
    }

    @Test("hunks group changed rows with insertion points on the shorter side")
    func hunks() {
        let rows = LineDiff.rows("one\nthree\nfour\n", "one\ntwo\nthree\nFOUR!\n")
        let hunks = TwoWayMerge.hunks(in: rows)
        #expect(hunks == [TextHunk(a: 1..<1, b: 1..<2), TextHunk(a: 2..<3, b: 3..<4)])
    }

    @Test("line links pair matched lines and pin unmatched ones to the insertion point")
    func lineLinks() {
        let links = TwoWayMerge.lineLinks(in: LineDiff.rows("1\n2\n3", "1\n3"))
        #expect(links.aToB == [LineLink(line: 0, matched: true), LineLink(line: 1, matched: false),
                               LineLink(line: 1, matched: true)])
        #expect(links.bToA == [LineLink(line: 0, matched: true), LineLink(line: 2, matched: true)])
    }

    @Test("copying a change in either direction makes that side match")
    func applyBothDirections() {
        let a = "one\ntwo\nthree\n"
        let b = "one\n2\nthree\n"
        let hunk = TwoWayMerge.hunks(in: LineDiff.rows(a, b))[0]
        #expect(TwoWayMerge.apply(hunk, .aToB, a: a, b: b) == (a, a))
        #expect(TwoWayMerge.apply(hunk, .bToA, a: a, b: b) == (b, b))
    }

    @Test("replacing lines keeps untouched terminators and the final-newline state")
    func replacingLines() {
        #expect(TwoWayMerge.replacingLines(1..<2, in: "a\r\nb\r\nc\r\n", with: ["X", "Y"])
                == "a\r\nX\r\nY\r\nc\r\n")
        #expect(TwoWayMerge.replacingLines(2..<3, in: "a\r\nb\nc\n", with: ["d"]) == "a\r\nb\nd\n")
        #expect(TwoWayMerge.replacingLines(2..<2, in: "a\nb", with: ["c"]) == "a\nb\nc")
        #expect(TwoWayMerge.replacingLines(1..<2, in: "a\nb\n", with: ["c"]) == "a\nc\n")
        #expect(TwoWayMerge.replacingLines(0..<2, in: "a\nb\n", with: []) == "")
        #expect(TwoWayMerge.replacingLines(0..<1, in: "solo", with: ["x", "y"], fallbackEnding: "\r\n")
                == "x\r\ny")
        // An empty last line has to be terminated to exist, even without a final newline.
        #expect(TwoWayMerge.replacingLines(1..<2, in: "a\nb", with: ["c", ""]) == "a\nc\n\n")
    }

    @Test("applying every hunk reproduces the source side (randomized)")
    func randomizedApplyAll() {
        var rng = SystemRandomNumberGenerator()
        let vocabulary = ["a", "b", "c", "", "a b"]
        func randomText() -> String {
            let lines = (0..<Int.random(in: 0...8, using: &rng)).map { _ in vocabulary.randomElement(using: &rng)! }
            guard !lines.isEmpty else { return "" }
            let ending = ["\n", "\r\n"].randomElement(using: &rng)!
            return lines.joined(separator: ending) + (Bool.random(using: &rng) ? ending : "")
        }
        for _ in 0..<300 {
            let a = randomText(), b = randomText()
            let hunks = TwoWayMerge.hunks(in: LineDiff.rows(a, b))
            // Apply back to front so earlier hunks' line ranges stay valid.
            var toB = b, toA = a
            for hunk in hunks.reversed() {
                toB = TwoWayMerge.apply(hunk, .aToB, a: a, b: toB).b
                toA = TwoWayMerge.apply(hunk, .bToA, a: toA, b: b).a
            }
            #expect(LineDiff.split(toB) == LineDiff.split(a), "A→B failed for \(a.debugDescription) / \(b.debugDescription)")
            #expect(LineDiff.split(toA) == LineDiff.split(b), "B→A failed for \(a.debugDescription) / \(b.debugDescription)")
        }
    }

    @Test("character ranges convert to UTF-16 across multi-unit characters")
    func utf16Ranges() {
        #expect(TwoWayMerge.utf16Ranges([3..<4], in: "👋 hi") == [4..<5])
        #expect(TwoWayMerge.utf16Ranges([0..<1, 9..<10], in: "👋 hi") == [0..<2])
    }
}

@Suite("Pasted text analysis")
struct PastedTextAnalysisTests {
    @Test("modified and inserted lines become fills, highlights, and hunk ranges")
    func decorations() {
        let analysis = PastedTextAnalysis.make(a: "let x = 1\nlet y = 2\n",
                                               b: "let x = 1\nlet y = 3\nlet z = 4\n",
                                               whitespace: .significant)
        #expect(analysis.hunks == [TextHunk(a: 1..<2, b: 1..<3)])
        #expect(analysis.a.lineFills == [.init(range: NSRange(location: 10, length: 10), kind: .modified)])
        #expect(analysis.b.lineFills == [.init(range: NSRange(location: 10, length: 10), kind: .modified),
                                         .init(range: NSRange(location: 20, length: 10), kind: .inserted)])
        #expect(analysis.a.characterHighlights == [NSRange(location: 18, length: 1)])
        #expect(analysis.b.characterHighlights == [NSRange(location: 18, length: 1)])
        #expect(analysis.a.hunkRanges == [NSRange(location: 10, length: 10)])
        #expect(analysis.b.hunkRanges == [NSRange(location: 10, length: 20)])
        #expect(analysis.stats == DiffStats(insertions: 1, deletions: 0, modifications: 1))
    }

    @Test("an insertion is a zero-length hunk range that the caret can select")
    func insertionPoint() {
        let analysis = PastedTextAnalysis.make(a: "one\nthree\n", b: "one\ntwo\nthree\n", whitespace: .significant)
        #expect(analysis.a.hunkRanges == [NSRange(location: 4, length: 0)])
        #expect(analysis.b.hunkRanges == [NSRange(location: 4, length: 4)])
        #expect(analysis.hunkIndex(containing: 4, on: .a) == 0)
        #expect(analysis.hunkIndex(containing: 5, on: .a) == nil)
        #expect(analysis.hunkIndex(containing: 7, on: .b) == 0)
        #expect(analysis.hunkIndex(containing: 8, on: .b) == nil)
    }

    @Test("an insertion after a last line without a newline points at the end of the text")
    func insertionAtEnd() {
        let analysis = PastedTextAnalysis.make(a: "one", b: "one\ntwo", whitespace: .significant)
        #expect(analysis.a.hunkRanges == [NSRange(location: 3, length: 0)])
    }

    @Test("highlights land on UTF-16 offsets, not character offsets")
    func emojiHighlights() {
        let analysis = PastedTextAnalysis.make(a: "👋 hi", b: "👋 ho", whitespace: .significant)
        #expect(analysis.a.characterHighlights == [NSRange(location: 4, length: 1)])
        #expect(analysis.b.characterHighlights == [NSRange(location: 4, length: 1)])
    }
}
