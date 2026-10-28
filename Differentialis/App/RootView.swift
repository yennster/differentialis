import SwiftUI
import AppKit

struct RootView: View {
    static let windowID = "main"

    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var sidebarVisible = true

    var body: some View {
        @Bindable var model = model
        // A plain fixed-width sidebar instead of NavigationSplitView. NavigationSplitView's
        // balanced/prominent styles squeeze the sidebar below its minimum width (clipping its
        // content off the window's left edge) when the multi-pane repository detail competes
        // for width — and no column-width setting overrides that. A fixed HStack pane can never
        // be squeezed. The detail is wrapped in a NavigationStack so its `.toolbar` items still
        // populate the window toolbar; that toolbar also hosts the sidebar toggle.
        HStack(spacing: 0) {
            if sidebarVisible {
                SidebarView()
                    .frame(width: 272)
                    .transition(.move(edge: .leading))
                Divider()
            }
            NavigationStack {
                detail
                    .diffCanvasBackground()
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button {
                                withAnimation(.snappy) { sidebarVisible.toggle() }
                            } label: {
                                Image(systemName: "sidebar.left")
                            }
                            .help("Toggle Sidebar")
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            model.showMainWindow = { [openWindow] in
                if NSApp.isHidden {
                    NSApp.unhide(nil)
                    return
                }
                // The Settings window (SwiftUI's "com_apple_SwiftUI_Settings_window") doesn't count.
                let mainWindows = NSApp.windows.filter {
                    $0.canBecomeMain && $0.identifier?.rawValue.contains("Settings") != true
                }
                guard !mainWindows.contains(where: \.isVisible) else { return }
                if let minimized = mainWindows.first(where: \.isMiniaturized) {
                    minimized.deminiaturize(nil)
                } else {
                    openWindow(id: RootView.windowID)
                }
            }
        }
        .task {
            await model.openFromLaunchArguments()
            await model.restoreOpenChangesets()
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { model.errorMessage != nil },
                                    set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(isPresented: Binding(get: { model.showShortcuts },
                                    set: { model.showShortcuts = $0 })) {
            KeyboardShortcutsView()
        }
        .overlay(alignment: .bottom) {
            if let update = model.updater.available {
                UpdateBanner(update: update)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: model.updater.available)
    }

    @ViewBuilder
    private var detail: some View {
        switch model.route {
        case .welcome:
            WelcomeView()
        case .repository:
            if let repo = model.repo {
                RepositoryView(repo: repo)
            } else {
                WelcomeView()
            }
        case .comparison(let id):
            if let comparison = model.comparison(id) {
                // .id keys the subtree to the comparison so switching tabs fully resets child state
                // (scroll position, selection, stale content) instead of reusing the prior view.
                ComparisonDetailView(comparison: comparison)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if comparison.waitToken != nil {
                            CommandLineWaitBanner(comparison: comparison)
                        }
                    }
                    .id(comparison.id)
            } else {
                WelcomeView()
            }
        case .changeset(let id):
            if let changeset = model.changeset(id) {
                ChangesetDetailView(changeset: changeset)
                    .id(changeset.id)
            } else {
                WelcomeView()
            }
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: Binding(get: { model.route }, set: { if let r = $0 { model.route = r } })) {
            Label("Welcome", systemImage: "sparkles")
                .tag(AppModel.Route.welcome)

            Section {
                ForEach(model.projects.projects) { project in
                    ProjectRow(project: project)
                    ForEach(openChangesets(for: project)) { changeset in
                        changesetRow(changeset)
                            .padding(.leading, 14)
                    }
                    ForEach(savedComparisons(for: project)) { saved in
                        SavedComparisonRow(saved: saved)
                            .padding(.leading, 14)
                    }
                }
                Button {
                    model.chooseFiles(mode: .repository)
                } label: {
                    Label("Open Repository…", systemImage: "plus.circle")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } header: {
                Text("Projects")
            }

            if !model.comparisons.isEmpty || !orphanChangesets.isEmpty {
                Section("Open") {
                    ForEach(model.comparisons) { comparison in
                        Label(comparison.title, systemImage: comparison.symbol)
                            .lineLimit(1)
                            .tag(AppModel.Route.comparison(comparison.id))
                            .contextMenu {
                                Button("Close", role: .destructive) { model.closeComparison(comparison.id) }
                            }
                    }
                    ForEach(orphanChangesets) { changeset in
                        changesetRow(changeset)
                    }
                }
            }

            if !orphanedSaved.isEmpty {
                Section("Saved Comparisons") {
                    ForEach(orphanedSaved) { saved in
                        SavedComparisonRow(saved: saved)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.canvasTop)
        .safeAreaInset(edge: .top) { sidebarHeader }
    }

    private func changesetRow(_ changeset: OpenChangeset) -> some View {
        Label {
            Text(changeset.title).lineLimit(1)
        } icon: {
            Image(systemName: "square.stack.3d.up").foregroundStyle(Theme.brandAlt)
        }
        .tag(AppModel.Route.changeset(changeset.id))
        .contextMenu {
            Button("Close", role: .destructive) { model.closeChangeset(changeset.id) }
        }
    }

    /// Open changesets nested under the project they belong to.
    private func openChangesets(for project: RecentProject) -> [OpenChangeset] {
        model.changesets.filter { $0.repoPath == project.path }
    }

    /// Open changesets whose repository isn't in the Projects list; they stay in "Open".
    private var orphanChangesets: [OpenChangeset] {
        let projectPaths = Set(model.projects.projects.map(\.path))
        return model.changesets.filter { !projectPaths.contains($0.repoPath) }
    }

    /// Saved comparisons that belong to a project in the Projects list, shown nested
    /// under that project's row.
    private func savedComparisons(for project: RecentProject) -> [SavedComparison] {
        model.store.saved.filter { $0.repoPath == project.path }
    }

    /// Saved comparisons whose repository is no longer in the Projects list.
    private var orphanedSaved: [SavedComparison] {
        let projectPaths = Set(model.projects.projects.map(\.path))
        return model.store.saved.filter { !projectPaths.contains($0.repoPath) }
    }

    private var sidebarHeader: some View {
        HStack(spacing: 10) {
            DiffMarkView(size: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text("Differentialis")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("Compare · Merge")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

struct ProjectRow: View {
    @Environment(AppModel.self) private var model
    let project: RecentProject

    private var isOpen: Bool { model.route == .repository && model.openRepoPath == project.path }

    var body: some View {
        Button {
            model.openProject(project)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(project.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(project.parentPath).font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            } icon: {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(isOpen ? Theme.brand : .secondary)
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(isOpen ? Theme.brand.opacity(0.16) : Color.clear)
        .contextMenu {
            Button("Open") { model.openProject(project) }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([project.url]) }
            Button("Remove from List", role: .destructive) { model.projects.remove(project) }
        }
    }
}

struct SavedComparisonRow: View {
    @Environment(AppModel.self) private var model
    let saved: SavedComparison
    @State private var renaming = false
    @State private var draftName = ""

    var body: some View {
        Button {
            model.openSaved(saved)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(saved.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                    Text("\(saved.a.label) ↔ \(saved.b.label)")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            } icon: {
                Image(systemName: "bookmark.fill").foregroundStyle(Theme.brand)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open") { model.openSaved(saved) }
            Button("Rename…") { draftName = saved.name; renaming = true }
            Button("Delete", role: .destructive) { model.store.remove(saved) }
        }
        .alert("Rename comparison", isPresented: $renaming) {
            TextField("Name", text: $draftName)
            Button("Save") { model.store.rename(saved, to: draftName) }
            Button("Cancel", role: .cancel) {}
        }
    }
}
