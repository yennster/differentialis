import Testing
import Foundation
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

    /// Rebuild both sides from the edit script — the core invariant of any correct diff. Exercises
    /// the prefix/suffix trimming and band-based backtrack across many random inputs.
    private func reconstructs(_ a: [Int], _ b: [Int]) -> Bool {
        let edits = myersDiff(a, b)
        var fromA: [Int] = [], fromB: [Int] = []
        for edit in edits {
            switch edit {
            case let .equal(i, j): fromA.append(a[i]); fromB.append(b[j])
            case let .delete(i): fromA.append(a[i])
            case let .insert(j): fromB.append(b[j])
            }
        }
        return fromA == a && fromB == b
    }

    @Test("edit script reconstructs both sides (shared prefix/suffix)")
    func reconstruction() {
        #expect(reconstructs([1, 2, 3, 4, 5], [1, 2, 9, 4, 5]))       // middle change
        #expect(reconstructs([1, 2, 3], [1, 2, 3, 4, 5]))            // suffix insert
        #expect(reconstructs([0, 1, 2, 3], [1, 2, 3]))               // prefix delete
        #expect(reconstructs([1, 1, 1, 1], [1, 1]))                  // repeats
        #expect(reconstructs([], []))
        #expect(reconstructs([5], [5]))
    }

    @Test("randomized reconstruction")
    func randomizedReconstruction() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let a = (0..<Int.random(in: 0...40, using: &rng)).map { _ in Int.random(in: 0...5, using: &rng) }
            let b = (0..<Int.random(in: 0...40, using: &rng)).map { _ in Int.random(in: 0...5, using: &rng) }
            #expect(reconstructs(a, b), "failed for \(a) / \(b)")
        }
    }

    @Test("large dissimilar inputs stay valid and bounded")
    func largeDissimilar() {
        // Two wholly-dissimilar 20k-element sequences. Before the budget/band fix this allocated
        // gigabytes; now it degrades to a block replace and still reconstructs correctly.
        let a = (0..<20_000).map { $0 }
        let b = (0..<20_000).map { $0 + 1_000_000 }
        let edits = myersDiff(a, b)
        var fromA: [Int] = [], fromB: [Int] = []
        for edit in edits {
            switch edit {
            case let .equal(i, j): fromA.append(a[i]); fromB.append(b[j])
            case let .delete(i): fromA.append(a[i])
            case let .insert(j): fromB.append(b[j])
            }
        }
        #expect(fromA == a)
        #expect(fromB == b)
    }
}

@Suite("Character diff")
struct CharDiffTests {
    @Test("combined result gives highlights and similarity in one pass")
    func combined() {
        let result = charDiff("color = red", "color = blue")
        #expect(!result.left.isEmpty)
        #expect(!result.right.isEmpty)
        #expect(result.similarity > 0.25 && result.similarity < 1)
    }

    @Test("identical strings are fully similar with no highlights")
    func identical() {
        let result = charDiff("same", "same")
        #expect(result.left.isEmpty && result.right.isEmpty)
        #expect(result.similarity == 1)
    }

