import SwiftUI
import AppKit

struct FolderComparisonView: View {
    let a: ComparisonSource
    let b: ComparisonSource

    @State private var entries: [FolderEntry] = []
    @State private var selection: FolderEntry.ID?
    @State private var changesOnly = true
    @State private var scanning = true
    @State private var query = ""
    @State private var statusFilter: FolderStatus?
    @State private var scanIssues: [String] = []
    @State private var scanRequest: UUID?

    private var aRoot: URL? { if case .file(let url) = a { return url }; return nil }
    private var bRoot: URL? { if case .file(let url) = b { return url }; return nil }

    private var filtered: [FolderEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        return entries.filter { entry in
            if changesOnly && !entry.status.isChange { return false }
            if let statusFilter, entry.status != statusFilter { return false }
            return needle.isEmpty || entry.relativePath.localizedLowercase.contains(needle)
        }
    }

    private var stats: (added: Int, removed: Int, modified: Int) {
        (entries.filter { $0.status == .added }.count,
         entries.filter { $0.status == .removed }.count,
         entries.filter { $0.status == .modified }.count)
    }

    private var modeEntryCount: Int {
        changesOnly ? entries.filter { $0.status.isChange }.count : entries.count
    }

    var body: some View {
        VStack(spacing: 0) {
            PathBar(a: a, b: b, leftAccent: Theme.brandAlt, rightAccent: Theme.brandAlt) { toolbar }
            Divider().opacity(0.4)
            if scanning {
                ProgressView("Scanning folders…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty, let issue = scanIssues.first {
                ContentUnavailableView("Couldn’t scan folders", systemImage: "folder.badge.questionmark",
                                       description: Text(issue))
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
        .onChange(of: query) { _, _ in keepSelectionVisible() }
        .onChange(of: statusFilter) { _, _ in keepSelectionVisible() }
        .onChange(of: changesOnly) { _, _ in keepSelectionVisible() }
    }

    @ViewBuilder
    private var toolbar: some View {
        if scanning {
            StatChip(text: "Scanning…", color: .secondary, systemImage: "arrow.triangle.2.circlepath")
        } else {
            let s = stats
            HStack(spacing: 6) {
                if s.added > 0 { StatChip(text: "+\(s.added)", color: Theme.added) }
                if s.removed > 0 { StatChip(text: "−\(s.removed)", color: Theme.removed) }
                if s.modified > 0 { StatChip(text: "~\(s.modified)", color: Theme.modified) }
                if s.added == 0 && s.removed == 0 && s.modified == 0 && scanIssues.isEmpty {
                    StatChip(text: "Identical", color: Theme.added)
                }
                if !scanIssues.isEmpty {
                    StatChip(text: "\(scanIssues.count) issue\(scanIssues.count == 1 ? "" : "s")",
                             color: Theme.conflict, systemImage: "exclamationmark.triangle.fill")
                }
            }
        }
        GlassSegmentedControl(
            selection: $changesOnly,
            options: [.init(value: true, title: "Changes"), .init(value: false, title: "All")],
            compact: true)
        .fixedSize()
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered, selection: $selection) { entry in
                    HStack(spacing: 8) {
                        Text(entry.error == nil ? entry.status.letter : "!")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.badgeForeground)
                            .frame(width: 18, height: 18)
                            .background(entry.error == nil ? color(entry.status) : Theme.conflict,
                                        in: RoundedRectangle(cornerRadius: 4))
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
                            if let error = entry.error {
                                Text(error).font(.system(size: 9.5)).foregroundStyle(Theme.conflict).lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                    .tag(entry.id)
                    .contextMenu { fileMenu(for: entry) }
                }
                .listStyle(.inset)
            }
            folderFilterBar
        }
    }

    private var folderFilterBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 11.5)).foregroundStyle(.secondary)
            TextField("Filter files", text: $query).textFieldStyle(.plain).font(.system(size: 12))
            Menu {
                Button("All Statuses") { statusFilter = nil }
                Divider()
                ForEach(FolderStatus.allCases, id: \.self) { status in
                    Button {
                        statusFilter = status
                        if status == .identical { changesOnly = false }
                    } label: {
                        Label(status.label, systemImage: statusFilter == status ? "checkmark" : "circle.fill")
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(statusFilter == nil ? Color.gray : color(statusFilter!))
            }
            .menuStyle(.borderlessButton).fixedSize().help("Filter by status")
            if !query.isEmpty || statusFilter != nil {
                Button {
                    query = ""; statusFilter = nil
                } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("Clear filters")
            }
            Text((query.isEmpty && statusFilter == nil) ? "\(modeEntryCount)" : "\(filtered.count)/\(modeEntryCount)")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.ultraThinMaterial)
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
        let request = UUID()
        scanRequest = request
        scanning = true
        entries = []
        scanIssues = []
        guard let aRoot, let bRoot else {
            guard request == scanRequest else { return }
            selection = nil
            scanning = false
            return
        }
        let result = await Task.detached { FolderScanner.scanDetailed(a: aRoot, b: bRoot) }.value
        // A newer refresh of the same folders is just as authoritative as navigating to a new pair.
        // The task key alone cannot distinguish those overlapping, same-key requests.
        guard !Task.isCancelled, request == scanRequest else { return }
        entries = result.entries
        scanIssues = result.issues
        if selection == nil || !result.entries.contains(where: { $0.id == selection }) {
            selection = result.entries.first(where: { $0.status.isChange })?.id
        }
        keepSelectionVisible()
        scanning = false
    }

    private func keepSelectionVisible() {
        guard !filtered.contains(where: { $0.id == selection }) else { return }
        selection = filtered.first?.id
    }
}
