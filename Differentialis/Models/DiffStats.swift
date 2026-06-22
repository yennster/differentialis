import Foundation

struct DiffStats: Hashable {
    var insertions: Int = 0
    var deletions: Int = 0
    var modifications: Int = 0

    var totalChanges: Int { insertions + deletions + modifications }
    var isIdentical: Bool { totalChanges == 0 }

    var summary: String {
        if isIdentical { return "No differences" }
        var parts: [String] = []
        if insertions > 0 { parts.append("+\(insertions)") }
        if deletions > 0 { parts.append("−\(deletions)") }
        if modifications > 0 { parts.append("~\(modifications)") }
        return parts.joined(separator: "  ")
    }
}
