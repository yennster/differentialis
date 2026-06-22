import Testing
@testable import Differentialis

@Suite("Myers diff")
struct MyersDiffTests {
    @Test("identical sequences produce only equals")
    func identical() {
        let edits = myersDiff(["a", "b", "c"], ["a", "b", "c"])
        #expect(edits.allSatisfy { if case .equal = $0 { return true } else { return false } })
        #expect(edits.count == 3)
    }

    @Test("insertion is detected")
    func insertion() {
        let edits = myersDiff(["a", "c"], ["a", "b", "c"])
        let inserts = edits.filter { if case .insert = $0 { return true } else { return false } }
        #expect(inserts.count == 1)
    }

    @Test("deletion is detected")
    func deletion() {
        let edits = myersDiff(["a", "b", "c"], ["a", "c"])
        let deletes = edits.filter { if case .delete = $0 { return true } else { return false } }
        #expect(deletes.count == 1)
    }

    @Test("empty inputs")
    func empties() {
        #expect(myersDiff([Int](), [Int]()).isEmpty)
        #expect(myersDiff([1, 2], []).count == 2)
        #expect(myersDiff([], [1, 2, 3]).count == 3)
    }
}

@Suite("Line diff")
struct LineDiffTests {
    @Test("counts insertions and deletions")
    func stats() {
        let a = "one\ntwo\nthree"
        let b = "one\nTWO\nthree\nfour"
        let doc = LineDiff.document(a, b)
        #expect(!doc.isIdentical)
        #expect(doc.stats.modifications == 1)   // two -> TWO
        #expect(doc.stats.insertions == 1)      // + four
    }

    @Test("identical text reports no changes")
    func identical() {
        let doc = LineDiff.document("alpha\nbeta", "alpha\nbeta")
        #expect(doc.isIdentical)
        #expect(doc.stats.totalChanges == 0)
    }

    @Test("intra-line highlights are produced for similar lines")
    func highlights() {
        let doc = LineDiff.document("color = red", "color = blue")
        let modified = doc.allRows.first { $0.kind == .modified }
        #expect(modified != nil)
        #expect(!(modified?.rightHighlights.isEmpty ?? true))
    }
}

@Suite("Three-way merge")
struct ThreeWayMergeTests {
    @Test("non-overlapping edits merge cleanly")
    func cleanMerge() {
        let base = "line1\nline2\nline3"
        let left = "LINE1\nline2\nline3"     // changed first line
        let right = "line1\nline2\nLINE3"    // changed last line
        let hunks = ThreeWayMerge.merge(base: base, left: left, right: right)
        #expect(ThreeWayMerge.conflictCount(hunks) == 0)
        let merged = ThreeWayMerge.mergedText(hunks)
        #expect(merged.contains("LINE1"))
        #expect(merged.contains("LINE3"))
    }

    @Test("overlapping edits produce a conflict")
    func conflict() {
        let base = "value = 1"
        let left = "value = 2"
        let right = "value = 3"
        let hunks = ThreeWayMerge.merge(base: base, left: left, right: right)
        #expect(ThreeWayMerge.conflictCount(hunks) == 1)
    }

    @Test("identical edits on both sides are not a conflict")
    func sameEdit() {
        let base = "x"
        let hunks = ThreeWayMerge.merge(base: base, left: "y", right: "y")
        #expect(ThreeWayMerge.conflictCount(hunks) == 0)
        #expect(ThreeWayMerge.mergedText(hunks) == "y")
    }
}
