import SwiftUI

struct TextComparisonView: View {
    let a: ComparisonSource
    let b: ComparisonSource

    @State private var document: DiffDocument?
    @State private var unified = false
    @State private var expandedGaps: Set<String> = []
    @State private var changeIDs: [UUID] = []
    @State private var currentChange = -1
    @State private var currentChangeID: UUID?
    @State private var loadError: String?

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
            toggleLayout: { unified.toggle() }))
        .focusable()
        .focusEffectDisabled()
        .onKeyPress("]") { navigate(1); return .handled }
        .onKeyPress("[") { navigate(-1); return .handled }
    }

    private var taskKey: String { "\(a.displayName)|\(b.displayName)|\(a.subtitle)|\(b.subtitle)" }

    @ViewBuilder
    private var content: some View {
        if let document {
            if document.isIdentical {
                identicalState
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
            Label("Files are identical", systemImage: "checkmark.seal.fill")
        } description: {
            Text("No differences between A and B.")
        }
        .foregroundStyle(Theme.added)
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        if let document {
            StatChip(text: document.stats.summary,
                     color: document.stats.isIdentical ? Theme.added : .primary)
        }
        HStack(spacing: 6) {
            Button { navigate(-1) } label: { Image(systemName: "chevron.up") }
            Button { navigate(1) } label: { Image(systemName: "chevron.down") }
        }
        .buttonStyle(.borderless)
        .disabled(changeIDs.isEmpty)

        GlassSegmentedControl(
            selection: $unified,
            options: [
                .init(value: false, title: "Split", systemImage: "rectangle.split.2x1"),
                .init(value: true, title: "Unified", systemImage: "list.bullet"),
            ],
            compact: true)
        .fixedSize()
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
        document = nil
        loadError = nil
        do {
            let aText = try a.loadText()
            let bText = try b.loadText()
            let doc = LineDiff.document(aText, bText)
            document = doc
            changeIDs = doc.allRows.filter { $0.kind.isChange }.map(\.id)
            currentChange = -1
            currentChangeID = nil
        } catch {
            loadError = error.localizedDescription
        }
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
