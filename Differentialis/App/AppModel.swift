import SwiftUI
import Observation
import UniformTypeIdentifiers

/// An opened changeset (a custom comparison result or a saved comparison) shown as a file list.
struct OpenChangeset: Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String
    var repo: GitRepository
    var resolved: ResolvedChangeset
}

@MainActor
@Observable
final class AppModel {
    enum Route: Hashable {
        case welcome
        case repository
        case comparison(UUID)
        case changeset(UUID)
    }

    var route: Route = .welcome
    var comparisons: [Comparison] = []
    var changesets: [OpenChangeset] = []

    var repo: GitRepository?
    var repoName: String = ""
    var repoRefs: [GitRef] = []

    var errorMessage: String?
    var showShortcuts = false

    let store = ComparisonStore()
    let projects = RecentProjectsStore()
    let updates = UpdateChecker()
    var openRepoPath: String?
    private var didProcessLaunchArguments = false

    // MARK: - Launch arguments (open files/folders/repo passed on the command line)

    func openFromLaunchArguments() {
        guard !didProcessLaunchArguments else { return }
        didProcessLaunchArguments = true
        let fm = FileManager.default
        let urls = CommandLine.arguments.dropFirst()
            .filter { fm.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return }

        if urls.count == 1, GitRepository.isRepository(urls[0]) {
            openRepository(at: urls[0])
        } else if urls.count >= 3 {
            open(Comparison.merge(base: .file(urls[0]), left: .file(urls[1]), right: .file(urls[2])))
        } else if urls.count >= 2 {
            open(Comparison.make(a: .file(urls[0]), b: .file(urls[1])))
        }
    }

    // MARK: - Opening

    func open(_ comparison: Comparison) {
        if !comparisons.contains(where: { $0.id == comparison.id }) {
            comparisons.append(comparison)
        }
        route = .comparison(comparison.id)
    }

    func openChangeset(_ changeset: OpenChangeset) {
        changesets.append(changeset)
        route = .changeset(changeset.id)
    }

    func comparison(_ id: UUID) -> Comparison? { comparisons.first { $0.id == id } }
    func changeset(_ id: UUID) -> OpenChangeset? { changesets.first { $0.id == id } }

    var selectedComparison: Comparison? {
        if case .comparison(let id) = route { return comparison(id) }
        return nil
    }

    // MARK: - Closing

    func closeComparison(_ id: UUID) {
        comparisons.removeAll { $0.id == id }
        if route == .comparison(id) { route = .welcome }
    }

    func closeChangeset(_ id: UUID) {
        changesets.removeAll { $0.id == id }
        if route == .changeset(id) { route = .welcome }
    }

    // MARK: - Repository

    func openRepository(at url: URL) {
        guard GitRepository.isRepository(url) else {
            errorMessage = "“\(url.lastPathComponent)” is not a git repository."
            return
        }
        let repository = GitRepository(url: url)
        repo = repository
        repoName = repository.displayName()
        repoRefs = (try? repository.refs()) ?? []
        let root = (try? repository.root()) ?? url
        openRepoPath = root.standardizedFileURL.path
        projects.record(name: repository.displayName(), url: root)
        route = .repository
    }

    func openProject(_ project: RecentProject) {
        openRepository(at: project.url)
    }

    func refreshRefs() {
        guard let repo else { return }
        repoRefs = (try? repo.refs()) ?? []
    }

    // MARK: - Custom comparison

    func runCustomComparison(a: CustomSide, b: CustomSide, name: String? = nil) {
        guard let repo else { return }
        do {
            let resolved = try repo.customChangeset(a: a, b: b)
            let title = name ?? "\(a.label) ↔ \(b.label)"
            openChangeset(OpenChangeset(title: title, subtitle: repoName, repo: repo, resolved: resolved))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveCustomComparison(name: String, a: CustomSide, b: CustomSide) {
        guard let repo else { return }
        let root = (try? repo.root()) ?? repo.url
        store.add(SavedComparison(name: name, repoPath: root.path, a: a, b: b, createdAt: Date()))
    }

    func openSaved(_ saved: SavedComparison) {
        let repository = GitRepository(url: saved.repoURL)
        guard GitRepository.isRepository(saved.repoURL) else {
            errorMessage = "The repository for “\(saved.name)” could not be found."
            return
        }
        repo = repository
        repoName = repository.displayName()
        repoRefs = (try? repository.refs()) ?? []
        let root = (try? repository.root()) ?? saved.repoURL
        openRepoPath = root.standardizedFileURL.path
        projects.record(name: repository.displayName(), url: root)
        do {
            let resolved = try repository.customChangeset(a: saved.a, b: saved.b)
            openChangeset(OpenChangeset(title: saved.name, subtitle: saved.repoName,
                                        repo: repository, resolved: resolved))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - File pickers

    func chooseFiles(mode: PickMode) {
        switch mode {
        case .text, .image:
            guard let a = pickFile(prompt: "Choose original (A)"),
                  let b = pickFile(prompt: "Choose modified (B)") else { return }
            open(Comparison.make(a: .file(a), b: .file(b)))
        case .folder:
            guard let a = pickFolder(prompt: "Choose folder A"),
                  let b = pickFolder(prompt: "Choose folder B") else { return }
            open(Comparison.make(a: .file(a), b: .file(b)))
        case .merge:
            guard let base = pickFile(prompt: "Choose base (common ancestor)"),
                  let left = pickFile(prompt: "Choose left (mine)"),
                  let right = pickFile(prompt: "Choose right (theirs)") else { return }
            open(Comparison.merge(base: .file(base), left: .file(left), right: .file(right)))
        case .repository:
            guard let folder = pickFolder(prompt: "Choose a git repository") else { return }
            openRepository(at: folder)
        }
    }

    enum PickMode { case text, image, folder, merge, repository }

    private func pickFile(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.message = prompt
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func pickFolder(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.message = prompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
