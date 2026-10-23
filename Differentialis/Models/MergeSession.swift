import Foundation
import Observation

/// The working state of a 3-way merge: the three sources, the hunk and line-style choices, and
/// the Result text. A reference type retained by `Comparison` (like `PastedTextDocument`), so the
/// user's work survives the detail view being torn down when they switch to another sidebar item
/// and back. It is not persisted across launches.
@Observable
final class MergeSession {
    enum Presentation: Hashable { case review, result }

    let base: ComparisonSource
    let left: ComparisonSource
    let right: ComparisonSource

    private(set) var hunks: [MergeHunk] = []
    private(set) var loadError: String?
    private(set) var loaded = false
    private(set) var lineEnding = "\n"
    private(set) var finalNewline = false
    var presentation = Presentation.review
    private(set) var resultText = ""
    private(set) var resultDirty = false
    private(set) var baseLineStyle = TextLineStyle(ending: "\n", finalNewline: false)
    private(set) var leftLineStyle = TextLineStyle(ending: "\n", finalNewline: false)
    private(set) var rightLineStyle = TextLineStyle(ending: "\n", finalNewline: false)
    private(set) var lineStyleConflict = false
    /// A hunk choice, line-style choice, or Result edit made since the last load or save.
    private(set) var hasUnsavedChanges = false
    @ObservationIgnored private var loadToken: UUID?

    init(base: ComparisonSource, left: ComparisonSource, right: ComparisonSource) {
        self.base = base
        self.left = left
        self.right = right
    }

    var unresolvedConflicts: Int {
        hunks.filter { $0.isConflict && !$0.resolved }.count + (lineStyleConflict ? 1 : 0)
    }

    /// True until the first load has finished (or after a failed one), unless a load is running.
    /// A view appearing again for an already-loaded session must not reload and wipe the work.
    var needsLoad: Bool { !loaded && loadToken == nil }

    var defaultSaveName: String {
        if case .file(let url) = left { return url.lastPathComponent }
        if case .file(let url) = base { return url.lastPathComponent }
        return "merged.txt"
    }

    /// Reads the three sources and runs the merge, replacing every choice and edit.
    @MainActor
    func load() async {
        let token = UUID()
        loadToken = token
        loaded = false
        loadError = nil
        // The caller has already agreed to discard any work, so a failed reload must not leave
        // the session claiming unsaved changes it can no longer show or save.
        hasUnsavedChanges = false
        let base = base, left = left, right = right
        // Read all three files and run the diff3 merge off the main actor — for large files this
        // is heavy and would otherwise freeze the UI.
        let outcome: (([MergeHunk], MergeLineStyleDecision)?, String?) = await offMain {
            do {
                let baseText = try base.loadText()
                let leftText = try left.loadText()
                let rightText = try right.loadText()
                let hunks = ThreeWayMerge.merge(base: baseText, left: leftText, right: rightText)
                let style = ThreeWayMerge.lineStyleDecision(base: baseText,
                                                            left: leftText,
                                                            right: rightText)
                return ((hunks, style), nil)
            } catch {
                return (nil, error.localizedDescription)
            }
        }
        // A newer Refresh supersedes this load. The result is applied even if the view that
        // started it has gone away: it belongs to the session, not the view.
        guard token == loadToken else { return }
        loadToken = nil
        if let result = outcome.0 {
            install(hunks: result.0, style: result.1)
        } else {
            loadError = outcome.1
        }
    }

    func install(hunks: [MergeHunk], style: MergeLineStyleDecision) {
        self.hunks = hunks
        lineEnding = style.selected.ending
        finalNewline = style.selected.finalNewline
        baseLineStyle = style.base
        leftLineStyle = style.left
        rightLineStyle = style.right
        lineStyleConflict = style.hasConflict
        resultDirty = false
        synchronizeResult()
        hasUnsavedChanges = false
        loaded = true
    }

    func resolve(hunk id: MergeHunk.ID, as resolution: MergeResolution, lines: [String]) {
        guard let index = hunks.firstIndex(where: { $0.id == id }) else { return }
        hunks[index].resolution = resolution
        hunks[index].chosen = lines
        hunks[index].resolved = true
        hasUnsavedChanges = true
        if !resultDirty { synchronizeResult() }
    }

    func resolveLineStyle(_ style: TextLineStyle) {
        lineEnding = style.ending
        finalNewline = style.finalNewline
        lineStyleConflict = false
        hasUnsavedChanges = true
        if !resultDirty { synchronizeResult() }
    }

    /// A manual edit in the Result tab. From here on the text is authoritative: hunk and format
    /// choices no longer regenerate it until `resetResultFromReview()`.
    func editResult(_ text: String) {
        // Compare scalars, not `String` equality: canonically equivalent text (é vs e + U+0301)
        // is still a different file once saved.
        guard !text.unicodeScalars.elementsEqual(resultText.unicodeScalars) else { return }
        resultText = text
        resultDirty = true
        hasUnsavedChanges = true
    }

    func resetResultFromReview() {
        guard resultDirty else { return }
        resultDirty = false
        synchronizeResult()
        hasUnsavedChanges = true
    }

    /// The current Result has been written to disk.
    func markSaved() {
        hasUnsavedChanges = false
    }

    private func synchronizeResult() {
        resultText = ThreeWayMerge.mergedText(hunks, lineEnding: lineEnding,
                                               finalNewline: finalNewline)
    }
}

extension MergeSession: Hashable {
    static func == (lhs: MergeSession, rhs: MergeSession) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
