import Testing
import Foundation
@testable import Differentialis

@Suite("Find and Go to Line")
struct TextSearchTests {
    @Test("finds every non-overlapping occurrence, case-insensitively by default")
    func caseInsensitiveRanges() {
        #expect(TextSearch.ranges(of: "ab", in: "Ab xAB ab", caseSensitive: false) == [0..<2, 4..<6, 7..<9])
        #expect(TextSearch.ranges(of: "aa", in: "aaaa", caseSensitive: false) == [0..<2, 2..<4])
        #expect(TextSearch.ranges(of: "ab", in: "Ab xAB ab", caseSensitive: true) == [7..<9])
    }

    @Test("an empty query or line matches nothing")
    func emptyInputs() {
        #expect(TextSearch.ranges(of: "", in: "text", caseSensitive: false).isEmpty)
        #expect(TextSearch.ranges(of: "x", in: "", caseSensitive: false).isEmpty)
        #expect(TextSearch.matches(of: "", in: LineDiff.document("a", "b").allRows, options: .init()).isEmpty)
    }

    @Test("ranges count Characters, so matches after emoji and combining marks line up with the drawn text")
    func characterOffsets() {
        #expect(TextSearch.ranges(of: "ok", in: "👍🏽 ok", caseSensitive: false) == [2..<4])
        #expect(TextSearch.ranges(of: "x", in: "e\u{301}x🇫🇷x", caseSensitive: false) == [1..<2, 3..<4])
        // A decomposed é is one Character, not an "e" with something after it.
        #expect(TextSearch.ranges(of: "e", in: "e\u{301}", caseSensitive: false).isEmpty)
    }

    @Test("diff matches come in display order, A before B within a row")
    func diffMatchOrder() {
        let rows = LineDiff.document("let value = 1\nkeep\n", "let value = 2\nkeep\nvalue\n").allRows
        let matches = TextSearch.matches(of: "value", in: rows, options: .init())
        #expect(matches.map(\.side) == [.left, .right, .right])
        #expect(matches.map(\.range) == [4..<9, 4..<9, 0..<5])
        // The first two matches are the two halves of the one modified row.
        #expect(matches[0].rowID == matches[1].rowID)
        #expect(matches[2].rowID != matches[0].rowID)
    }

    @Test("the unified layout searches an unchanged row once, as it draws it")
    func unifiedSearchesContextOnce() {
        let rows = LineDiff.document("same x\nold x\n", "same x\nnew x\n").allRows
        let split = TextSearch.matches(of: "same", in: rows, options: .init())
        let unified = TextSearch.matches(of: "same", in: rows, options: .init(), unified: true)
        #expect(split.map(\.side) == [.left, .right])
        #expect(unified.map(\.side) == [.left])
        // Changed rows still show both sides in unified.
        #expect(TextSearch.matches(of: "x", in: rows, options: .init(), unified: true).count == 3)
    }

    @Test("changed lines only skips unchanged context on both sides")
    func changedOnly() {
        let rows = LineDiff.document("same x\nold x\n", "same x\nnew x\n").allRows
        let all = TextSearch.matches(of: "x", in: rows, options: .init())
        let changed = TextSearch.matches(of: "x", in: rows, options: .init(changedLinesOnly: true))
        #expect(all.count == 4)
        #expect(changed.count == 2)
        #expect(Set(changed.map(\.rowID)).count == 1)
    }

    @Test("rows hidden in a collapsed gap are still searched")
    func searchesCollapsedRows() {
        let context = (1...40).map { "line \($0)" }
        let a = (context + ["end A"]).joined(separator: "\n")
        let b = (context + ["end B"]).joined(separator: "\n")
        let document = LineDiff.document(a, b)
        #expect(document.sections.contains { if case .gap = $0 { true } else { false } })
        let matches = TextSearch.matches(of: "line 5", in: document.allRows, options: .init())
        // "line 5" appears in line 5 and lines 50+ don't exist, so one row, both sides.
        #expect(matches.count == 2)
    }

