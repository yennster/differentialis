import SwiftUI
import UniformTypeIdentifiers

/// A whole `<<<<<<<` … `>>>>>>>` conflict block. Stricter than a fragment check, since a lone
/// `=======` line is ordinary content in Markdown and reStructuredText.
func containsConflictMarkers(_ text: String) -> Bool {
    var open = false
    for line in text.components(separatedBy: .newlines) {
        if line.hasPrefix("<<<<<<<") { open = true }
        else if open, line.hasPrefix(">>>>>>>") { return true }
    }
    return false
}

func containsConflictMarkerFragment(_ text: String) -> Bool {
    text.components(separatedBy: .newlines).contains { line in
        line.hasPrefix("<<<<<<<") || line == "=======" || line.hasPrefix(">>>>>>>")
    }
}

struct MergeView: View {
    @Bindable var session: MergeSession
    @Environment(AppModel.self) private var model
    /// The region Next/Previous Change last moved to, highlighted in Review.
    @State private var currentStopID: UUID?
    /// Bumped on every navigation so pressing ⌘] on the only conflict scrolls back to it.
    @State private var scrollRequest = 0
    /// Scroll identity for the line-ending choice, which is not a hunk.
    @State private var lineStyleStopID = UUID()

    // Find (⌘F) in Review, and Go to Line (⌘L) in Result. In Result, Find is the editor's own.
    @State private var findVisible = false
    @State private var findQuery = ""
    @State private var findOptions = TextSearchOptions()
    @State private var findMatches: [MergeSearchMatch] = []
    @State private var findByHunk: [UUID: HunkFindHighlights] = [:]
    @State private var findIndex: Int?
    @State private var findFocusRequest = 0
    @State private var findScrollRequest = 0
    @State private var goToLineVisible = false
    @State private var goToLineFocusRequest = 0
    @State private var resultEditorHandle = CodeEditorHandle()
    /// Review line position of the current match (`MergeSearchMatch.position`), so re-searching
    /// after a resolve or an option change carries on there.
    @State private var findAnchor: Int?
    /// The line the current match is on, to scroll only when a re-search moves it.
    @State private var findCurrentLine: MergeLineID?
    @FocusState private var findFieldFocused: Bool
    @FocusState private var goToLineFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            if findVisible && canFindInReview {
                FindBar(query: $findQuery, options: $findOptions,
                        matchCount: findMatches.count, currentIndex: findIndex,
                        focusRequest: findFocusRequest, fieldFocused: $findFieldFocused,
                        next: { stepFind(1) }, previous: { stepFind(-1) },
                        close: { findVisible = false })
                Divider().opacity(0.4)
            }
            if goToLineVisible && session.loaded && session.loadError == nil {
                GoToLineBar(side: .constant(.left), showsSidePicker: false,
                            focusRequest: goToLineFocusRequest, fieldFocused: $goToLineFieldFocused,
                            go: goToResultLine, close: { goToLineVisible = false })
                Divider().opacity(0.4)
            }
            if let loadError = session.loadError {
                ContentUnavailableView("Couldn’t load files", systemImage: "exclamationmark.triangle",
                                       description: Text(loadError))
            } else if !session.loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if session.presentation == .review {
                review
            } else {
                resultEditor
            }
        }
        .codeFontZoomGesture()
        // The session outlives this view, so coming back to an already-loaded merge keeps its
        // choices and edits instead of re-reading the sources.
        .task { if session.needsLoad { await session.load() } }
        .task(id: findKey) { await search() }
        .focusedSceneValue(\.diffCommands, DiffCommandActions(
            nextChange: canNavigate ? { navigate(1) } : nil,
            prevChange: canNavigate ? { navigate(-1) } : nil,
            refresh: {
                guard session.confirmDiscardingChanges(before: .reload) else { return }
                currentStopID = nil
                Task { await session.load() }
            },
            find: canFind ? { showFind() } : nil,
            findNext: canFind ? { stepFind(1) } : nil,
            findPrevious: canFind ? { stepFind(-1) } : nil,
            goToLine: canFind ? { showGoToLine() } : nil,
            findInTextView: session.presentation == .result))
    }

    private var review: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if session.lineStyleConflict {
                        LineStyleConflictBlock(base: session.baseLineStyle,
                                               left: session.leftLineStyle,
                                               right: session.rightLineStyle,
                                               isCurrent: currentStopID == lineStyleStopID,
                                               choose: session.resolveLineStyle)
                            .id(lineStyleStopID)
                    }
                    ForEach(session.hunks) { hunk in
                        HunkBlock(hunk: hunk, isCurrent: hunk.id == currentStopID,
                                  find: findHighlights(for: hunk.id)) { source in
                            session.resolve(hunk: hunk.id, as: source)
                            // Navigation carries on from the hunk the user just worked on.
                            currentStopID = hunk.id
                        }
                        .id(hunk.id)
                    }
                }
                .padding(.vertical, 6)
            }
            .background(Theme.well)
            .onChange(of: scrollRequest) { _, _ in
                guard let id = currentStopID else { return }
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: findScrollRequest) { _, request in
                guard let findIndex, findIndex < findMatches.count else { return }
                let match = findMatches[findIndex]
                // Bring the hunk into the lazy stack, then centre the matching line: an unchanged
                // hunk can be thousands of lines long.
                proxy.scrollTo(match.hunkID, anchor: .center)
                Task { @MainActor in
                    // Give the lazy stack a moment to lay the hunk out, so its lines have ids.
                    try? await Task.sleep(for: .milliseconds(30))
                    guard request == findScrollRequest else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(MergeLineID(hunk: match.hunkID, part: match.part, line: match.line),
                                       anchor: .center)
                    }
                }
            }
            // The conflict chip can switch from Result to Review, which mounts this list after the
            // request was made, so a pending target is honoured on appear as well.
            .onAppear {
                // Deferred a turn so the lazy list has laid out before scrollTo runs.
                guard currentStopID != nil else { return }
                Task { @MainActor in scrollRequest &+= 1 }
            }
        }
    }

    // MARK: - Find and Go to Line

    private var canFind: Bool { session.loaded && session.loadError == nil }
    private var canFindInReview: Bool { canFind && session.presentation == .review }

    /// Re-run Find when the query, its options, or a hunk's resolution changes.
    private struct FindKey: Hashable {
        let visible: Bool
        let query: String
        let options: TextSearchOptions
        let hunks: [UUID]
        let resolutions: [MergeResolution]
    }

    private var findKey: FindKey {
        FindKey(visible: findVisible && canFindInReview, query: findQuery, options: findOptions,
                hunks: session.hunks.map(\.id), resolutions: session.hunks.map(\.resolution))
    }

    private func showFind() {
        if session.presentation == .result {
            // Result is a text view with its own find bar.
            resultEditorHandle.perform(.showFindInterface)
            return
        }
        goToLineVisible = false
        findVisible = true
        findFocusRequest &+= 1
    }

    private func showGoToLine() {
        findVisible = false
        goToLineVisible = true
        goToLineFocusRequest &+= 1
    }

    /// Review has no line numbers, so Go to Line opens the line in the Result the merge saves.
    private func goToResultLine(_ line: Int) {
        session.presentation = .result
        resultEditorHandle.goToLine(line)
    }

    private func stepFind(_ delta: Int) {
        if session.presentation == .result {
            resultEditorHandle.perform(delta > 0 ? .nextMatch : .previousMatch)
            return
        }
        if !findVisible { showFind() }
        guard var next = TextSearch.step(from: findIndex, by: delta, count: findMatches.count) else { return }
        // After ⌘] / ⌘[ moved to another hunk, carry on from there instead.
        if findAnchor == nil, let currentStopID,
           let anchor = TextSearch.reviewLinePositions(of: session.hunks)[currentStopID] {
            let atOrAfter = TextSearch.startIndex(of: findMatches, at: anchor) { $0.position } ?? 0
            next = delta > 0 ? atOrAfter : (atOrAfter - 1 + findMatches.count) % findMatches.count
        }
        setCurrentMatch(next)
        findScrollRequest &+= 1
    }

    private func setCurrentMatch(_ index: Int?) {
        findIndex = index
        guard let index, index < findMatches.count else {
            findAnchor = nil
            findCurrentLine = nil
            return
        }
        let match = findMatches[index]
        findAnchor = match.position
        findCurrentLine = MergeLineID(hunk: match.hunkID, part: match.part, line: match.line)
    }

    private func search() async {
        guard findKey.visible, !findQuery.isEmpty else {
            findMatches = []
            findByHunk = [:]
            setCurrentMatch(nil)
            return
        }
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }
        let query = findQuery, options = findOptions, hunks = session.hunks
        let found = await offMain {
            TextSearch.matches(of: query, in: hunks, options: options, limit: TextSearch.matchLimit + 1)
        }
        guard !Task.isCancelled else { return }
        var byHunk: [UUID: HunkFindHighlights] = [:]
        for match in found {
            byHunk[match.hunkID, default: [:]][match.part, default: [:]][match.line, default: LineFindHighlights()]
                .matches.append(match.range)
        }
        findMatches = found
        findByHunk = byHunk
        // Carry on from the match the user was on (resolving a hunk re-runs the search), else from
        // the hunk Next/Previous Change last moved to.
        let anchor = findAnchor ?? currentStopID.flatMap { TextSearch.reviewLinePositions(of: hunks)[$0] }
        let previousLine = findCurrentLine
        setCurrentMatch(TextSearch.startIndex(of: found, at: anchor) { $0.position })
        // Don't move the view when the current match is still on the line it was on.
        if findIndex != nil, findCurrentLine != previousLine { findScrollRequest &+= 1 }
    }

    /// Find highlights for one hunk, by part and line, with the current match marked.
    private func findHighlights(for hunkID: UUID) -> HunkFindHighlights {
        var result = findByHunk[hunkID] ?? [:]
        if let findIndex, findIndex < findMatches.count, findMatches[findIndex].hunkID == hunkID {
            let match = findMatches[findIndex]
            result[match.part, default: [:]][match.line, default: LineFindHighlights()].current = match.range
        }
        return result
    }

    // MARK: - Navigation

    private var navigationStops: [MergeNavigation.Stop] {
        MergeNavigation.stops(hunks: session.hunks, lineStyleConflict: session.lineStyleConflict,
                              lineStyleID: lineStyleStopID)
    }

    /// ⌘] / ⌘[ act on the Review list; the Result editor keeps its own text navigation.
    private var canNavigate: Bool {
        session.loaded && session.loadError == nil && session.presentation == .review
            && navigationStops.contains { $0.changed }
    }

    private func navigate(_ delta: Int) {
        guard let target = MergeNavigation.target(from: currentStopID, delta: delta, in: navigationStops)
        else { return }
        move(to: target)
    }

    private func jumpToFirstConflict() {
        guard let target = MergeNavigation.firstUnresolvedConflict(in: navigationStops) else { return }
        session.presentation = .review
        move(to: target)
    }

    private func move(to id: UUID) {
        currentStopID = id
        // The next search or ⌘G starts from here, not from the last match.
        findAnchor = nil
        scrollRequest &+= 1
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label("3-Way Merge", systemImage: "arrow.triangle.merge")
                .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 6) {
                legend("Base", .secondary)
                legend("Left", Theme.removed)
                legend("Right", Theme.modified)
            }
            Spacer()
            if session.loaded {
                GlassSegmentedControl(
                    selection: $session.presentation,
                    options: [
                        .init(value: .review, title: "Review", systemImage: "list.bullet.rectangle"),
                        .init(value: .result, title: "Result", systemImage: "square.and.pencil"),
                    ],
                    compact: true)
                .fixedSize()
            }
            if session.unresolvedConflicts > 0 {
                let count = session.unresolvedConflicts
                Button(action: jumpToFirstConflict) {
                    StatChip(text: "\(count) conflict\(count == 1 ? "" : "s")",
                             color: Theme.conflict, systemImage: "exclamationmark.triangle.fill")
                }
                .buttonStyle(.plain)
                .help("Show the first unresolved conflict (⌘] for the next)")
                .accessibilityLabel("\(count) unresolved conflict\(count == 1 ? "" : "s")")
                .accessibilityHint("Shows the first unresolved conflict")
            } else if session.loaded {
                StatChip(text: "Resolved", color: Theme.added, systemImage: "checkmark.seal.fill")
            }
            if session.resultDirty {
                StatChip(text: "Edited", color: Theme.brandAlt, systemImage: "pencil")
            }
            Button {
                // A merge from git mergetool is finished by saving it resolved: git is waiting on the
                // close. A save that keeps conflict markers is progress, so the merge stays open.
                let finishes = session.savesToOutput
                if session.saveInteractively(), finishes, session.outputResolved {
                    model.finishMerge(session)
                }
            } label: {
                Label(session.savesToOutput ? "Save" : "Save Merged…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.glass)
            .disabled(!session.loaded)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var resultEditor: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(session.resultDirty
                     ? "Manual edits take precedence over the hunk selections."
                     : "This is the exact text that will be saved.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Spacer()
                if session.resultDirty {
                    Button("Reset from Review") {
                        session.resetResultFromReview()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(.ultraThinMaterial)

            PlainCodeEditor(text: Binding(
                get: { session.resultText },
                set: { session.editResult($0) }),
                font: DiffEditorStyle.codeFont(Theme.codeFontSize),
                accessibilityLabel: "Merged result",
                handle: resultEditorHandle)
                .padding(8)
                .background(Theme.well)
        }
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

/// The save and discard prompts for a merge session. They live with the view layer because they
/// run AppKit alerts and panels; `AppModel` uses them when closing a merge or quitting.
@MainActor
extension MergeSession {
    enum DiscardReason { case reload, close(title: String) }

    /// Asks before an action that would throw away unsaved merge work. Returns true when the
    /// action may go ahead: there was nothing to lose, the user saved, or chose not to save.
    func confirmDiscardingChanges(before reason: DiscardReason) -> Bool {
        guard loaded, hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        switch reason {
        case .reload:
            alert.messageText = "Save the merge before reloading?"
            alert.informativeText = "Reloading re-reads the files and discards your conflict choices and Result edits."
        case .close(let title):
            alert.messageText = "Save “\(title)” before closing?"
            alert.informativeText = "Your conflict choices and Result edits will be lost if you don’t save them."
        }
        alert.addButton(withTitle: savesToOutput ? "Save" : "Save…")
        alert.addButton(withTitle: "Cancel")
        let discard = alert.addButton(withTitle: "Don’t Save")
        discard.keyEquivalent = "d"
        discard.keyEquivalentModifierMask = .command
        switch alert.runModal() {
        case .alertFirstButtonReturn: return saveInteractively()
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    /// Runs the save flow: conflict warnings, then the save panel. Returns true only when the
    /// Result was written.
    @discardableResult
    func saveInteractively() -> Bool {
        // Save rewrites every line to the chosen line ending, so an edited result needs that
        // choice made too.
        if lineStyleConflict {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Choose an output line-ending style"
            alert.informativeText = "Left and right use different line endings. Resolve the formatting conflict in Review before saving."
            alert.addButton(withTitle: "Review")
            alert.runModal()
            presentation = .review
            return false
        }

        // Never silently write the left side over an unresolved conflict — warn, then emit
        // standard conflict markers so nothing is lost.
        // A whole marker block: a lone ======= line is a Markdown or reStructuredText heading.
        let conflictMarkersRemain = containsConflictMarkers(resultText)
        if (!resultDirty && unresolvedConflicts > 0) || conflictMarkersRemain {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Unresolved conflicts"
            if conflictMarkersRemain {
                alert.informativeText = "The result still contains conflict markers. They will be saved as shown so you can finish resolving them later."
            } else {
                alert.informativeText = "\(unresolvedConflicts) conflict\(unresolvedConflicts == 1 ? " is" : "s are") still unresolved. It will be written with conflict markers so no content is lost."
            }
            alert.addButton(withTitle: "Save with Markers")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
        }

        let url: URL
        if savesToOutput, let output {
            // git mergetool named the file to write; asking again would just invite a wrong answer.
            url = output
        } else {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = defaultSaveName
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let chosen = panel.url else { return false }
            url = chosen
        }

        do {
            try write(to: url)
            return true
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn’t save the merged file"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return false
        }
    }
}

private struct LineStyleConflictBlock: View {
    let base: TextLineStyle
    let left: TextLineStyle
    let right: TextLineStyle
    var isCurrent = false
    let choose: (TextLineStyle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Line-ending conflict — choose the output style",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.conflict)
            HStack(spacing: 8) {
                choice("Base", style: base)
                choice("Left", style: left)
                choice("Right", style: right)
            }
        }
        .padding(12)
        .background(Theme.conflict.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.conflict.opacity(0.4)))
        .currentMergeStop(isCurrent, cornerRadius: 10)
        .padding(.horizontal, 12).padding(.vertical, 4)
    }

    private func choice(_ title: String, style: TextLineStyle) -> some View {
        Button {
            choose(style)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 10.5, weight: .bold))
                Text(style.label).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(7)
        }
        .buttonStyle(.bordered)
    }
}

/// Find matches in one hunk: by the part of the hunk, then by line index within that part.
typealias HunkFindHighlights = [MergeSearchPart: [Int: LineFindHighlights]]

/// Scroll identity of one line in merge Review, so Find can centre the matching line.
struct MergeLineID: Hashable {
    let hunk: UUID
    let part: MergeSearchPart
    let line: Int
}

private struct HunkBlock: View {
    let hunk: MergeHunk
    var isCurrent = false
    var find: HunkFindHighlights = [:]
    let choose: (MergeResolution) -> Void

    var body: some View {
        if hunk.resolution == .unchanged {
            unchangedView
        } else if hunk.isConflict && !hunk.resolved {
            conflictView
        } else {
            resolvedView
        }
    }

    private var unchangedView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(hunk.chosen.enumerated()), id: \.offset) { index, line in
                lineText(line, color: .secondary.opacity(0.7), find: find[.chosen]?[index])
                    .id(MergeLineID(hunk: hunk.id, part: .chosen, line: index))
            }
        }
        .padding(.horizontal, 14)
    }

    private var resolvedView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(hunk.resolution.tint).frame(width: 7, height: 7)
                Text("Took \(hunk.resolution.label)").font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(hunk.resolution.tint)
                Spacer()
                sourceMenu
            }
            .padding(.bottom, 3)
            ForEach(Array(hunk.chosen.enumerated()), id: \.offset) { index, line in
                lineText(line, color: .primary, find: find[.chosen]?[index])
                    .id(MergeLineID(hunk: hunk.id, part: .chosen, line: index))
            }
        }
        .padding(10)
        .background(hunk.resolution.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(hunk.resolution.tint.opacity(0.25)))
        .currentMergeStop(isCurrent, cornerRadius: 8)
        .padding(.horizontal, 12).padding(.vertical, 3)
    }

    private var conflictView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.conflict)
                Text("Conflict — choose a side").font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.conflict)
            }
            HStack(alignment: .top, spacing: 8) {
                conflictColumn(title: "Left", part: .left, lines: hunk.leftLines, color: Theme.removed,
                               find: find[.left] ?? [:]) {
                    choose(.takeLeft)
                }
                conflictColumn(title: "Right", part: .right, lines: hunk.rightLines, color: Theme.modified,
                               find: find[.right] ?? [:]) {
                    choose(.takeRight)
                }
            }
            HStack(spacing: 8) {
                Button("Use Both") { choose(.takeBoth) }
                    .buttonStyle(.bordered)
                Button("Use Base") { choose(.takeBase) }
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(Theme.conflict.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.conflict.opacity(0.4)))
        .currentMergeStop(isCurrent, cornerRadius: 10)
        .padding(.horizontal, 12).padding(.vertical, 4)
    }

    private func conflictColumn(title: String, part: MergeSearchPart, lines: [String], color: Color,
                                find: [Int: LineFindHighlights],
                                choose: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 10.5, weight: .bold)).foregroundStyle(color)
                Spacer()
                Button("Use") { choose() }.buttonStyle(.borderless).controlSize(.small).foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    lineText(line, color: .primary, find: find[index])
                        .id(MergeLineID(hunk: hunk.id, part: part, line: index))
                }
                if lines.isEmpty { lineText("(empty)", color: .secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var sourceMenu: some View {
        Menu {
            Button("Left") { choose(.takeLeft) }
            Button("Right") { choose(.takeRight) }
            Button("Both") { choose(.takeBoth) }
            Button("Base") { choose(.takeBase) }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func lineText(_ text: String, color: Color, find: LineFindHighlights? = nil) -> some View {
        // Only lines with matches pay for an attributed string.
        Group {
            if let find, !text.isEmpty {
                Text(highlightedLine(text, ranges: [], color: .clear, find: find))
            } else {
                Text(verbatim: text.isEmpty ? " " : text)
            }
        }
        .font(Theme.codeFont)
        .foregroundStyle(color)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private extension View {
    /// Marks the region Next/Previous Change moved to, with the same brand tint the text diff
    /// uses for its current change.
    func currentMergeStop(_ isCurrent: Bool, cornerRadius: CGFloat) -> some View {
        overlay {
            if isCurrent {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius).fill(Theme.brand.opacity(0.12))
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Theme.brand.opacity(0.6), lineWidth: 1.5)
                }
                .allowsHitTesting(false)
            }
        }
    }
}
