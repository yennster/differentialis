import SwiftUI

func textFormatDifferences(_ a: String, _ b: String) -> [String] {
    let aStyle = ThreeWayMerge.lineStyle(of: a)
    let bStyle = ThreeWayMerge.lineStyle(of: b)
    var differences: [String] = []

    var aEndings = lineEndingSequence(in: a)
    var bEndings = lineEndingSequence(in: b)
    // A missing final newline is reported separately. Remove that one unmatched terminator before
    // comparing styles so the UI does not describe the same difference twice.
    if aStyle.finalNewline != bStyle.finalNewline {
        if aStyle.finalNewline { aEndings.removeLast() }
        if bStyle.finalNewline { bEndings.removeLast() }
    }
    if aEndings != bEndings {
        let aKinds = Set(aEndings)
        let bKinds = Set(bEndings)
        if aKinds.count == 1, bKinds.count == 1,
           let aEnding = aKinds.first, let bEnding = bKinds.first {
            differences.append("Line endings: A uses \(lineEndingName(aEnding)); B uses \(lineEndingName(bEnding)).")
        } else {
            differences.append("Line ending sequences differ between A and B.")
        }
    }
    if aStyle.finalNewline != bStyle.finalNewline {
        differences.append(aStyle.finalNewline
                           ? "A has a final newline; B does not."
                           : "B has a final newline; A does not.")
    }
    return differences
}

private func lineEndingSequence(in text: String) -> [String] {
    var result: [String] = []
    var pendingCR = false
    for scalar in text.unicodeScalars {
        if pendingCR {
            if scalar.value == 0x0A {
                result.append("\r\n")
                pendingCR = false
                continue
            }
            result.append("\r")
            pendingCR = false
        }
        if scalar.value == 0x0D {
            pendingCR = true
        } else if scalar.value == 0x0A {
            result.append("\n")
        }
    }
    if pendingCR { result.append("\r") }
    return result
}

private func lineEndingName(_ ending: String) -> String {
    switch ending {
    case "\r\n": return "CRLF"
    case "\r": return "CR"
    default: return "LF"
    }
}

struct TextComparisonView: View {
    let a: ComparisonSource
    let b: ComparisonSource
    /// Extra controls appended to the toolbar (the pasted-text comparison's Edit / Diff switch).
    var accessory: AnyView? = nil
    @Environment(\.changesetRefresh) private var changesetRefresh
    @Environment(\.changesetRevision) private var changesetRevision

    @State private var document: DiffDocument?
    @AppStorage("diffLayoutUnified") private var unified = false
    /// Where the split columns divide, as a fraction of the view width. Shared across
    /// comparisons and persisted; the PathBar headings track the same value.
    @AppStorage("diffSplitFraction") private var splitFraction = 0.5
    @AppStorage("textWhitespacePolicy") private var whitespacePolicy = WhitespacePolicy.significant
    @State private var expandedGaps: Set<String> = []
    @State private var changeIDs: [UUID] = []
    @State private var currentChange = -1
    @State private var currentChangeID: UUID?
    @State private var loadError: String?
    @State private var formatDifferences: [String] = []
    @State private var loadRequest: UUID?
    /// Rows inside collapsed gaps, by the gap's section ID, so Find and Go to Line can open them.
    @State private var gapByRow: [UUID: String] = [:]

    // Find (⌘F) and Go to Line (⌘L).
    @State private var findVisible = false
    @State private var findQuery = ""
    @State private var findOptions = TextSearchOptions()
    @State private var findMatches: [DiffSearchMatch] = []
    @State private var findHighlights: [UUID: RowFindHighlights] = [:]
    @State private var findIndex: Int?
    @State private var findFocusRequest = 0
    @State private var goToLineVisible = false
    @State private var goToLineSide = DiffSide.left
    @State private var goToLineFocusRequest = 0
    /// The row Go to Line landed on, marked like the current change.
    @State private var lineTargetID: UUID?
    /// A row to scroll to; the token makes a repeat request for the same row scroll again.
    @State private var scrollTarget: ScrollTarget?
    @State private var scrollCounter = 0
    /// Display position of the current match's row, so a new search (or the same search after a
    /// reload or a layout switch) carries on from there.
    @State private var findAnchor: Int?
    /// The diff the last search ran on, to tell a reload from a new query.
    @State private var findDocument: UUID?
    @FocusState private var findFieldFocused: Bool
    @FocusState private var goToLineFieldFocused: Bool
    @FocusState private var diffFocused: Bool

