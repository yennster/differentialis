import SwiftUI
import UniformTypeIdentifiers

func containsConflictMarkerFragment(_ text: String) -> Bool {
    text.components(separatedBy: .newlines).contains { line in
        line.hasPrefix("<<<<<<<") || line == "=======" || line.hasPrefix(">>>>>>>")
    }
}

struct MergeView: View {
    let base: ComparisonSource
    let left: ComparisonSource
    let right: ComparisonSource

    @State private var hunks: [MergeHunk] = []
    @State private var loadError: String?
    @State private var loaded = false
    @State private var lineEnding = "\n"
    @State private var finalNewline = false
    @State private var presentation = Presentation.review
    @State private var resultText = ""
    @State private var resultDirty = false
    @State private var baseLineStyle = TextLineStyle(ending: "\n", finalNewline: false)
    @State private var leftLineStyle = TextLineStyle(ending: "\n", finalNewline: false)
    @State private var rightLineStyle = TextLineStyle(ending: "\n", finalNewline: false)
    @State private var lineStyleConflict = false
    @State private var loadToken: UUID?

    private enum Presentation: Hashable { case review, result }

    private var unresolvedConflicts: Int {
        hunks.filter { $0.isConflict && !$0.resolved }.count + (lineStyleConflict ? 1 : 0)
    }

    private var taskKey: String {
        "\(base.displayName)|\(base.subtitle)|\(left.displayName)|\(left.subtitle)|\(right.displayName)|\(right.subtitle)"
    }