    @Test("very long lines skip char diff but still score similarity")
    func longLines() {
        let a = String(repeating: "x", count: CharDiff.maxLineLength + 500)
        let b = a + "y"
        let result = charDiff(a, b)
        #expect(result.left.isEmpty && result.right.isEmpty)   // highlighting skipped
        #expect(result.similarity > 0.9)                       // but still recognized as similar
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

    @Test("trailing newline does not create a phantom blank row")
    func trailingNewline() {
        // "a\nb\n" is two lines, not three — the final newline must not show as a numbered blank.
        #expect(LineDiff.split("a\nb\n") == ["a", "b"])
        #expect(LineDiff.split("a\nb") == ["a", "b"])
        #expect(LineDiff.split("") == [""])
        #expect(LineDiff.split("a\n\n") == ["a", ""])   // genuine blank line before EOF is kept
        let doc = LineDiff.document("a\nb\n", "a\nb\n")
        #expect(doc.isIdentical)
        #expect(doc.allRows.count == 2)
    }

    @Test("intra-line highlights are produced for similar lines")
    func highlights() {
        let doc = LineDiff.document("color = red", "color = blue")
        let modified = doc.allRows.first { $0.kind == .modified }
        #expect(modified != nil)
        #expect(!(modified?.rightHighlights.isEmpty ?? true))
    }

    @Test("dissimilar adjacent lines stay a deletion and insertion")
    func dissimilarLines() {
        let doc = LineDiff.document("apple", "zzzzz")
        #expect(doc.allRows.map(\.kind) == [.deleted, .inserted])
        #expect(doc.stats.deletions == 1)
        #expect(doc.stats.insertions == 1)
        #expect(doc.stats.modifications == 0)
    }

    @Test("whitespace policies ignore only the requested differences")
    func whitespacePolicies() {
        let edgeOnly = LineDiff.document("  value  ", "value", whitespace: .trimEdges)
        #expect(edgeOnly.isIdentical)
        #expect(edgeOnly.allRows.first?.leftText == "  value  ")
        #expect(edgeOnly.allRows.first?.rightText == "value")

        let internalSpacing = LineDiff.document("let value = 1", "letvalue=1",
                                                whitespace: .trimEdges)
        #expect(!internalSpacing.isIdentical)
        #expect(LineDiff.document("let value = 1", "letvalue=1",
                                  whitespace: .ignoreAll).isIdentical)
        #expect(!LineDiff.document("a b", "ab", whitespace: .significant).isIdentical)
    }

    @Test("format diagnostics catch mixed line endings and final newlines")
    func textFormatDiagnostics() {
        let mixed = textFormatDifferences("a\nb\r\n", "a\r\nb\n")
        #expect(mixed.contains("Line ending sequences differ between A and B."))

        let finalOnly = textFormatDifferences("value\n", "value")
        #expect(finalOnly == ["A has a final newline; B does not."])
    }
}

@Suite("Git parsing")
struct GitParsingTests {
    private let repo = GitRepository(url: URL(fileURLWithPath: "/tmp"))

    @Test("name-status -z handles unicode names and renames (old→new order)")
    func nameStatusZ() {
        // Exactly what `git diff --name-status -M -z` emits (verified against a scratch repo).
        let out = "M\u{0}café.txt\u{0}R100\u{0}old.txt\u{0}new name.txt\u{0}D\u{0}sub/keep.txt\u{0}"
        let files = repo.parseNameStatus(out)
        #expect(files.count == 3)
        #expect(files[0].status == .modified && files[0].path == "café.txt")
        #expect(files[1].status == .renamed && files[1].oldPath == "old.txt" && files[1].path == "new name.txt")
        #expect(files[2].status == .deleted && files[2].path == "sub/keep.txt")
    }

    @Test("porcelain -z handles renames (new→old order) without phantom entries")
    func porcelainZ() {
        // Exactly what `git status --porcelain -uall -z` emits.
        let out = " M café.txt\u{0}R  new name.txt\u{0}old.txt\u{0} M sub/keep.txt\u{0}?? untracked1.txt\u{0}"
        let files = repo.parsePorcelain(out)
        #expect(files.count == 4)                       // no phantom entry from the trailing old-path token
        #expect(files[0].status == .modified && files[0].path == "café.txt")
        #expect(files[1].status == .renamed && files[1].path == "new name.txt" && files[1].oldPath == "old.txt")
        #expect(files[2].status == .modified && files[2].path == "sub/keep.txt")
        #expect(files[3].status == .untracked && files[3].path == "untracked1.txt")
    }

