import SwiftUI
import AppKit

struct RepositoryView: View {
    let repo: GitRepository
    @Environment(AppModel.self) private var model

    @State private var commits: [GitCommit] = []
    @State private var selectedCommit: GitCommit.ID?
    @State private var changeset: ResolvedChangeset?
    @State private var showCustom = false
    @State private var loading = true

    var body: some View {
        HSplitView {
            commitList
                .frame(minWidth: 280, idealWidth: 340, maxWidth: 480)
            commitDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar { toolbarContent }
        .task(id: repo.url.path) { await loadCommits() }
        .onChange(of: selectedCommit) { _, _ in loadChangeset() }
    }

    // MARK: - Commit list

    private var commitList: some View {
        VStack(spacing: 0) {
            HStack {
                Label("\(commits.count) commits", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider().opacity(0.4)
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(commits, selection: $selectedCommit) { commit in
                    CommitRow(commit: commit).tag(commit.id)
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: - Commit detail

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
