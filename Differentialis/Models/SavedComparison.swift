import Foundation

/// One selectable side of a custom git comparison.
enum CustomSide: Codable, Hashable {
    case reference(String)        // e.g. "HEAD", "main", "origin/main"
    case commit(String)           // SHA
    case workingCopy(WorkingScope)

    var refString: String {
        switch self {
        case .reference(let name): return name
        case .commit(let sha): return sha
        case .workingCopy: return "HEAD"
        }
    }

    var label: String {
        switch self {
        case .reference(let name): return name
        case .commit(let sha): return String(sha.prefix(7))
        case .workingCopy(let scope): return "Working Copy · \(scope.label)"
        }
    }

    var isWorkingCopy: Bool {
        if case .workingCopy = self { return true }
        return false
    }
}

/// A named custom comparison the user has saved to revisit later.
struct SavedComparison: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var repoPath: String
    var a: CustomSide
    var b: CustomSide
    var createdAt: Date

    var repoURL: URL { URL(fileURLWithPath: repoPath) }
    var repoName: String { (repoPath as NSString).lastPathComponent }
}

/// The fully resolved file list + sides for a custom comparison.
struct ResolvedChangeset {
    var files: [GitChangedFile]
    var a: GitSide
    var aLabel: String
    var b: GitSide
    var bLabel: String
}
