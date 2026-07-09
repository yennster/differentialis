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
    static var shared: AppModel!

    init() { AppModel.shared = self }

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

    // MARK: - Opening from paths (command line or `open` Apple Event)

    /// Routes file/folder URLs into the right view. Shared by launch-argument parsing and the
    /// `application(_:open:)` Apple Event handler so `open -a Differentialis <path>` lands in the
    /// app whether it is being launched or already running — not just on a fresh launch.
    func open(urls: [URL]) async {
        guard !urls.isEmpty else { return }

        if urls.count == 1 {
            // openRepositoryImpl re-checks isRepository and surfaces "'X' is not a git
            // repository." as an in-app error, so CLI users get feedback instead of a
            // silent no-op on a single non-repo path.
            openRepository(at: urls[0])
        } else if urls.count >= 3 {
            open(Comparison.merge(base: .file(urls[0]), left: .file(urls[1]), right: .file(urls[2])))
        } else {
            open(Comparison.make(a: .file(urls[0]), b: .file(urls[1])))
        }
    }

    func openFromLaunchArguments() async {
        guard !didProcessLaunchArguments else { return }
        didProcessLaunchArguments = true
        let fm = FileManager.default
        let urls = CommandLine.arguments.dropFirst()
            .filter { fm.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return }
        await open(urls: urls)
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

    // Opening a repository runs several git commands (rev-parse, refs). They are hopped off the
    // main actor so the sidebar click never blocks the run loop. The route flips once they finish.
    func openRepository(at url: URL) {
        Task { await openRepositoryImpl(at: url) }
    }

    private func openRepositoryImpl(at url: URL) async {
        guard await offMain({ GitRepository.isRepository(url) }) else {
            errorMessage = "“\(url.lastPathComponent)” is not a git repository."
            return
        }
        let probe = GitRepository(url: url)
        let info = await offMain { () -> (name: String, refs: [GitRef], root: URL) in
            let root = (try? probe.root()) ?? url
            return (root.lastPathComponent, (try? probe.refs()) ?? [], root)
        }
        // Store the repository keyed on its working-tree root, so `rootURL` (used by makeComparison
        // in view bodies) is just `url` and never has to run git on the main thread.
        repo = GitRepository(url: info.root)
        repoName = info.name
        repoRefs = info.refs
        openRepoPath = info.root.standardizedFileURL.path
        projects.record(name: info.name, url: info.root)
        route = .repository
    }

    func openProject(_ project: RecentProject) {
        openRepository(at: project.url)
    }

    func refreshRefs() {
        guard let repo else { return }
        Task {
            let refs = await offMain { (try? repo.refs()) ?? [] }
            repoRefs = refs
        }
    }

    // MARK: - Custom comparison

    func runCustomComparison(a: CustomSide, b: CustomSide, name: String? = nil) {
        guard let repo else { return }
        Task {
            let outcome = await offMain { () -> (ResolvedChangeset?, String?) in
                do { return (try repo.customChangeset(a: a, b: b), nil) }
                catch { return (nil, error.localizedDescription) }
            }
            if let resolved = outcome.0 {
                let title = name ?? "\(a.label) ↔ \(b.label)"
                openChangeset(OpenChangeset(title: title, subtitle: repoName, repo: repo, resolved: resolved))
            } else {
                errorMessage = outcome.1
            }
        }
    }

    func saveCustomComparison(name: String, a: CustomSide, b: CustomSide) {
        guard let repo else { return }
        Task {
            let root = await offMain { (try? repo.root()) ?? repo.url }
            store.add(SavedComparison(name: name, repoPath: root.path, a: a, b: b, createdAt: Date()))
        }
    }

    func openSaved(_ saved: SavedComparison) {
        Task { await openSavedImpl(saved) }
    }

    private func openSavedImpl(_ saved: SavedComparison) async {
        let probe = GitRepository(url: saved.repoURL)
        guard await offMain({ GitRepository.isRepository(saved.repoURL) }) else {
            errorMessage = "The repository for “\(saved.name)” could not be found."
            return
        }
        let info = await offMain { () -> (name: String, refs: [GitRef], root: URL) in
            let root = (try? probe.root()) ?? saved.repoURL
            return (root.lastPathComponent, (try? probe.refs()) ?? [], root)
        }
        // Keyed on the working-tree root so makeComparison's rootURL never runs git (see GitChangeset).
        let repository = GitRepository(url: info.root)
        repo = repository
        repoName = info.name
        repoRefs = info.refs
        openRepoPath = info.root.standardizedFileURL.path
        projects.record(name: info.name, url: info.root)
        let outcome = await offMain { () -> (ResolvedChangeset?, String?) in
            do { return (try repository.customChangeset(a: saved.a, b: saved.b), nil) }
            catch { return (nil, error.localizedDescription) }
        }
        if let resolved = outcome.0 {
            openChangeset(OpenChangeset(title: saved.name, subtitle: saved.repoName,
                                        repo: repository, resolved: resolved))
        } else {
            errorMessage = outcome.1
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
