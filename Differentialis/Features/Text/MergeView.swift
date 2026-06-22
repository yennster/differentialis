import SwiftUI
import UniformTypeIdentifiers

struct MergeView: View {
    let base: ComparisonSource
    let left: ComparisonSource
    let right: ComparisonSource

    @State private var hunks: [MergeHunk] = []
    @State private var loadError: String?
    @State private var loaded = false

    private var unresolvedConflicts: Int { hunks.filter { $0.isConflict && !$0.resolved }.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            if let loadError {
                ContentUnavailableView("Couldn’t load files", systemImage: "exclamationmark.triangle",
                                       description: Text(loadError))
            } else if !loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach($hunks) { $hunk in
                            HunkBlock(hunk: $hunk)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .background(.black.opacity(0.18))
            }
        }
        .task(id: "\(base.subtitle)|\(left.subtitle)|\(right.subtitle)") { await load() }
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
            if unresolvedConflicts > 0 {
                StatChip(text: "\(unresolvedConflicts) conflict\(unresolvedConflicts == 1 ? "" : "s")",
                         color: Theme.conflict, systemImage: "exclamationmark.triangle.fill")
            } else if loaded {
                StatChip(text: "Resolved", color: Theme.added, systemImage: "checkmark.seal.fill")
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

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func load() async {
        do {
            let baseText = try base.loadText()
            let leftText = try left.loadText()
            let rightText = try right.loadText()
            hunks = ThreeWayMerge.merge(base: baseText, left: leftText, right: rightText)
            loaded = true
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "merged.txt"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? ThreeWayMerge.mergedText(hunks).write(to: url, atomically: true, encoding: .utf8)
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
