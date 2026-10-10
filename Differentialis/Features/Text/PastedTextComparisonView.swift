import SwiftUI
import AppKit

/// Two side-by-side editors to paste or type text into, diffed live as you edit. Each change can
/// be copied across to the other side, and the Diff presentation shows the usual aligned diff.
struct PastedTextComparisonView: View {
    @Bindable var document: PastedTextDocument

    @AppStorage("diffSplitFraction") private var splitFraction = 0.5
    @AppStorage("textWhitespacePolicy") private var whitespacePolicy = WhitespacePolicy.significant
    @State private var presentation = Presentation.edit
    @State private var analysis: PastedTextAnalysis?
    @State private var currentHunk: Int?
    @State private var caret: Caret?
    @State private var controller = PastedTextEditorController()
    /// Set by actions (paste, merge, swap) that should re-diff without the typing debounce.
    @State private var analyzeImmediately = true
    /// After copying a change, scroll to the change that takes its place once the re-diff lands.
    @State private var revealAfterAnalysis = false

    private enum Presentation: Hashable { case edit, diff }

    private struct Caret: Equatable {
        var side: PastedTextSide
        var location: Int
    }

    private struct AnalysisKey: Equatable {
        var a: String
        var b: String
        var whitespace: WhitespacePolicy
    }

    var body: some View {
        Group {
            switch presentation {
            case .edit:
                editor
            case .diff:
                TextComparisonView(a: source(.a), b: source(.b), accessory: AnyView(presentationSwitch))
            }
        }
        .task(id: AnalysisKey(a: document.a, b: document.b, whitespace: whitespacePolicy)) {
            await analyze()
        }
    }

    private func source(_ side: PastedTextSide) -> ComparisonSource {
        side == .a ? .text(content: document.a, name: "Original")
                   : .text(content: document.b, name: "Modified")
    }

    private func text(_ side: PastedTextSide) -> String {
        side == .a ? document.a : document.b
    }

    // MARK: - Edit presentation

    private var editor: some View {
        VStack(spacing: 0) {
            PathBar(a: source(.a), b: source(.b), splitFraction: splitFraction) { toolbar }
            Divider().opacity(0.4)
            GeometryReader { geo in
                HStack(spacing: 0) {
                    column(.a)
                        .frame(width: max(0, (geo.size.width * splitFraction - 0.5).rounded()))
                    Rectangle().fill(.primary.opacity(0.06)).frame(width: 1)
                    column(.b)
                }
                .overlay(alignment: .topLeading) {
                    ColumnSplitHandle(fraction: $splitFraction, width: geo.size.width)
                }
            }
            .background(Theme.well)
        }
        .codeFontZoomGesture()
        .focusedSceneValue(\.diffCommands, DiffCommandActions(
            nextChange: { navigate(1) },
            prevChange: { navigate(-1) },
            swapAB: { swapSides() },
            copyChangeToA: canCopyChange ? { copyChange(.bToA) } : nil,
            copyChangeToB: canCopyChange ? { copyChange(.aToB) } : nil))
    }

    private func column(_ side: PastedTextSide) -> some View {
        VStack(spacing: 0) {
            columnHeader(side)
            Divider().opacity(0.4)
            DiffTextEditor(side: side,
                           text: side == .a ? $document.a : $document.b,
                           decorations: decorations(side),
                           currentRange: currentRange(side),
                           style: .current(for: side),
                           controller: controller,
                           onCaretMove: { caretMoved(side, to: $0) })
                .overlay {
                    if text(side).isEmpty { emptyPrompt(side) }
                }
        }
    }