    private struct ScrollTarget: Equatable {
        let id: UUID
        let token: Int
    }

    var body: some View {
        VStack(spacing: 0) {
            PathBar(a: a, b: b, splitFraction: unified ? 0.5 : splitFraction) { toolbar }
            Divider().opacity(0.4)
            // Kept up through a reload, so the bars don't flicker or lose what's typed.
            if findVisible {
                FindBar(query: $findQuery, options: $findOptions,
                        matchCount: findMatches.count, currentIndex: findIndex,
                        focusRequest: findFocusRequest, fieldFocused: $findFieldFocused,
                        next: { stepFind(1) }, previous: { stepFind(-1) },
                        close: { findVisible = false; diffFocused = true })
                Divider().opacity(0.4)
            }
            if goToLineVisible {
                GoToLineBar(side: $goToLineSide, focusRequest: goToLineFocusRequest,
                            fieldFocused: $goToLineFieldFocused,
                            go: goToLine, close: { goToLineVisible = false; diffFocused = true })
                Divider().opacity(0.4)
            }
            content
                .codeFontZoomGesture()
        }
        .task(id: taskKey) { await load() }
        .task(id: findKey) { await search() }
        .focusedSceneValue(\.diffCommands, DiffCommandActions(
            nextChange: { navigate(1) },
            prevChange: { navigate(-1) },
            toggleLayout: { unified.toggle() },
            refresh: { refresh() },
            find: canSearch ? { showFind() } : nil,
            findNext: canSearch ? { stepFind(1) } : nil,
            findPrevious: canSearch ? { stepFind(-1) } : nil,
            goToLine: canSearch ? { showGoToLine() } : nil))
        .focusable()
        .focused($diffFocused)
        .focusEffectDisabled()
        // Not while typing in the Find or Go to Line field: it takes typed brackets.
        .onKeyPress("]") { guard !typingInBar else { return .ignored }; navigate(1); return .handled }
        .onKeyPress("[") { guard !typingInBar else { return .ignored }; navigate(-1); return .handled }
    }

    private var taskKey: String {
        "\(a.displayName)|\(b.displayName)|\(a.subtitle)|\(b.subtitle)|\(whitespacePolicy.rawValue)|\(changesetRevision)"
    }

    private var typingInBar: Bool { findFieldFocused || goToLineFieldFocused }

    /// Find and Go to Line work on a loaded diff that has rows to show.
    private var canSearch: Bool {
        guard let document else { return false }
        return !document.isIdentical
    }

    /// Re-run Find when the query, its options, or the loaded diff changes.
    private struct FindKey: Hashable {
        let visible: Bool
        let query: String
        let options: TextSearchOptions
        let unified: Bool
        let document: UUID?
    }

    private var findKey: FindKey {
        FindKey(visible: findVisible, query: findQuery, options: findOptions, unified: unified,
                document: document?.allRows.first?.id)
    }

    /// Inside an open changeset, refreshing the changeset also reloads this file (its revision is
    /// part of `taskKey`); elsewhere this just reloads the file.
    private func refresh() {
        if let changesetRefresh { changesetRefresh() } else { Task { await load() } }
    }

