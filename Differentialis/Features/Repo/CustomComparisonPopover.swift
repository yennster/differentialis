import SwiftUI

struct CustomComparisonPopover: View {
    let repo: GitRepository
    let commits: [GitCommit]
    let onClose: () -> Void

    @Environment(AppModel.self) private var model

    enum ASideKind: Hashable { case reference, commit }
    enum BSideKind: Hashable { case workingCopy, reference, commit }

    @State private var aKind: ASideKind = .reference
    @State private var bKind: BSideKind = .workingCopy
    @State private var aRef = "HEAD"
    @State private var aCommit = ""
    @State private var bRef = "HEAD"
    @State private var bCommit = ""
    @State private var bScope: WorkingScope = .all
    @State private var saving = false
    @State private var saveName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            HStack(alignment: .top, spacing: 28) {
                compareColumn
                withColumn
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            Divider().padding(.horizontal, 20).padding(.vertical, 14)
            footer
        }
        .padding(.vertical, 16)
        .frame(width: 580)
        .onAppear {
            aCommit = commits.first?.id ?? "HEAD"
            bCommit = commits.first?.id ?? "HEAD"
            bRef = repo.currentBranch() ?? "HEAD"
        }
        .alert("Save comparison", isPresented: $saving) {
            TextField("Name", text: $saveName)
            Button("Save") {
                model.saveCustomComparison(name: saveName.isEmpty ? defaultName : saveName, a: makeA(), b: makeB())
                onClose()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This comparison will appear under Saved Comparisons.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 0) {
                Text("Custom Comparison ").font(.system(size: 15, weight: .bold))
                Text("in \(model.repoName)").font(.system(size: 15)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { compare() } label: {
                Image(systemName: "arrow.up.forward.app").font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.removed)
            .help("Open comparison")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    // MARK: - Columns

    private var compareColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Compare:").font(.system(size: 13, weight: .semibold))
            GlassSegmentedControl(
                selection: $aKind,
                options: [.init(value: .reference, title: "Reference"), .init(value: .commit, title: "Commit")],
                compact: true)
            if aKind == .reference {
                refMenu(selection: $aRef)
            } else {
                commitMenu(selection: $aCommit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var withColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("with:").font(.system(size: 13, weight: .semibold))
            GlassSegmentedControl(
                selection: $bKind,
                options: [.init(value: .workingCopy, title: "Working Copy"),
                          .init(value: .reference, title: "Reference"),
                          .init(value: .commit, title: "Commit")],
                compact: true)
            switch bKind {
            case .workingCopy: scopeMenu(selection: $bScope)
            case .reference: refMenu(selection: $bRef)
            case .commit: commitMenu(selection: $bCommit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refMenu(selection: Binding<String>) -> some View {
        Menu {
            ForEach(model.repoRefs) { ref in
                Button { selection.wrappedValue = ref.name } label: {
                    Label(ref.name, systemImage: ref.symbol)
                }
            }
        } label: {
            menuLabel(icon: "arrow.triangle.branch", text: selection.wrappedValue)
        }
        .menuStyle(.borderlessButton)
    }

    private func commitMenu(selection: Binding<String>) -> some View {
        Menu {
            ForEach(commits.prefix(60)) { commit in
                Button { selection.wrappedValue = commit.id } label: {
                    Text("\(commit.shortSHA)  \(commit.summary)")
                }
            }
        } label: {
            let commit = commits.first { $0.id == selection.wrappedValue }
            menuLabel(icon: "smallcircle.filled.circle",
                      text: commit.map { "\($0.shortSHA)  \($0.summary)" } ?? "Select commit")
        }
        .menuStyle(.borderlessButton)
    }

    private func scopeMenu(selection: Binding<WorkingScope>) -> some View {
        Menu {
            ForEach(WorkingScope.allCases, id: \.self) { scope in
                Button(scope.label) { selection.wrappedValue = scope }
            }
        } label: {
            menuLabel(icon: "pencil.and.list.clipboard", text: selection.wrappedValue.label)
        }
        .menuStyle(.borderlessButton)
    }

    private func menuLabel(icon: String, text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(text).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
            Spacer()
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.08)))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button { swap() } label: {
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 13, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.borderless)
            .background(.black.opacity(0.25), in: Circle())
            .help("Swap sides")

            Spacer()

            Button { saveName = defaultName; saving = true } label: {
                Label("Save", systemImage: "bookmark")
            }
            .buttonStyle(.bordered)

            Button { compare() } label: {
                Text("Compare").fontWeight(.semibold).padding(.horizontal, 10)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.brand)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Logic

    private func makeA() -> CustomSide {
        aKind == .reference ? .reference(aRef) : .commit(aCommit)
    }
    private func makeB() -> CustomSide {
        switch bKind {
        case .workingCopy: return .workingCopy(bScope)
        case .reference: return .reference(bRef)
        case .commit: return .commit(bCommit)
        }
    }
    private var defaultName: String { "\(makeA().label) ↔ \(makeB().label)" }

    private func compare() {
        model.runCustomComparison(a: makeA(), b: makeB())
        onClose()
    }

    private func swap() {
        // Swap is only meaningful when both sides are refs/commits.
        let oldARef = aRef, oldACommit = aCommit, oldAKind = aKind
        if bKind != .workingCopy {
            aKind = bKind == .reference ? .reference : .commit
            aRef = bRef; aCommit = bCommit
            bKind = oldAKind == .reference ? .reference : .commit
            bRef = oldARef; bCommit = oldACommit
        }
    }
}
