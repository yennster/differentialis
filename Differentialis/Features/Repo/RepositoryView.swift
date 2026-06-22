import SwiftUI
import AppKit

struct RepositoryView: View {
    let repo: GitRepository
    @Environment(AppModel.self) private var model

    enum Mode: Hashable { case commits, files }

    @State private var mode: Mode = .commits
    @State private var commits: [GitCommit] = []
    @State private var selectedCommit: GitCommit.ID?
    @State private var changeset: ResolvedChangeset?
    @State private var loading = true

    @State private var workingFiles: [GitChangedFile] = []
    @State private var selectedFile: GitChangedFile.ID?
    @State private var fileFilter = ""

    @State private var showCustom = false

    var body: some View {
        HSplitView {
            leftPane
                .frame(minWidth: 240, idealWidth: 320, maxWidth: 460)
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar { toolbarContent }
        .task(id: repo.url.path) {
            await loadCommits()
            loadWorkingFiles()
        }
        .onChange(of: selectedCommit) { _, _ in loadChangeset() }
        .onChange(of: mode) { _, newMode in if newMode == .files { loadWorkingFiles() } }
    }

    // MARK: - Left pane (commits or files)

    private var leftPane: some View {
        VStack(spacing: 0) {
            leftHeader
            Divider().opacity(0.4)
            switch mode {
            case .commits: commitListContent
            case .files: filesListContent
            }
        }
    }

    private var leftHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                modeButton(.commits, icon: "clock.arrow.circlepath", help: "Commit history")
                modeButton(.files, icon: "list.bullet", help: "Changed files")
            }
            .padding(2)
            .background(.black.opacity(0.22), in: Capsule())
            Spacer()
            Text(mode == .commits ? "\(commits.count) commits" : "\(filteredWorkingFiles.count) files")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func modeButton(_ m: Mode, icon: String, help: String) -> some View {
        Button { mode = m } label: {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(mode == m ? .white : .secondary)
                .frame(width: 32, height: 22)
                .background(mode == m ? Theme.brand : .clear, in: Capsule())
        }
        .buttonStyle(.plain).help(help)
    }

    @ViewBuilder
    private var commitListContent: some View {
        if loading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(commits, selection: $selectedCommit) { commit in
                CommitRow(commit: commit).tag(commit.id)
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private var filesListContent: some View {
        if workingFiles.isEmpty {
            ContentUnavailableView("No working changes", systemImage: "checkmark.circle",
                                   description: Text("Your working tree matches HEAD."))
        } else {
            VStack(spacing: 0) {
                List(selection: $selectedFile) {
                    ForEach(groupedWorkingFiles, id: \.dir) { group in
                        Section(group.dir.isEmpty ? "/" : group.dir) {
                            ForEach(group.files) { file in
                                fileRow(file).tag(file.id)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 12)).foregroundStyle(.secondary)
                    TextField("Filter files", text: $fileFilter).textFieldStyle(.plain).font(.system(size: 12))
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.ultraThinMaterial)
            }
        }
    }

    private func fileRow(_ file: GitChangedFile) -> some View {
        HStack(spacing: 8) {
            Text(file.status.letter)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(file.status.tint, in: RoundedRectangle(cornerRadius: 4))
            Text((file.path as NSString).lastPathComponent)
                .font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
            Spacer()
        }
    }

    private var filteredWorkingFiles: [GitChangedFile] {
        let query = fileFilter.trimmingCharacters(in: .whitespaces).lowercased()
        return query.isEmpty ? workingFiles : workingFiles.filter { $0.path.lowercased().contains(query) }
    }

    private var groupedWorkingFiles: [(dir: String, files: [GitChangedFile])] {
        let groups = Dictionary(grouping: filteredWorkingFiles) { ($0.path as NSString).deletingLastPathComponent }
        return groups.keys.sorted().map { (dir: $0, files: groups[$0]!.sorted { $0.path < $1.path }) }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailPane: some View {
        switch mode {
        case .commits: commitDetail
        case .files: workingFileDetail
        }
    }

    @ViewBuilder
    private var commitDetail: some View {
        if let commit = commits.first(where: { $0.id == selectedCommit }), let changeset {
            VStack(spacing: 0) {
                commitHeader(commit)
                Divider().opacity(0.4)
                GitChangesetView(repo: repo, files: changeset.files,
                                 a: changeset.a, aLabel: changeset.aLabel,
                                 b: changeset.b, bLabel: changeset.bLabel)
            }
        } else {
            ContentUnavailableView("Select a commit", systemImage: "point.3.filled.connected.trianglepath.dotted",
                                   description: Text("Choose a commit to review its changes, or open a Custom Comparison."))
        }
    }

    @ViewBuilder
    private var workingFileDetail: some View {
        if let file = filteredWorkingFiles.first(where: { $0.id == selectedFile }) ?? filteredWorkingFiles.first {
            ComparisonDetailView(comparison: repo.makeComparison(
                file: file, a: .ref("HEAD"), aLabel: "HEAD", b: .workingCopy, bLabel: "Working Copy"))
                .id(file.id)
        } else {
            ContentUnavailableView("Working copy", systemImage: "pencil.and.list.clipboard",
                                   description: Text("Select a changed file to see its diff against HEAD."))
        }
    }

    private func commitHeader(_ commit: GitCommit) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(commit.summary).font(.system(size: 13.5, weight: .semibold)).lineLimit(2)
                Text("\(commit.author) · \(commit.shortSHA) · \(commit.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { revealInFinder() } label: { Image(systemName: "folder") }
                .help("Reveal in Finder")
            Button { openTerminal() } label: { Image(systemName: "terminal") }
                .help("Open in Terminal")
            Button { showCustom.toggle() } label: {
                Image(systemName: "arrow.triangle.branch")
            }
            .help("Custom Comparison")
            .popover(isPresented: $showCustom, arrowEdge: .bottom) {
                CustomComparisonPopover(repo: repo, commits: commits) { showCustom = false }
                    .environment(model)
            }
        }
    }

    // MARK: - Actions

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([(try? repo.root()) ?? repo.url])
    }

    private func openTerminal() {
        let url = (try? repo.root()) ?? repo.url
        NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    private func loadCommits() async {
        loading = true
        commits = (try? repo.commits(limit: 300)) ?? []
        selectedCommit = commits.first?.id
        loading = false
        loadChangeset()
    }

    private func loadChangeset() {
        guard let commit = commits.first(where: { $0.id == selectedCommit }) else { changeset = nil; return }
        if let result = try? repo.changeset(forCommit: commit) {
            changeset = ResolvedChangeset(files: result.files, a: result.a, aLabel: result.aLabel,
                                          b: result.b, bLabel: result.bLabel)
        } else {
            changeset = nil
        }
    }

    private func loadWorkingFiles() {
        workingFiles = (try? repo.workingChanges(scope: .all)) ?? []
        if selectedFile == nil || !workingFiles.contains(where: { $0.id == selectedFile }) {
            selectedFile = workingFiles.first?.id
        }
    }
}

struct CommitRow: View {
    let commit: GitCommit

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.brand.gradient).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(commit.summary).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(commit.author).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    Text(commit.shortSHA).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.brandAlt)
                    Text(commit.date.formatted(.relative(presentation: .numeric)))
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