    @ViewBuilder
    private var content: some View {
        if let document {
            if document.isIdentical && formatDifferences.isEmpty {
                identicalState
            } else if document.isIdentical {
                formatOnlyState
            } else {
                diffScroll(document)
            }
        } else if let loadError {
            ContentUnavailableView("Couldn’t load files", systemImage: "exclamationmark.triangle", description: Text(loadError))
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var identicalState: some View {
        ContentUnavailableView {
            Label("No differences", systemImage: "checkmark.seal.fill")
        } description: {
            Text(whitespacePolicy == .significant
                 ? "A and B are identical."
                 : "A and B match with \(whitespacePolicy.label.lowercased()).")
        }
        .foregroundStyle(Theme.added)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var formatOnlyState: some View {
        ContentUnavailableView {
            Label("Text matches, formatting differs", systemImage: "textformat")
        } description: {
            Text(formatDifferences.joined(separator: "\n"))
        }
        .foregroundStyle(Theme.modified)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        if let document {
            StatChip(text: document.stats.isIdentical && !formatDifferences.isEmpty
                     ? "Formatting differs" : document.stats.summary,
                     color: document.stats.isIdentical && formatDifferences.isEmpty ? Theme.added : .primary)
        }
        HStack(spacing: 6) {
            Button { navigate(-1) } label: { Image(systemName: "chevron.up") }
            Button { navigate(1) } label: { Image(systemName: "chevron.down") }
        }
        .buttonStyle(.borderless)
        .disabled(changeIDs.isEmpty)

        WhitespacePolicyMenu(policy: $whitespacePolicy)

        GlassSegmentedControl(
            selection: $unified,
            options: [
                .init(value: false, title: "Split", systemImage: "rectangle.split.2x1"),
                .init(value: true, title: "Unified", systemImage: "list.bullet"),
            ],
            compact: true)
        .fixedSize()

        FilePropertiesButton(a: a, b: b)

        if let accessory { accessory }
    }

    // MARK: - Diff scroll

    private func diffScroll(_ document: DiffDocument) -> some View {
        // The GeometryReader turns the shared split fraction into a concrete left-column
        // width for every row, so all rows (and the PathBar) divide at the same x.
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(document.sections) { section in
                            sectionView(section, leftWidth: unified ? nil : leftColumnWidth(in: geo.size.width))
                        }
                    }
                }
                .onChange(of: currentChangeID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
                }
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(target.id, anchor: .center) }
                }
            }
            .overlay(alignment: .topLeading) {
                if !unified {
                    ColumnSplitHandle(fraction: $splitFraction, width: geo.size.width)
                }
            }
        }
        .background(Theme.well)
    }

    private func leftColumnWidth(in width: CGFloat) -> CGFloat {
        max(0, (width * splitFraction - 0.5).rounded())
    }

    @ViewBuilder
    private func sectionView(_ section: DiffDocument.Section, leftWidth: CGFloat?) -> some View {
        switch section {
        case .rows(let rows):
            ForEach(rows) { row in rowView(row, leftWidth: leftWidth) }
        case .gap(_, let hiddenCount, let rows):
            if expandedGaps.contains(section.id) {
                ForEach(rows) { row in rowView(row, leftWidth: leftWidth) }
            } else {
                DiffGapView(count: hiddenCount) {
                    _ = expandedGaps.insert(section.id)
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: DiffRow, leftWidth: CGFloat?) -> some View {
        let isCurrent = row.id == currentChangeID || row.id == lineTargetID
        let find = rowFindHighlights(row.id)
        Group {
            if unified {
                UnifiedRowView(row: row, isCurrent: isCurrent, find: find)
            } else {
                DiffRowView(row: row, isCurrent: isCurrent, leftWidth: leftWidth, find: find)
            }
        }
        .id(row.id)
    }

    /// The row's Find matches, with the current match marked on its side.
    private func rowFindHighlights(_ rowID: UUID) -> RowFindHighlights {
        var highlights = findHighlights[rowID] ?? RowFindHighlights()
        if let findIndex, findIndex < findMatches.count, findMatches[findIndex].rowID == rowID {
            let match = findMatches[findIndex]
            if match.side == .left { highlights.left.current = match.range } else { highlights.right.current = match.range }
        }
        return highlights
    }

    // MARK: - Navigation

    private func navigate(_ delta: Int) {
        guard !changeIDs.isEmpty else { return }
        lineTargetID = nil
        findAnchor = nil
        if currentChange == -1 {
            currentChange = delta > 0 ? 0 : changeIDs.count - 1
        } else {
            currentChange = (currentChange + delta + changeIDs.count) % changeIDs.count
        }
        currentChangeID = changeIDs[currentChange]
    }

    // MARK: - Find and Go to Line

    private func showFind() {
        goToLineVisible = false
        findVisible = true
        findFocusRequest &+= 1
    }

    private func showGoToLine() {
        findVisible = false
        goToLineVisible = true
        goToLineFocusRequest &+= 1
    }

    private func search() async {
        guard findVisible, !findQuery.isEmpty, let rows = document?.allRows else {
            findMatches = []
            findHighlights = [:]
            findIndex = nil
            // Mid-reload the position is kept, so the new diff picks up where the old one was.
            if !findVisible || findQuery.isEmpty { findAnchor = nil }
            return
        }
        // Let a burst of typing settle before searching a long file.
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }
        let query = findQuery, options = findOptions, unified = unified
        let found = await offMain { TextSearch.matches(of: query, in: rows, options: options, unified: unified) }
        // The key (query, options, document) changed while searching: a newer search owns the result.
        guard !Task.isCancelled else { return }
        // Start from the match the user was on, else the line or change they're looking at, not
        // the top of the file.
        let position = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($1.id, $0) })
        let anchor = findAnchor ?? (lineTargetID ?? currentChangeID).flatMap { position[$0] }
        var highlights: [UUID: RowFindHighlights] = [:]
        for match in found {
            if match.side == .left {
                highlights[match.rowID, default: RowFindHighlights()].left.matches.append(match.range)
            } else {
                highlights[match.rowID, default: RowFindHighlights()].right.matches.append(match.range)
            }
        }
        findMatches = found
        findHighlights = highlights
        findIndex = TextSearch.startIndex(of: found, at: anchor) { position[$0.rowID] ?? 0 }
        let newAnchor = findIndex.map { position[found[$0].rowID] ?? 0 }
        // Don't move the view when the current match stayed on the row it was on.
        let unmoved = findDocument == rows.first?.id && newAnchor == findAnchor
        if let findIndex, !unmoved { reveal(found[findIndex].rowID) }
        findAnchor = newAnchor
        findDocument = rows.first?.id
    }

    private func stepFind(_ delta: Int) {
        if !findVisible { showFind() }
        guard var next = TextSearch.step(from: findIndex, by: delta, count: findMatches.count) else { return }
        // After ⌘] / ⌘[ or Go to Line moved elsewhere, carry on from there instead.
        if findAnchor == nil, let rows = document?.allRows,
           let target = lineTargetID ?? currentChangeID,
           let anchor = rows.firstIndex(where: { $0.id == target }) {
            let position = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($1.id, $0) })
            let atOrAfter = TextSearch.startIndex(of: findMatches, at: anchor) { position[$0.rowID] ?? 0 } ?? 0
            next = delta > 0 ? atOrAfter : (atOrAfter - 1 + findMatches.count) % findMatches.count
        }
        findIndex = next
        let rowID = findMatches[next].rowID
        findAnchor = document?.allRows.firstIndex { $0.id == rowID }
        reveal(rowID)
    }

    private func goToLine(_ line: Int) {
        guard let rows = document?.allRows,
              let id = TextSearch.row(forLine: line, side: goToLineSide, in: rows) else { return }
        lineTargetID = id
        findAnchor = nil
        reveal(id)
    }

    /// Scrolls to a row, first opening the collapsed gap that hides it.
    private func reveal(_ rowID: UUID) {
        scrollCounter &+= 1
        let token = scrollCounter
        func scroll() {
            // A later request superseded this one.
            guard token == scrollCounter else { return }
            scrollTarget = ScrollTarget(id: rowID, token: token)
        }
        if let gap = gapByRow[rowID], !expandedGaps.contains(gap) {
            expandedGaps.insert(gap)
            // Wait a turn so the opened rows exist in the lazy stack before scrolling to one.
            Task { @MainActor in scroll() }
        } else {
            scroll()
        }
    }

    // MARK: - Loading

    private func load() async {
        let request = UUID()
        loadRequest = request
        document = nil
        loadError = nil
        formatDifferences = []
        changeIDs = []
        expandedGaps = []
        gapByRow = [:]
        currentChange = -1
        currentChangeID = nil
        lineTargetID = nil
        let a = a, b = b
        let whitespacePolicy = whitespacePolicy
        let key = taskKey
        // Reading the bytes (possibly a git blob) and the Myers + character-level diff are heavy
        // for large files — run them off the main actor so the UI never freezes mid-diff.
        let outcome = await offMain { () -> (DiffDocument?, [String], String?) in
            do {
                let aText = try a.loadText()
                let bText = try b.loadText()
                return (LineDiff.document(aText, bText, whitespace: whitespacePolicy),
                        textFormatDifferences(aText, bText), nil)
            } catch {
                return (nil, [], error.localizedDescription)
            }
        }
        // Discard a result the user has already navigated past — otherwise an older, slower diff
        // can land after a newer one and overwrite it.
        guard !Task.isCancelled, request == loadRequest, key == taskKey else { return }
        if let doc = outcome.0 {
            document = doc
            formatDifferences = outcome.1
            changeIDs = hunkStartIDs(doc.allRows)
            var gaps: [UUID: String] = [:]
            for section in doc.sections {
                if case .gap(_, _, let rows) = section {
                    for row in rows { gaps[row.id] = section.id }
                }
            }
            gapByRow = gaps
            currentChange = -1
            currentChangeID = nil
        } else {
            loadError = outcome.2
        }
    }

    /// IDs of the first row of each contiguous run of changed rows, so Next/Previous jumps
    /// hunk-to-hunk instead of stepping through every single changed line.
    private func hunkStartIDs(_ rows: [DiffRow]) -> [UUID] {
        var ids: [UUID] = []
        var prevChanged = false
        for row in rows {
            let changed = row.kind.isChange
            if changed && !prevChanged { ids.append(row.id) }
            prevChanged = changed
        }
        return ids
    }
}

