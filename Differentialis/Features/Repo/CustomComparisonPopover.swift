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
    @AppStorage private var aCommit: String
    @State private var bRef = "HEAD"
    @AppStorage private var bCommit: String
    @State private var bScope: WorkingScope = .all
    @State private var saving = false
    @State private var saveName = ""

    init(repo: GitRepository, commits: [GitCommit], onClose: @escaping () -> Void) {
        self.repo = repo
        self.commits = commits
        self.onClose = onClose
        let draftKey = "customComparison.\(repo.url.standardizedFileURL.path)"
        _aCommit = AppStorage(wrappedValue: "", "\(draftKey).aCommit")
        _bCommit = AppStorage(wrappedValue: "", "\(draftKey).bCommit")
    }

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
            // Preserve anything the user pasted here across presentations and app launches. Only
            // seed a side from history when that repository has never had a saved draft value.
            if trimmed(aCommit).isEmpty { aCommit = commits.first?.id ?? "HEAD" }
            if trimmed(bCommit).isEmpty { bCommit = commits.first?.id ?? "HEAD" }
        }
        .task {
            bRef = await offMain { repo.currentBranch() ?? "HEAD" }
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

    /// Paste/type any commit hash, or pick one from history. Arbitrary SHAs resolve at compare time.
    private func commitMenu(selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: "number").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Paste a commit hash", text: selection)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                Menu {
                    ForEach(commits.prefix(60)) { commit in
                        Button("\(commit.shortSHA)  \(commit.summary)") { selection.wrappedValue = commit.id }
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help("Pick from history")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.08)))

            if let subject = resolvedSubject(for: selection.wrappedValue) {
                Text(subject).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
        }
    }

    private func resolvedSubject(for hash: String) -> String? {
        let h = hash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty else { return nil }
        if let c = commits.first(where: { $0.id == h || $0.id.hasPrefix(h) || $0.shortSHA == h }) {
            return c.summary
        }
        return "Resolves “\(h)” when you Compare"
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
        aKind == .reference ? .reference(trimmed(aRef)) : .commit(trimmed(aCommit))
    }
    private func makeB() -> CustomSide {
        switch bKind {
        case .workingCopy: return .workingCopy(bScope)
        case .reference: return .reference(trimmed(bRef))
        case .commit: return .commit(trimmed(bCommit))
        }
    }

    /// Trim pasted refs/hashes — a trailing space or newline from the clipboard otherwise makes
    /// `git` fail with "unknown revision" on an otherwise-valid hash.
    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
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