    private var defaultSaveName: String {
        if case .file(let url) = left { return url.lastPathComponent }
        if case .file(let url) = base { return url.lastPathComponent }
        return "merged.txt"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            if let loadError {
                ContentUnavailableView("Couldn’t load files", systemImage: "exclamationmark.triangle",
                                       description: Text(loadError))
            } else if !loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if presentation == .review {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if lineStyleConflict {
                            LineStyleConflictBlock(base: baseLineStyle,
                                                   left: leftLineStyle,
                                                   right: rightLineStyle,
                                                   choose: resolveLineStyle)
                        }
                        ForEach($hunks) { $hunk in
                            HunkBlock(hunk: $hunk)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .background(.black.opacity(0.18))
            } else {
                resultEditor
            }
        }
        .task(id: taskKey) { await load() }
        .focusedSceneValue(\.diffCommands, DiffCommandActions(refresh: { Task { await load() } }))
        .onChange(of: hunks) { _, _ in
            if !resultDirty { synchronizeResult() }
        }
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
            if loaded {
                GlassSegmentedControl(
                    selection: $presentation,
                    options: [
                        .init(value: .review, title: "Review", systemImage: "list.bullet.rectangle"),
                        .init(value: .result, title: "Result", systemImage: "square.and.pencil"),
                    ],
                    compact: true)
                .fixedSize()
            }
            if unresolvedConflicts > 0 {
                StatChip(text: "\(unresolvedConflicts) conflict\(unresolvedConflicts == 1 ? "" : "s")",
                         color: Theme.conflict, systemImage: "exclamationmark.triangle.fill")
            } else if loaded {
                StatChip(text: "Resolved", color: Theme.added, systemImage: "checkmark.seal.fill")
            }
            if resultDirty {
                StatChip(text: "Edited", color: Theme.brandAlt, systemImage: "pencil")
            }
            Button {
                save()
            } label: {
                Label("Save Merged…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.glass)
            .disabled(!loaded)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var resultEditor: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(resultDirty
                     ? "Manual edits take precedence over the hunk selections."
                     : "This is the exact text that will be saved.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Spacer()
                if resultDirty {
                    Button("Reset from Review") {
                        resultDirty = false
                        synchronizeResult()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(.ultraThinMaterial)

            TextEditor(text: Binding(
                get: { resultText },
                set: { newValue in
                    resultText = newValue
                    resultDirty = true
                }))
                .font(Theme.codeFont)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.black.opacity(0.18))
                .accessibilityLabel("Merged result")
        }
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func load() async {
        let token = UUID()
        loadToken = token
        loaded = false
        loadError = nil
        let base = base, left = left, right = right
        let key = taskKey
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
        // Ignore a result from a comparison the user has already navigated away from.
        guard !Task.isCancelled, token == loadToken, key == taskKey else { return }
        if let result = outcome.0 {
            hunks = result.0
            let style = result.1
            lineEnding = style.selected.ending
            finalNewline = style.selected.finalNewline
            baseLineStyle = style.base
            leftLineStyle = style.left
            rightLineStyle = style.right
            lineStyleConflict = style.hasConflict
            resultDirty = false
            resultText = ThreeWayMerge.mergedText(result.0, lineEnding: style.selected.ending,
                                                   finalNewline: style.selected.finalNewline)
            loaded = true
        } else {
            loadError = outcome.1
        }
    }

    private func save() {
        if lineStyleConflict && !resultDirty {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Choose an output line-ending style"
            alert.informativeText = "Left and right use different line endings. Resolve the formatting conflict in Review before saving."
            alert.addButton(withTitle: "Review")
            alert.runModal()
            presentation = .review
            return
        }

        // Never silently write the left side over an unresolved conflict — warn, then emit
        // standard conflict markers so nothing is lost.
        let conflictMarkersRemain = containsConflictMarkerFragment(resultText)
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
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultSaveName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try resultText.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn’t save the merged file"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func synchronizeResult() {
        resultText = ThreeWayMerge.mergedText(hunks, lineEnding: lineEnding,
                                               finalNewline: finalNewline)
    }

    private func resolveLineStyle(_ style: TextLineStyle) {
        lineEnding = style.ending
        finalNewline = style.finalNewline
        lineStyleConflict = false
        if !resultDirty { synchronizeResult() }
    }
}

private struct LineStyleConflictBlock: View {
    let base: TextLineStyle
    let left: TextLineStyle
    let right: TextLineStyle
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

private struct HunkBlock: View {
    @Binding var hunk: MergeHunk

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
            ForEach(Array(hunk.chosen.enumerated()), id: \.offset) { _, line in
                lineText(line, color: .secondary.opacity(0.7))
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
            ForEach(Array(hunk.chosen.enumerated()), id: \.offset) { _, line in
                lineText(line, color: .primary)
            }
        }
        .padding(10)
        .background(hunk.resolution.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(hunk.resolution.tint.opacity(0.25)))
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
                conflictColumn(title: "Left", lines: hunk.leftLines, color: Theme.removed) {
                    resolve(.takeLeft, lines: hunk.leftLines)
                }
                conflictColumn(title: "Right", lines: hunk.rightLines, color: Theme.modified) {
                    resolve(.takeRight, lines: hunk.rightLines)
                }
            }
            HStack(spacing: 8) {
                Button("Use Both") { resolve(.takeBoth, lines: hunk.leftLines + hunk.rightLines) }
                    .buttonStyle(.bordered)
                Button("Use Base") { resolve(.unchanged, lines: hunk.baseLines) }
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(Theme.conflict.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.conflict.opacity(0.4)))
        .padding(.horizontal, 12).padding(.vertical, 4)
    }

    private func conflictColumn(title: String, lines: [String], color: Color, choose: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 10.5, weight: .bold)).foregroundStyle(color)
                Spacer()
                Button("Use") { choose() }.buttonStyle(.borderless).controlSize(.small).foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    lineText(line, color: .primary)
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
            Button("Left") { resolve(.takeLeft, lines: hunk.leftLines) }
            Button("Right") { resolve(.takeRight, lines: hunk.rightLines) }
            Button("Both") { resolve(.takeBoth, lines: hunk.leftLines + hunk.rightLines) }
            Button("Base") { resolve(.unchanged, lines: hunk.baseLines) }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func resolve(_ resolution: MergeResolution, lines: [String]) {
        hunk.resolution = resolution
        hunk.chosen = lines
        hunk.resolved = true
    }

    private func lineText(_ text: String, color: Color) -> some View {
        Text(text.isEmpty ? " " : text)
            .font(Theme.codeFont)
            .foregroundStyle(color)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
