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
        session.resolve(hunk: conflict.id, as: .takeRight)
        #expect(session.hasUnsavedChanges)
        #expect(session.unresolvedConflicts == 0)
        #expect(session.resultText == "value = 3\nshared")
    }

    @Test("choosing Base keeps the hunk re-choosable and still clears the conflict")
    func resolveToBase() async throws {
        let session = await loadedSession()
        let conflict = try #require(firstConflict(session))
        session.resolve(hunk: conflict.id, as: .takeBase)
        #expect(session.hasUnsavedChanges)
        #expect(session.unresolvedConflicts == 0)
        #expect(session.resultText == "value = 1\nshared")
        #expect(session.hunks.first { $0.id == conflict.id }?.resolution == .takeBase)

        session.resolve(hunk: conflict.id, as: .takeLeft)
        #expect(session.resultText == "value = 2\nshared")
    }

    @Test("a manual Result edit is kept when hunk choices change, until Reset from Review")
    func manualEditIsAuthoritative() async throws {
        let session = await loadedSession()
        session.editResult("hand written")
        #expect(session.resultDirty)
        #expect(session.hasUnsavedChanges)

        let conflict = try #require(firstConflict(session))
        session.resolve(hunk: conflict.id, as: .takeLeft)
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

    @Test("a canonically equivalent but different Result is still an edit")
    func equivalentTextIsAnEdit() async {
        let session = await loadedSession(base: "caf\u{E9}", left: "caf\u{E9}", right: "caf\u{E9}")
        session.editResult("cafe\u{301}")
        #expect(session.resultDirty)
        #expect(Array(session.resultText.unicodeScalars) == Array("cafe\u{301}".unicodeScalars))
    }

    @Test("Reset from Review counts as work, and does nothing on an unedited Result")
    func resetCountsAsWork() async {
        let session = await loadedSession()
        session.resetResultFromReview()
        #expect(!session.hasUnsavedChanges)
        session.editResult("hand written")
        session.markSaved()
        session.resetResultFromReview()
        #expect(session.hasUnsavedChanges)
    }

    @Test("a running load is not restarted by a returning view")
    func inFlightLoad() async {
        let session = MergeSession(base: .text(content: "a", name: "base"),
                                   left: .text(content: "b", name: "left"),
                                   right: .text(content: "c", name: "right"))
        #expect(session.needsLoad)
        let load = Task { await session.load() }
        await Task.yield()
        #expect(!session.loaded)
        #expect(!session.needsLoad)
        await load.value
        #expect(session.loaded)
        #expect(!session.needsLoad)
    }

    @Test("a failed reload reports the error, clears unsaved work, and is retried when the view returns")
    func failedLoad() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("differentialis-merge-\(UUID().uuidString).txt")
        try "value = 2\nshared".write(to: url, atomically: true, encoding: .utf8)
        let session = MergeSession(base: .text(content: "value = 1\nshared", name: "base"),
                                   left: .file(url),
                                   right: .text(content: "value = 3\nshared", name: "right"))
        await session.load()
        let conflict = try #require(firstConflict(session))
        session.resolve(hunk: conflict.id, as: .takeLeft)
        #expect(session.hasUnsavedChanges)

        try FileManager.default.removeItem(at: url)
        await session.load()
        #expect(session.loadError != nil)
        #expect(!session.loaded)
        #expect(session.needsLoad)
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
        session.resolve(hunk: conflict.id, as: .takeLeft)
        session.markSaved()
        #expect(!session.hasUnsavedChanges)
        session.editResult("more")
        #expect(session.hasUnsavedChanges)
    }

    @Test("reloading discards choices, edits, and the unsaved flag")
    func reloadResets() async throws {
        let session = await loadedSession()
        let conflict = try #require(firstConflict(session))
        session.resolve(hunk: conflict.id, as: .takeLeft)
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
        session.resolve(hunk: conflict.id, as: .takeRight)

        // A view rebuilt from the same comparison sees the same, already-resolved session.
        let copy = comparison
        #expect(copy.mergeSession === session)
        #expect(copy.mergeSession?.needsLoad == false)
        #expect(copy.mergeSession?.resultText == "z")
        #expect(Comparison.make(a: .empty(name: "a"), b: .empty(name: "b")).mergeSession == nil)
    }
}
