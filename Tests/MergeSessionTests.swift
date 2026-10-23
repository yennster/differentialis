import Testing
import Foundation
@testable import Differentialis

@Suite("Merge session")
@MainActor
struct MergeSessionTests {
    private func loadedSession(base: String = "value = 1\nshared",
                               left: String = "value = 2\nshared",
                               right: String = "value = 3\nshared") async -> MergeSession {
        let session = MergeSession(base: .text(content: base, name: "base"),
                                   left: .text(content: left, name: "left"),
                                   right: .text(content: right, name: "right"))
        await session.load()
        return session
    }

    private func firstConflict(_ session: MergeSession) -> MergeHunk? {
        session.hunks.first { $0.isConflict }
    }

    @Test("a fresh load needs no saving and is not reloaded by a returning view")
    func freshLoad() async {
        let session = await loadedSession()
        #expect(session.loaded)
        #expect(!session.needsLoad)
        #expect(!session.hasUnsavedChanges)
        #expect(session.unresolvedConflicts == 1)
        #expect(session.resultText.contains("<<<<<<< left"))
    }

    @Test("resolving a conflict marks unsaved work and regenerates the Result")
    func resolveConflict() async throws {
        let session = await loadedSession()
        let conflict = try #require(firstConflict(session))
        session.resolve(hunk: conflict.id, as: .takeRight, lines: conflict.rightLines)
        #expect(session.hasUnsavedChanges)
        #expect(session.unresolvedConflicts == 0)
        #expect(session.resultText == "value = 3\nshared")
    }

    @Test("a manual Result edit is kept when hunk choices change, until Reset from Review")
    func manualEditIsAuthoritative() async throws {
        let session = await loadedSession()
        session.editResult("hand written")
        #expect(session.resultDirty)
        #expect(session.hasUnsavedChanges)

        let conflict = try #require(firstConflict(session))
        session.resolve(hunk: conflict.id, as: .takeLeft, lines: conflict.leftLines)
        #expect(session.resultText == "hand written")

        session.resetResultFromReview()
        #expect(!session.resultDirty)
        #expect(session.resultText == "value = 2\nshared")
    }

    @Test("re-setting the same Result text is not an edit")
    func unchangedEditIsIgnored() async {
        let session = await loadedSession()
        session.editResult(session.resultText)
        #expect(!session.resultDirty)
        #expect(!session.hasUnsavedChanges)
    }

    @Test("choosing a line style resolves the format conflict and counts as work")
    func lineStyleChoice() async {
        let session = await loadedSession(base: "a\nb\n", left: "a\r\nb\r\n", right: "a\nb")
        #expect(session.lineStyleConflict)
        session.resolveLineStyle(session.leftLineStyle)
        #expect(!session.lineStyleConflict)
        #expect(session.hasUnsavedChanges)
        #expect(session.resultText == "a\r\nb\r\n")
    }

    @Test("saving clears unsaved work; a later change sets it again")
    func markSaved() async throws {
        let session = await loadedSession()
        let conflict = try #require(firstConflict(session))
        session.resolve(hunk: conflict.id, as: .takeLeft, lines: conflict.leftLines)
        session.markSaved()
        #expect(!session.hasUnsavedChanges)
        session.editResult("more")
        #expect(session.hasUnsavedChanges)
    }

    @Test("reloading discards choices, edits, and the unsaved flag")
    func reloadResets() async throws {
        let session = await loadedSession()
        let conflict = try #require(firstConflict(session))
        session.resolve(hunk: conflict.id, as: .takeLeft, lines: conflict.leftLines)
        session.editResult("hand written")
        session.presentation = .result

        await session.load()
        #expect(!session.hasUnsavedChanges)
        #expect(!session.resultDirty)
        #expect(session.unresolvedConflicts == 1)
        #expect(session.resultText.contains("<<<<<<< left"))
        #expect(session.presentation == .result)
    }

    @Test("a merge comparison keeps one session for its lifetime")
    func comparisonOwnsSession() async throws {
        let comparison = Comparison.merge(base: .text(content: "x", name: "base"),
                                          left: .text(content: "y", name: "left"),
                                          right: .text(content: "z", name: "right"))
        let session = try #require(comparison.mergeSession)
        await session.load()
        let conflict = try #require(firstConflict(session))
        session.resolve(hunk: conflict.id, as: .takeRight, lines: conflict.rightLines)

        // A view rebuilt from the same comparison sees the same, already-resolved session.
        let copy = comparison
        #expect(copy.mergeSession === session)
        #expect(copy.mergeSession?.needsLoad == false)
        #expect(copy.mergeSession?.resultText == "z")
        #expect(Comparison.make(a: .empty(name: "a"), b: .empty(name: "b")).mergeSession == nil)
    }
}
