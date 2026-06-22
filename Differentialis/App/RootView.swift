import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 340)
        } detail: {
            detail
                .diffCanvasBackground()
        }
        .task { model.openFromLaunchArguments() }
        .alert("Something went wrong",
               isPresented: Binding(get: { model.errorMessage != nil },
                                    set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
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
                ComparisonDetailView(comparison: comparison)
            } else {
                WelcomeView()
            }
        case .changeset(let id):
            if let changeset = model.changeset(id) {
                ChangesetDetailView(changeset: changeset)
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

            if let repo = model.repo {
                Section("Repository") {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.repoName).font(.system(size: 13, weight: .semibold))
                            Text("\(repo.currentBranch() ?? "—")")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .foregroundStyle(Theme.brand)
                    }
                    .tag(AppModel.Route.repository)
                }
            }

            if !model.comparisons.isEmpty || !model.changesets.isEmpty {
                Section("Open") {
                    ForEach(model.comparisons) { comparison in
                        Label(comparison.title, systemImage: comparison.symbol)
                            .lineLimit(1)
                            .tag(AppModel.Route.comparison(comparison.id))
                            .contextMenu {
                                Button("Close", role: .destructive) { model.closeComparison(comparison.id) }
                            }
                    }
                    ForEach(model.changesets) { changeset in
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
                }
            }

            if !model.store.saved.isEmpty {
                Section("Saved Comparisons") {
                    ForEach(model.store.saved) { saved in
                        SavedComparisonRow(saved: saved)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) { sidebarHeader }
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
