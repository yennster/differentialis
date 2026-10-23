import SwiftUI
import UniformTypeIdentifiers

func containsConflictMarkerFragment(_ text: String) -> Bool {
    text.components(separatedBy: .newlines).contains { line in
        line.hasPrefix("<<<<<<<") || line == "=======" || line.hasPrefix(">>>>>>>")
    }
}

struct MergeView: View {
    @Bindable var session: MergeSession

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            if let loadError = session.loadError {
                ContentUnavailableView("Couldn’t load files", systemImage: "exclamationmark.triangle",
                                       description: Text(loadError))
            } else if !session.loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if session.presentation == .review {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if session.lineStyleConflict {
                            LineStyleConflictBlock(base: session.baseLineStyle,
                                                   left: session.leftLineStyle,
                                                   right: session.rightLineStyle,
                                                   choose: session.resolveLineStyle)
                        }
                        ForEach(session.hunks) { hunk in
                            HunkBlock(hunk: hunk) { resolution, lines in
                                session.resolve(hunk: hunk.id, as: resolution, lines: lines)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .background(Theme.well)
            } else {
                resultEditor
            }
        }
        .codeFontZoomGesture()
        // The session outlives this view, so coming back to an already-loaded merge keeps its
        // choices and edits instead of re-reading the sources.
        .task { if session.needsLoad { await session.load() } }
        .focusedSceneValue(\.diffCommands, DiffCommandActions(refresh: {
            guard session.confirmDiscardingChanges(before: .reload) else { return }
            Task { await session.load() }
        }))
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
                StatChip(text: "\(count) conflict\(count == 1 ? "" : "s")",
                         color: Theme.conflict, systemImage: "exclamationmark.triangle.fill")
            } else if session.loaded {
                StatChip(text: "Resolved", color: Theme.added, systemImage: "checkmark.seal.fill")
            }
            if session.resultDirty {
                StatChip(text: "Edited", color: Theme.brandAlt, systemImage: "pencil")
            }
            Button {
                session.saveInteractively()
            } label: {
                Label("Save Merged…", systemImage: "square.and.arrow.down")
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

            TextEditor(text: Binding(
                get: { session.resultText },
                set: { session.editResult($0) }))
                .font(Theme.codeFont)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Theme.well)
                .accessibilityLabel("Merged result")
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
        alert.addButton(withTitle: "Save…")
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
        if lineStyleConflict && !resultDirty {
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
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultSaveName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return false }

        do {
            try resultText.write(to: url, atomically: true, encoding: .utf8)
            markSaved()
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
    let hunk: MergeHunk
    let choose: (MergeResolution, [String]) -> Void

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
        choose(resolution, lines)
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
