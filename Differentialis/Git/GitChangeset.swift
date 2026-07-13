import Foundation

extension GitRepository {
    // `makeComparison` is called from SwiftUI view bodies, so this must NEVER shell out to git:
    // `Process.waitUntilExit` pumps the run loop, re-enters the SwiftUI update cycle mid-layout
    // and crashes (AttributeGraph precondition / RootGeometry recursion). A `GitRepository` is
    // always created with its working-tree root as `url` (see AppModel.openRepository), so the
    // root is just `url` — no subprocess needed.
    private var rootURL: URL { url }

    private func source(_ side: GitSide, path: String, label: String) -> ComparisonSource {
        switch side {
        case .ref(let ref): return .gitBlob(repo: rootURL, ref: ref, path: path, label: label)
        case .index: return .gitIndex(repo: rootURL, path: path)
        case .indexStage(let stage):
            // `git show :2:path` / `:3:path` addresses the two unmerged index sides. Representing
            // these as git blobs also keeps file properties and content classification working.
            return .gitBlob(repo: rootURL, ref: ":\(stage)", path: path, label: label)
        case .workingCopy: return .workingCopy(repo: rootURL, path: path)
        }
    }

    private func source(_ side: GitSide?, path: String, label: String) -> ComparisonSource {
        guard let side else {
            let name = (path as NSString).lastPathComponent
            return .empty(name: "\(name) — \(label) (absent)")
        }
        return source(side, path: path, label: label)
    }

    /// Build a file-level `Comparison` for a changed file between two git sides.
    func makeComparison(file: GitChangedFile,
                        a: GitSide, aLabel: String,
                        b: GitSide, bLabel: String) -> Comparison {
        if let endpoints = file.comparison {
            return Comparison.make(
                a: source(endpoints.a, path: endpoints.aPath, label: endpoints.aLabel),
                b: source(endpoints.b, path: endpoints.bPath, label: endpoints.bLabel),
                title: file.path)
        }

        let aPath = file.oldPath ?? file.path
        let bPath = file.path

        let aSource: ComparisonSource
        if file.status == .added || file.status == .untracked {
            aSource = .empty(name: file.path)
        } else {
            aSource = source(a, path: aPath, label: aLabel)
        }

        let bSource: ComparisonSource
        if file.status == .deleted {
            bSource = .empty(name: file.path)
        } else {
            bSource = source(b, path: bPath, label: bLabel)
        }

        return Comparison.make(a: aSource, b: bSource, title: file.path)
    }

    /// Resolve a custom comparison (the "Custom Comparison" popover) into a file list + sides.
    /// The "Compare:" (A) side is always a reference/commit; "with:" (B) may be the working copy.
    func customChangeset(a: CustomSide, b: CustomSide) throws -> ResolvedChangeset {
        let aRef = a.refString
        if case .workingCopy(let scope) = b {
            switch scope {
            case .staged:
                let files = try changedFilesFromReferenceToIndex(aRef)
                return ResolvedChangeset(files: files, a: .ref(aRef), aLabel: a.label,
                                         b: .index, bLabel: "Index")
            case .unstaged:
                let files = try changedFilesFromIndexToWorkingTree()
                return ResolvedChangeset(files: files, a: .index, aLabel: "Index",
                                         b: .workingCopy, bLabel: "Working Copy")
            case .all:
                let files = try changedFilesAcrossWorkingLayers(aRef, refLabel: a.label)
                return ResolvedChangeset(files: files, a: .ref(aRef), aLabel: a.label,
                                         b: .workingCopy, bLabel: b.label)
            }
        } else {
            let files = try changedFiles(from: aRef, to: b.refString)
            return ResolvedChangeset(files: files, a: .ref(aRef), aLabel: a.label,
                                     b: .ref(b.refString), bLabel: b.label)
        }
    }

    /// Files changed when viewing a single commit (parent ↔ commit).
    func changeset(forCommit commit: GitCommit) throws -> (files: [GitChangedFile], a: GitSide, b: GitSide, aLabel: String, bLabel: String) {
        let parent = commit.firstParent
        // For a merge commit, `diff-tree <sha>` emits nothing — diff against the first parent so
        // the changeset isn't empty. `diff-tree --root` still handles the parentless root commit.
        let files: [GitChangedFile]
        if let parent {
            files = try changedFiles(from: parent, to: commit.id)
        } else {
            files = try changedFiles(inCommit: commit.id)
        }
        let a: GitSide = .ref(parent ?? "\(commit.id)^")
        let aLabel = parent.map { String($0.prefix(7)) } ?? "—"
        return (files, a, .ref(commit.id), aLabel, commit.shortSHA)
    }
}
