import SwiftUI
import AppKit

struct FolderComparisonView: View {
    let a: ComparisonSource
    let b: ComparisonSource

    @State private var entries: [FolderEntry] = []
    @State private var selection: FolderEntry.ID?
    @State private var changesOnly = true
    @State private var scanning = true

    private var aRoot: URL? { if case .file(let url) = a { return url }; return nil }
    private var bRoot: URL? { if case .file(let url) = b { return url }; return nil }

    private var filtered: [FolderEntry] {
        changesOnly ? entries.filter { $0.status.isChange } : entries
    }

    private var stats: (added: Int, removed: Int, modified: Int) {
        (entries.filter { $0.status == .added }.count,
         entries.filter { $0.status == .removed }.count,
         entries.filter { $0.status == .modified }.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            PathBar(a: a, b: b, leftAccent: Theme.brandAlt, rightAccent: Theme.brandAlt) { toolbar }
            Divider().opacity(0.4)
            if scanning {
                ProgressView("Scanning folders…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    fileList
                        .frame(minWidth: 200, idealWidth: 300, maxWidth: 400)
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task(id: "\(aRoot?.path ?? a.displayName)|\(bRoot?.path ?? b.displayName)") { await scan() }
        .focusedSceneValue(\.diffCommands, DiffCommandActions(refresh: { Task { await scan() } }))
    }

    @ViewBuilder
    private var toolbar: some View {
        let s = stats
        HStack(spacing: 6) {
            if s.added > 0 { StatChip(text: "+\(s.added)", color: Theme.added) }
            if s.removed > 0 { StatChip(text: "−\(s.removed)", color: Theme.removed) }
            if s.modified > 0 { StatChip(text: "~\(s.modified)", color: Theme.modified) }
            if s.added == 0 && s.removed == 0 && s.modified == 0 {
                StatChip(text: "Identical", color: Theme.added)
            }
        }
        GlassSegmentedControl(
            selection: $changesOnly,
            options: [.init(value: true, title: "Changes"), .init(value: false, title: "All")],
            compact: true)
        .fixedSize()
    }

    private var fileList: some View {
        List(filtered, selection: $selection) { entry in
            HStack(spacing: 8) {
                Text(entry.status.letter)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(color(entry.status), in: RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Image(systemName: entry.isImage ? "photo" : "doc.text")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(entry.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                    }
                    if !entry.directory.isEmpty {
                        Text(entry.directory).font(.system(size: 10)).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer()
            }
            .tag(entry.id)
            .contextMenu { fileMenu(for: entry) }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func fileMenu(for entry: FolderEntry) -> some View {
        // Resolve the absolute path against whichever side actually contains the file.
        let root = entry.status == .removed ? aRoot : (bRoot ?? aRoot)
        Button("Copy Name") { copyToPasteboard(entry.name) }
        Button("Copy Path") { copyToPasteboard(entry.relativePath) }
        if let root {
            Button("Copy Full Path") {
                copyToPasteboard(root.appendingPathComponent(entry.relativePath).path)
            }
        }
    }

    private func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    @ViewBuilder
    private var detail: some View {
        if let entry = filtered.first(where: { $0.id == selection }) ?? filtered.first,
           let comparison = comparison(for: entry) {
            ComparisonDetailView(comparison: comparison)
                .id(entry.id)
        } else {
            ContentUnavailableView("Select a file", systemImage: "sidebar.left",
                                   description: Text("Choose a file to see its differences."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func comparison(for entry: FolderEntry) -> Comparison? {
        guard let aRoot, let bRoot else { return nil }
        let aURL = aRoot.appendingPathComponent(entry.relativePath)
        let bURL = bRoot.appendingPathComponent(entry.relativePath)
        switch entry.status {
        case .added:
            return Comparison.make(a: .empty(name: entry.name), b: .file(bURL), title: entry.relativePath)
        case .removed:
            return Comparison.make(a: .file(aURL), b: .empty(name: entry.name), title: entry.relativePath)
        case .modified, .identical:
            return Comparison.make(a: .file(aURL), b: .file(bURL), title: entry.relativePath)
        }
    }

    private func color(_ status: FolderStatus) -> Color {
        switch status {
        case .added: return Theme.added
        case .removed: return Theme.removed
        case .modified: return Theme.modified
        case .identical: return .secondary
        }
    }

    private func scan() async {
        scanning = true
        entries = []
        selection = nil
        guard let aRoot, let bRoot else { scanning = false; return }
        let result = await Task.detached { FolderScanner.scan(a: aRoot, b: bRoot) }.value
        // A newer comparison may have superseded this scan while it ran.
        guard !Task.isCancelled else { return }
        entries = result
        selection = result.first(where: { $0.status.isChange })?.id
        scanning = false
    }
}