/// The draggable strip over a split comparison's column divider; double-click recenters.
struct ColumnSplitHandle: View {
    @Binding var fraction: Double
    let width: CGFloat
    @State private var dragBase: Double?

    var body: some View {
        Color.clear
            .frame(width: 9)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragBase == nil { dragBase = fraction }
                        let base = dragBase ?? fraction
                        fraction = min(0.8, max(0.2, base + value.translation.width / max(width, 1)))
                    }
                    .onEnded { _ in dragBase = nil }
            )
            .onTapGesture(count: 2) { withAnimation(.snappy) { fraction = 0.5 } }
            .help("Drag to resize the columns · double-click to recenter")
            .offset(x: width * fraction - 4.5)
    }
}

/// Picks how whitespace counts when matching lines.
struct WhitespacePolicyMenu: View {
    @Binding var policy: WhitespacePolicy

    var body: some View {
        Menu {
            ForEach(WhitespacePolicy.allCases, id: \.self) { option in
                Button {
                    policy = option
                } label: {
                    if policy == option {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            Image(systemName: policy == .significant ? "space" : "space.circle.fill")
                .foregroundStyle(policy == .significant ? Color.gray : Theme.brandAlt)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(policy.label)
        .accessibilityLabel("Whitespace comparison policy")
    }
}

/// A single unified-diff line (or pair, for a modified row).
struct UnifiedRowView: View {
    let row: DiffRow
    var isCurrent: Bool = false
    var find = RowFindHighlights()

    var body: some View {
        VStack(spacing: 0) {
            switch row.kind {
            case .equal:
                // An unchanged row draws A's text once; its B half matches it.
                line(marker: " ", number: row.leftNumber, text: row.leftText, kind: .equal, highlights: [],
                     find: find.left)
            case .inserted:
                line(marker: "+", number: row.rightNumber, text: row.rightText, kind: .inserted, highlights: row.rightHighlights,
                     find: find.right)
            case .deleted:
                line(marker: "−", number: row.leftNumber, text: row.leftText, kind: .deleted, highlights: row.leftHighlights,
                     find: find.left)
            case .modified:
                line(marker: "−", number: row.leftNumber, text: row.leftText, kind: .deleted, highlights: row.leftHighlights,
                     find: find.left)
                line(marker: "+", number: row.rightNumber, text: row.rightText, kind: .inserted, highlights: row.rightHighlights,
                     find: find.right)
            }
        }
        .background(isCurrent ? Theme.brand.opacity(0.12) : .clear)
    }

    @ViewBuilder
    private func line(marker: String, number: Int?, text: String?, kind: DiffRow.Kind, highlights: [Range<Int>],
                      find: LineFindHighlights) -> some View {
        let accent = Theme.color(for: kind)
        HStack(spacing: 0) {
            Rectangle().fill(kind.isChange ? accent : .clear).frame(width: 2.5)
            Text(number.map(String.init) ?? "")
                .font(Theme.gutterFont).foregroundStyle(.secondary.opacity(0.7))
                .frame(width: 44, alignment: .trailing).padding(.trailing, 6)
            Text(marker)
                .font(Theme.codeFont).foregroundStyle(accent == .clear ? .secondary : accent)
                .frame(width: 14)
            Text(highlightedLine(text ?? "", ranges: highlights,
                                 color: kind == .deleted ? Theme.removedHighlight : Theme.addedHighlight,
                                 find: find))
                .font(Theme.codeFont)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 1.5)
        .background(Theme.fill(for: kind))
    }
}
