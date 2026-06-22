import Foundation

extension GitRepository {
    private var rootURL: URL { (try? root()) ?? url }

    private func source(_ side: GitSide, path: String, label: String) -> ComparisonSource {
        switch side {
        case .ref(let ref): return .gitBlob(repo: rootURL, ref: ref, path: path, label: label)
        case .workingCopy: return .workingCopy(repo: rootURL, path: path)
        }
    }

    /// Build a file-level `Comparison` for a changed file between two git sides.
    func makeComparison(file: GitChangedFile,
                        a: GitSide, aLabel: String,
                        b: GitSide, bLabel: String) -> Comparison {
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
            let files: [GitChangedFile]
            switch scope {
            case .staged:
                files = parseNameStatus(try run(["diff", "--name-status", "-M", "--cached", aRef]))
            case .all, .unstaged:
                files = parseNameStatus(try run(["diff", "--name-status", "-M", aRef]))
            }
            return ResolvedChangeset(files: files, a: .ref(aRef), aLabel: a.label,
                                     b: .workingCopy, bLabel: b.label)
        } else {
            let files = try changedFiles(from: aRef, to: b.refString)
            return ResolvedChangeset(files: files, a: .ref(aRef), aLabel: a.label,
                                     b: .ref(b.refString), bLabel: b.label)
        }
    }

    /// Files changed when viewing a single commit (parent ↔ commit).
    func changeset(forCommit commit: GitCommit) throws -> (files: [GitChangedFile], a: GitSide, b: GitSide, aLabel: String, bLabel: String) {
        let files = try changedFiles(inCommit: commit.id)
        let parent = commit.firstParent
        let a: GitSide = .ref(parent ?? "\(commit.id)^")
        let aLabel = parent.map { String($0.prefix(7)) } ?? "—"
        return (files, a, .ref(commit.id), aLabel, commit.shortSHA)
    }
}
