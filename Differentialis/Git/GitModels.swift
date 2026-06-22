import Foundation

struct GitCommit: Identifiable, Hashable {
    let id: String          // full SHA
    var shortSHA: String
    var summary: String
    var author: String
    var date: Date
    var parents: [String]

    var firstParent: String? { parents.first }
}

enum GitFileStatus: String, Hashable {
    case added, modified, deleted, renamed, copied, untracked, conflicted, typeChanged

    init(letter: Character) {
        switch letter {
        case "A": self = .added
        case "M": self = .modified
        case "D": self = .deleted
        case "R": self = .renamed
        case "C": self = .copied
        case "T": self = .typeChanged
        case "U": self = .conflicted
        case "?": self = .untracked
        default: self = .modified
        }
    }

    var label: String { rawValue.capitalized }
    var letter: String {
        switch self {
        case .added: return "A"
        case .modified: return "M"
        case .deleted: return "D"
        case .renamed: return "R"
        case .copied: return "C"
        case .untracked: return "?"
        case .conflicted: return "U"
        case .typeChanged: return "T"
        }
    }
}

struct GitChangedFile: Identifiable, Hashable {
    let id = UUID()
    var path: String
    var oldPath: String?
    var status: GitFileStatus
}

enum GitRefKind: Hashable { case head, branch, remoteBranch, tag }

struct GitRef: Identifiable, Hashable {
    var id: String { fullName }
    var name: String
    var fullName: String
    var kind: GitRefKind

    var symbol: String {
        switch kind {
        case .head: return "smallcircle.filled.circle"
        case .branch: return "arrow.triangle.branch"
        case .remoteBranch: return "cloud"
        case .tag: return "tag"
        }
    }
}

/// One side of a git comparison.
enum GitSide: Hashable {
    case ref(String)        // SHA or ref name
    case workingCopy
}

/// Which working-copy changes to include in a comparison.
enum WorkingScope: String, Codable, Hashable, CaseIterable {
    case all, staged, unstaged

    var label: String {
        switch self {
        case .all: return "All Changes"
        case .staged: return "Staged"
        case .unstaged: return "Unstaged"
        }
    }
}

enum GitError: LocalizedError {
    case notARepository(URL)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notARepository(let url): return "Not a git repository: \(url.path)"
        case .commandFailed(let message): return message
        }
    }
}