    /// Paste / Copy / Clear for the side, and the button that copies the selected change across —
    /// placed on the inner edge, next to the side it sends the change to.
    private func columnHeader(_ side: PastedTextSide) -> some View {
        HStack(spacing: 10) {
            if side == .b { copyChangeButton(.bToA) }
            if side == .b { Spacer(minLength: 8) }
            HStack(spacing: 2) {
                headerButton("Paste", systemImage: "doc.on.clipboard",
                             help: "Replace \(side == .a ? "A" : "B") with the clipboard") { paste(into: side) }
                headerButton("Copy", systemImage: "doc.on.doc",
                             help: "Copy all of \(side == .a ? "A" : "B")") { copyAll(side) }
                    .disabled(text(side).isEmpty)
                headerButton("Clear", systemImage: "xmark.circle",
                             help: "Clear \(side == .a ? "A" : "B")") { setText("", on: side, actionName: "Clear") }
                    .disabled(text(side).isEmpty)
            }
            if side == .a { Spacer(minLength: 8) }
            if side == .a { copyChangeButton(.aToB) }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(.ultraThinMaterial)
    }

    private func headerButton(_ title: String, systemImage: String, help: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11.5))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private func copyChangeButton(_ direction: TwoWayMerge.Direction) -> some View {
        Button {
            copyChange(direction)
        } label: {
            HStack(spacing: 5) {
                if direction == .bToA { Image(systemName: "arrow.left") }
                Text(direction == .aToB ? "Copy to B" : "Copy to A")
                if direction == .aToB { Image(systemName: "arrow.right") }
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(canCopyChange ? Theme.brand : Color.secondary)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!canCopyChange)
        .help(direction == .aToB
              ? "Replace B’s side of the selected change with A’s lines (⌥⌘→)"
              : "Replace A’s side of the selected change with B’s lines (⌥⌘←)")
    }

    private func emptyPrompt(_ side: PastedTextSide) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.tertiary)
                .allowsHitTesting(false)
            Text(side == .a ? "Paste or type the original text" : "Paste or type the modified text")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .allowsHitTesting(false)
            Button {
                paste(into: side)
            } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.glass)
        }
        .padding(24)
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        statusChip
        HStack(spacing: 6) {
            Button { navigate(-1) } label: { Image(systemName: "chevron.up") }
                .help("Previous change (⌘[)")
            Button { navigate(1) } label: { Image(systemName: "chevron.down") }
                .help("Next change (⌘])")
        }
        .buttonStyle(.borderless)
        .disabled(analysis?.hunks.isEmpty ?? true)

        WhitespacePolicyMenu(policy: $whitespacePolicy)

        Button { swapSides() } label: { Image(systemName: "arrow.left.arrow.right") }
            .buttonStyle(.borderless)
            .disabled(document.a == document.b)
            .help("Swap A and B (⇧⌘S)")
            .accessibilityLabel("Swap A and B")

        presentationSwitch
    }

    /// Nothing to report until both sides have text — the empty panes prompt for it themselves.
    @ViewBuilder
    private var statusChip: some View {
        if !document.a.isEmpty, !document.b.isEmpty, let analysis {
            if analysis.isIdentical && analysis.formatDifferences.isEmpty {
                StatChip(text: "No differences", color: Theme.added, systemImage: "checkmark.seal.fill")
            } else if analysis.isIdentical {
                StatChip(text: "Formatting differs", color: Theme.modified)
                    .help(analysis.formatDifferences.joined(separator: "\n"))
            } else {
                StatChip(text: analysis.stats.summary, color: .primary)
            }
        }
    }

    private var presentationSwitch: some View {
        GlassSegmentedControl(
            selection: $presentation,
            options: [
                .init(value: .edit, title: "Edit", systemImage: "square.and.pencil"),
                .init(value: .diff, title: "Diff", systemImage: "rectangle.split.2x1"),
            ],
            compact: true)
        .fixedSize()
    }

    // MARK: - Decorations

    /// Whether `analysis` describes the texts currently in the editors.
    private var analysisIsCurrent: Bool {
        guard let analysis else { return false }
        return analysis.aText == document.a && analysis.bText == document.b
    }

    private var canCopyChange: Bool {
        guard let currentHunk, let analysis else { return false }
        return currentHunk < analysis.hunks.count
    }

    private func decorations(_ side: PastedTextSide) -> EditorDecorations {
        guard let analysis else { return EditorDecorations() }
        return side == .a ? analysis.a : analysis.b
    }

    private func currentRange(_ side: PastedTextSide) -> NSRange? {
        guard let currentHunk else { return nil }
        let ranges = decorations(side).hunkRanges
        return currentHunk < ranges.count ? ranges[currentHunk] : nil
    }

    // MARK: - Analysis

    private func analyze() async {
        let a = document.a, b = document.b, whitespace = whitespacePolicy
        guard !a.isEmpty, !b.isEmpty else {
            analysis = nil
            currentHunk = nil
            controller.aToB = []
            controller.bToA = []
            return
        }
        if analyzeImmediately {
            analyzeImmediately = false
        } else {
            // Debounce typing; a newer keystroke cancels this task before it diffs.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
        }
        let result = await offMain { PastedTextAnalysis.make(a: a, b: b, whitespace: whitespace) }
        guard !Task.isCancelled, a == document.a, b == document.b, whitespace == whitespacePolicy else { return }

        analysis = result
        controller.aToB = result.aToB
        controller.bToA = result.bToA
        if let caret, let index = result.hunkIndex(containing: caret.location, on: caret.side) {
            currentHunk = index
        } else if let current = currentHunk {
            currentHunk = result.hunks.isEmpty ? nil : min(current, result.hunks.count - 1)
        }
        if revealAfterAnalysis {
            revealAfterAnalysis = false
            if let currentHunk {
                controller.reveal(a: result.a.hunkRanges[currentHunk], b: result.b.hunkRanges[currentHunk],
                                  onlyIfNeeded: true)
            }
        }
    }

    // MARK: - Actions

    private func caretMoved(_ side: PastedTextSide, to location: Int) {
        caret = Caret(side: side, location: location)
        if analysisIsCurrent, let index = analysis?.hunkIndex(containing: location, on: side) {
            currentHunk = index
        }
    }

    private func navigate(_ delta: Int) {
        guard presentation == .edit, let analysis, !analysis.hunks.isEmpty else { return }
        let count = analysis.hunks.count
        let next = currentHunk.map { ($0 + delta + count) % count } ?? (delta > 0 ? 0 : count - 1)
        currentHunk = next
        caret = nil
        controller.reveal(a: analysis.a.hunkRanges[next], b: analysis.b.hunkRanges[next], onlyIfNeeded: false)
    }

    /// Copies the selected change from one side over the other, then moves on to the next change.
    private func copyChange(_ direction: TwoWayMerge.Direction) {
        guard analysisIsCurrent, let analysis, let index = currentHunk, index < analysis.hunks.count else {
            NSSound.beep()
            return
        }
        let merged = TwoWayMerge.apply(analysis.hunks[index], direction, a: document.a, b: document.b)
        caret = nil
        revealAfterAnalysis = true
        switch direction {
        case .aToB: setText(merged.b, on: .b, actionName: "Copy Change to B")
        case .bToA: setText(merged.a, on: .a, actionName: "Copy Change to A")
        }
    }

    private func swapSides() {
        let a = document.a, b = document.b
        guard a != b else { return }
        caret = nil
        // Both replacements land in one undo group (the undo manager groups by event).
        setText(b, on: .a, actionName: "Swap A and B")
        setText(a, on: .b, actionName: "Swap A and B")
    }

    private func paste(into side: PastedTextSide) {
        guard let string = NSPasteboard.general.string(forType: .string), !string.isEmpty else {
            NSSound.beep()
            return
        }
        caret = nil
        setText(string, on: side, actionName: "Paste")
    }

    private func copyAll(_ side: PastedTextSide) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text(side), forType: .string)
    }

    /// Edits go through the editor when it's on screen, so they're undoable like typing.
    private func setText(_ newText: String, on side: PastedTextSide, actionName: String) {
        guard newText != text(side) else { return }
        analyzeImmediately = true
        if !controller.replaceText(on: side, with: newText, actionName: actionName) {
            if side == .a { document.a = newText } else { document.b = newText }
        }
    }
}