    @Test("changed-file identity is stable across reparses")
    func stableIdentity() {
        let out = "M\u{0}a.txt\u{0}"
        let first = repo.parseNameStatus(out)
        let second = repo.parseNameStatus(out)
        #expect(first[0].id == second[0].id)   // selection/scroll survive a refresh
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

    @Test("adjacent independent edits merge without a stable separator")
    func adjacentIndependentEdits() {
        let hunks = ThreeWayMerge.merge(base: "a\nb", left: "A\nb", right: "a\nB")
        #expect(ThreeWayMerge.conflictCount(hunks) == 0)
        #expect(hunks.map(\.resolution) == [.takeLeft, .takeRight])
        #expect(ThreeWayMerge.mergedText(hunks) == "A\nB")
    }

    @Test("a shared edit and an adjacent one-sided edit merge cleanly")
    func sharedAndAdjacentEdits() {
        let hunks = ThreeWayMerge.merge(base: "a\nb", left: "A\nB", right: "A\nb")
        #expect(ThreeWayMerge.conflictCount(hunks) == 0)
        #expect(ThreeWayMerge.mergedText(hunks) == "A\nB")
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

    @Test("unresolved conflicts are written as git-style markers, never silently dropped")
    func conflictMarkers() {
        let hunks = ThreeWayMerge.merge(base: "value = 1", left: "value = 2", right: "value = 3")
        let output = ThreeWayMerge.mergedText(hunks)
        #expect(output.contains("<<<<<<< left"))
        #expect(output.contains("value = 2"))
        #expect(output.contains("======="))
        #expect(output.contains("value = 3"))
        #expect(output.contains(">>>>>>> right"))
    }

    @Test("CRLF and final newline are preserved in merged output")
    func lineEndingPreserved() {
        let base = "a\r\nb\r\nc\r\n"
        let style = ThreeWayMerge.lineStyle(of: base)
        #expect(style.ending == "\r\n")
        #expect(style.finalNewline)
        let hunks = ThreeWayMerge.merge(base: base, left: "A\r\nb\r\nc\r\n", right: "a\r\nb\r\nC\r\n")
        let output = ThreeWayMerge.mergedText(hunks, lineEnding: style.ending, finalNewline: style.finalNewline)
        #expect(output.hasSuffix("\r\n"))
        #expect(output.contains("A\r\n"))
        #expect(!output.contains("\n\n"))   // no bare-LF lines leaked in
    }

    @Test("a file containing exactly one newline round-trips")
    func singleNewlinePreserved() {
        let hunks = ThreeWayMerge.merge(base: "\n", left: "\n", right: "\n")
        let style = ThreeWayMerge.lineStyle(of: "\n")
        #expect(ThreeWayMerge.mergedText(hunks, lineEnding: style.ending,
                                         finalNewline: style.finalNewline) == "\n")
        #expect(ThreeWayMerge.mergedText([], finalNewline: true) == "")
    }

    @Test("line style chooses the most frequent terminator")
    func dominantLineEnding() {
        let lfDominant = ThreeWayMerge.lineStyle(of: "a\nb\nc\r\n")
        #expect(lfDominant.ending == "\n")
        #expect(lfDominant.finalNewline)

        let crDominant = ThreeWayMerge.lineStyle(of: "a\rb\rc\n")
        #expect(crDominant.ending == "\r")
        #expect(crDominant.finalNewline)
    }

    @Test("one-sided line-ending and final-newline edits are preserved")
    func oneSidedLineStyleEdits() {
        let crlf = ThreeWayMerge.lineStyleDecision(base: "", left: "added\r\n", right: "")
        #expect(crlf.selected.ending == "\r\n")
        #expect(crlf.selected.finalNewline)
        #expect(!crlf.hasConflict)
        let added = ThreeWayMerge.merge(base: "", left: "added\r\n", right: "")
        #expect(ThreeWayMerge.mergedText(added, lineEnding: crlf.selected.ending,
                                         finalNewline: crlf.selected.finalNewline) == "added\r\n")

        let finalNewline = ThreeWayMerge.lineStyleDecision(base: "x", left: "x\n", right: "x")
        #expect(finalNewline.selected.finalNewline)
        #expect(!finalNewline.hasConflict)
        let unchangedContent = ThreeWayMerge.merge(base: "x", left: "x\n", right: "x")
        #expect(ThreeWayMerge.mergedText(unchangedContent,
                                         lineEnding: finalNewline.selected.ending,
                                         finalNewline: finalNewline.selected.finalNewline) == "x\n")
    }

    @Test("different two-sided line styles require resolution")
    func conflictingLineStyles() {
        let decision = ThreeWayMerge.lineStyleDecision(base: "x", left: "x\r\n", right: "x\r")
        #expect(decision.hasConflict)
        #expect(decision.selected == decision.left)
    }

    @Test("partial conflict markers are still detected before saving")
    func partialConflictMarkers() {
        #expect(containsConflictMarkerFragment("<<<<<<< left\nvalue"))
        #expect(containsConflictMarkerFragment("value\n=======\nother"))
        #expect(!containsConflictMarkerFragment("ordinary text"))
    }
}
