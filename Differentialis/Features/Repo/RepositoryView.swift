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
    @State private var selectedChangesetFile: GitChangedFile.ID?
    @State private var loading = true

    @State private var workingFiles: [GitChangedFile] = []
    @State private var selectedFile: GitChangedFile.ID?
    @State private var fileFilter = ""

    @State private var showCustom = false
    @State private var leftCollapsed = false
    @State private var changesetFilesCollapsed = false

    var body: some View {
        Group {
            switch mode {
            case .commits: commitsLayout
            case .files: filesLayout
            }
        }
        .toolbar { toolbarContent }
        .task(id: repo.url.path) {
            await loadCommits()
            await loadWorkingFiles()
        }
        .onChange(of: selectedCommit) { _, _ in Task { await loadChangeset() } }
        .onChange(of: mode) { _, newMode in if newMode == .files { Task { await loadWorkingFiles() } } }
    }

    // MARK: - Layout
    //
    // Commits mode is a single three-pane split — commit list · changed files · diff — rather than
    // a commit-list HSplitView wrapping the changeset's own HSplitView. Collapsing that two-level
    // nesting into one NSSplitView keeps the layout's width distribution predictable (nested
    // NSSplitViews fight over width and resize nondeterministically). The window-left sidebar is
    // kept clip-free separately, by RootView's fixed-width sidebar pane.

    @ViewBuilder
    private var commitsLayout: some View {
        HSplitView {
            listColumn { commitListContent }
            if changesetFilesCollapsed {
                CollapsedRail(title: "Files") { withAnimation(.panel) { changesetFilesCollapsed = false } }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            } else {
                changesetFilesColumn
                    .frame(minWidth: 180, idealWidth: 280, maxWidth: 360, maxHeight: .infinity)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            changesetDiffColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var filesLayout: some View {
        HSplitView {
            listColumn { filesListContent }
            workingFileDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // The leading list column (commits or working files), or a thin rail when collapsed.
    @ViewBuilder
    private func listColumn<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if leftCollapsed {
            CollapsedRail(title: leftCollapsedTitle) { withAnimation(.panel) { leftCollapsed = false } }
                .transition(.move(edge: .leading).combined(with: .opacity))
        } else {
            VStack(spacing: 0) {
                leftHeader
                Divider().opacity(0.4)
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 240, idealWidth: 320, maxWidth: 460, maxHeight: .infinity)
            .transition(.move(edge: .leading).combined(with: .opacity))
        }
    }

    private var leftCollapsedTitle: String {
        mode == .commits ? "History" : "Files"
    }

    private var leftHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                modeButton(.commits, icon: "clock.arrow.circlepath", help: "Commit history")
                modeButton(.files, icon: "list.bullet", help: "Changed files")
            }
            .padding(2)
            .background(.black.opacity(0.22), in: Capsule())
            Text(leftCollapsedTitle)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.7))
            Spacer()
            Text(mode == .commits ? "\(commits.count) commits" : "\(filteredWorkingFiles.count) files")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Button { withAnimation(.panel) { leftCollapsed = true } } label: {
                Image(systemName: "sidebar.left")
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless).help("Hide list")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func modeButton(_ m: Mode, icon: String, help: String) -> some View {
        Button { mode = m } label: {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(mode == m ? .white : .secondary)
                .frame(width: 32, height: 22)
                .background(mode == m ? Theme.brand : .clear, in: Capsule())
                // Without this the inactive button's .clear background isn't hit-tested, so only the
                // tiny icon is clickable and switching modes feels broken. Make the whole pill tappable.
                .contentShape(Capsule())
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

    // The selected commit's changed files (middle pane in commits mode), with a header that can
    // collapse the pane to a rail to give the diff more room.
    private var changesetFilesColumn: some View {
        let count = changeset?.files.count ?? 0
        return VStack(spacing: 0) {
            HStack {
                Text("Files")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.7))
                Spacer()
                Text("\(count) file\(count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Button { withAnimation(.panel) { changesetFilesCollapsed = true } } label: {
                    Image(systemName: "sidebar.left")
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless).help("Hide files")
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            Divider().opacity(0.4)
            changesetFilesList
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var changesetFilesList: some View {
        if let changeset, !changeset.files.isEmpty {
            List(changeset.files, selection: $selectedChangesetFile) { file in
                fileRow(file).tag(file.id)
            }
            .listStyle(.inset)
        } else if loading {
            ProgressView()
        } else {
            Color.clear
        }
    }

    // The selected file's diff, under a header for the selected commit (trailing pane in commits mode).
    @ViewBuilder
    private var changesetDiffColumn: some View {
        if let commit = commits.first(where: { $0.id == selectedCommit }), let changeset,
           let file = changeset.files.first(where: { $0.id == selectedChangesetFile }) ?? changeset.files.first {
            VStack(spacing: 0) {
                commitHeader(commit)
                Divider().opacity(0.4)
                ComparisonDetailView(comparison: repo.makeComparison(
                    file: file, a: changeset.a, aLabel: changeset.aLabel,
                    b: changeset.b, bLabel: changeset.bLabel))
                    .id(file.id)
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
        NSWorkspace.shared.activateFileViewerSelecting([repo.url])
    }

    private func openTerminal() {
        NSWorkspace.shared.open([repo.url], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    // Git drives the `git` binary synchronously (Process.waitUntilExit), which pumps
    // the run loop. Running that on the main actor from inside a SwiftUI update cycle
    // re-enters the update driver and crashes (EXC_BAD_ACCESS), so every git call below
    // is hopped off the main thread via Task.detached and only the results land back on it.

    private func loadCommits() async {
        loading = true
        let repo = repo
        commits = await Task.detached { (try? repo.commits(limit: 300)) ?? [] }.value
        selectedCommit = commits.first?.id
        loading = false
        await loadChangeset()
    }

    private func loadChangeset() async {
        guard let commit = commits.first(where: { $0.id == selectedCommit }) else {
            changeset = nil; selectedChangesetFile = nil; return
        }
        let repo = repo
        let result = await Task.detached { try? repo.changeset(forCommit: commit) }.value
        if let result {
            changeset = ResolvedChangeset(files: result.files, a: result.a, aLabel: result.aLabel,
                                          b: result.b, bLabel: result.bLabel)
            selectedChangesetFile = result.files.first?.id
        } else {
            changeset = nil
            selectedChangesetFile = nil
        }
    }

    private func loadWorkingFiles() async {
        let repo = repo
        let files = await Task.detached { (try? repo.workingChanges(scope: .all)) ?? [] }.value
        workingFiles = files
        if selectedFile == nil || !files.contains(where: { $0.id == selectedFile }) {
            selectedFile = files.first?.id
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