    @Test("merge Review matches follow what Review shows for each hunk")
    func mergeMatches() {
        let base = "keep\nvalue = 0\ntail\n"
        let left = "keep\nvalue = 1\ntail\n"
        let right = "keep\nvalue = 2\ntail\n"
        var hunks = ThreeWayMerge.merge(base: base, left: left, right: right)
        let conflictIndex = try! #require(hunks.firstIndex { $0.isConflict })

        let unresolved = TextSearch.matches(of: "value", in: hunks, options: .init())
        #expect(unresolved.map(\.part) == [.left, .right])

        let context = TextSearch.matches(of: "keep", in: hunks, options: .init())
        #expect(context.map(\.part) == [.chosen])
        #expect(TextSearch.matches(of: "keep", in: hunks, options: .init(changedLinesOnly: true)).isEmpty)

        hunks[conflictIndex].choose(.takeRight)
        let resolved = TextSearch.matches(of: "value", in: hunks, options: .init())
        #expect(resolved.count == 1)
        #expect(resolved[0].part == .chosen)
        #expect(resolved[0].hunkID == hunks[conflictIndex].id)
    }

    @Test("stepping wraps at both ends and starts at the first or last match")
    func stepping() {
        #expect(TextSearch.step(from: nil, by: 1, count: 3) == 0)
        #expect(TextSearch.step(from: nil, by: -1, count: 3) == 2)
        #expect(TextSearch.step(from: 2, by: 1, count: 3) == 0)
        #expect(TextSearch.step(from: 0, by: -1, count: 3) == 2)
        #expect(TextSearch.step(from: 1, by: 1, count: 3) == 2)
        #expect(TextSearch.step(from: 0, by: 1, count: 0) == nil)
    }

    @Test("Go to Line finds the row for a line on either side, clamping out-of-range lines")
    func goToLineRows() {
        // A: a b c d   B: a x b d e  →  rows: a, +x, b, -c, d, +e
        let rows = LineDiff.document("a\nb\nc\nd\n", "a\nx\nb\nd\ne\n").allRows
        func text(_ id: UUID?, _ side: DiffSide) -> String? {
            guard let row = rows.first(where: { $0.id == id }) else { return nil }
            return side == .left ? row.leftText : row.rightText
        }
        #expect(text(TextSearch.row(forLine: 3, side: .left, in: rows), .left) == "c")
        #expect(text(TextSearch.row(forLine: 2, side: .right, in: rows), .right) == "x")
        #expect(text(TextSearch.row(forLine: 5, side: .right, in: rows), .right) == "e")
        #expect(text(TextSearch.row(forLine: 99, side: .left, in: rows), .left) == "d")
        #expect(text(TextSearch.row(forLine: 0, side: .left, in: rows), .left) == "a")
        #expect(TextSearch.row(forLine: 1, side: .left, in: []) == nil)
    }

    @Test("Go to Line selects a whole line without its terminator, for LF, CRLF, and CR")
    func goToLineUTF16() {
        let text = "one\r\ntwo\nthree\rfour"
        #expect(TextSearch.utf16Range(ofLine: 1, in: text) == NSRange(location: 0, length: 3))
        #expect(TextSearch.utf16Range(ofLine: 2, in: text) == NSRange(location: 5, length: 3))
        #expect(TextSearch.utf16Range(ofLine: 3, in: text) == NSRange(location: 9, length: 5))
        #expect(TextSearch.utf16Range(ofLine: 4, in: text) == NSRange(location: 15, length: 4))
        #expect(TextSearch.utf16Range(ofLine: 9, in: text) == NSRange(location: 15, length: 4))
        #expect(TextSearch.utf16Range(ofLine: 0, in: text) == NSRange(location: 0, length: 3))
        #expect(TextSearch.lineCount(in: text) == 4)
    }

    @Test("Go to Line counts UTF-16 units and treats a final newline as ending the last line")
    func goToLineEdges() {
        #expect(TextSearch.utf16Range(ofLine: 2, in: "😀\nb\n") == NSRange(location: 3, length: 1))
        #expect(TextSearch.utf16Range(ofLine: 5, in: "a\nb\n") == NSRange(location: 2, length: 1))
        #expect(TextSearch.lineCount(in: "a\nb\n") == 2)
        #expect(TextSearch.lineCount(in: "a\r\n") == 1)
        #expect(TextSearch.lineCount(in: "") == 1)
        #expect(TextSearch.utf16Range(ofLine: 1, in: "") == NSRange(location: 0, length: 0))
        #expect(TextSearch.utf16Range(ofLine: 2, in: "a\n\nc") == NSRange(location: 2, length: 0))
    }
}
