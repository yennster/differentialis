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

    @State private var document: DiffDocument?
    @AppStorage("diffLayoutUnified") private var unified = false
    @AppStorage("textWhitespacePolicy") private var whitespacePolicy = WhitespacePolicy.significant
    @State private var expandedGaps: Set<String> = []
    @State private var changeIDs: [UUID] = []
    @State private var currentChange = -1
    @State private var currentChangeID: UUID?
    @State private var loadError: String?
    @State private var formatDifferences: [String] = []
    @State private var loadRequest: UUID?

    var body: some View {
        VStack(spacing: 0) {
            PathBar(a: a, b: b) { toolbar }
            Divider().opacity(0.4)
            content
        }
        .task(id: taskKey) { await load() }
        .focusedSceneValue(\.diffCommands, DiffCommandActions(
            nextChange: { navigate(1) },
            prevChange: { navigate(-1) },
            toggleLayout: { unified.toggle() },
            refresh: { Task { await load() } }))
        .focusable()
        .focusEffectDisabled()
        .onKeyPress("]") { navigate(1); return .handled }
        .onKeyPress("[") { navigate(-1); return .handled }
    }

    private var taskKey: String {
        "\(a.displayName)|\(b.displayName)|\(a.subtitle)|\(b.subtitle)|\(whitespacePolicy.rawValue)"
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

        Menu {
            ForEach(WhitespacePolicy.allCases, id: \.self) { policy in
                Button {
                    whitespacePolicy = policy
                } label: {
                    if whitespacePolicy == policy {
                        Label(policy.label, systemImage: "checkmark")
                    } else {
                        Text(policy.label)
                    }
                }
            }
        } label: {
            Image(systemName: whitespacePolicy == .significant ? "space" : "space.circle.fill")
                .foregroundStyle(whitespacePolicy == .significant ? Color.gray : Theme.brandAlt)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(whitespacePolicy.label)
        .accessibilityLabel("Whitespace comparison policy")

        GlassSegmentedControl(
            selection: $unified,
            options: [
                .init(value: false, title: "Split", systemImage: "rectangle.split.2x1"),
                .init(value: true, title: "Unified", systemImage: "list.bullet"),
            ],
            compact: true)
        .fixedSize()

        FilePropertiesButton(a: a, b: b)
    }

    // MARK: - Diff scroll

    private func diffScroll(_ document: DiffDocument) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(document.sections) { section in
                        sectionView(section)
                    }
                }
            }
            .onChange(of: currentChangeID) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .background(.black.opacity(0.18))
    }

    @ViewBuilder
    private func sectionView(_ section: DiffDocument.Section) -> some View {
        switch section {
        case .rows(let rows):
            ForEach(rows) { row in rowView(row) }
        case .gap(_, let hiddenCount, let rows):
            if expandedGaps.contains(section.id) {
                ForEach(rows) { row in rowView(row) }
            } else {
                DiffGapView(count: hiddenCount) {
                    _ = expandedGaps.insert(section.id)
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: DiffRow) -> some View {
        Group {
            if unified {
                UnifiedRowView(row: row, isCurrent: row.id == currentChangeID)
            } else {
                DiffRowView(row: row, isCurrent: row.id == currentChangeID)
            }
        }
        .id(row.id)
    }

    // MARK: - Navigation

    private func navigate(_ delta: Int) {
        guard !changeIDs.isEmpty else { return }
        if currentChange == -1 {
            currentChange = delta > 0 ? 0 : changeIDs.count - 1
        } else {
            currentChange = (currentChange + delta + changeIDs.count) % changeIDs.count
        }
        currentChangeID = changeIDs[currentChange]
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
        currentChange = -1
        currentChangeID = nil
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

/// A single unified-diff line (or pair, for a modified row).
struct UnifiedRowView: View {
    let row: DiffRow
    var isCurrent: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            switch row.kind {
            case .equal:
                line(marker: " ", number: row.leftNumber, text: row.leftText, kind: .equal, highlights: [])
            case .inserted:
                line(marker: "+", number: row.rightNumber, text: row.rightText, kind: .inserted, highlights: row.rightHighlights)
            case .deleted:
                line(marker: "−", number: row.leftNumber, text: row.leftText, kind: .deleted, highlights: row.leftHighlights)
            case .modified:
                line(marker: "−", number: row.leftNumber, text: row.leftText, kind: .deleted, highlights: row.leftHighlights)
                line(marker: "+", number: row.rightNumber, text: row.rightText, kind: .inserted, highlights: row.rightHighlights)
            }
        }
        .background(isCurrent ? Theme.brand.opacity(0.12) : .clear)
    }

    @ViewBuilder
    private func line(marker: String, number: Int?, text: String?, kind: DiffRow.Kind, highlights: [Range<Int>]) -> some View {
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
                                 color: kind == .deleted ? Theme.removedHighlight : Theme.addedHighlight))
                .font(Theme.codeFont)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 1.5)
        .background(Theme.fill(for: kind))
    }
}
