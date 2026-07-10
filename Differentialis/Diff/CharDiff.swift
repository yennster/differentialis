import Foundation

enum CharDiff {
    /// Lines longer than this skip character-level diffing: the intra-line highlight isn't
    /// legible on very long lines and the quadratic-in-edit-distance search isn't worth it.
    static let maxLineLength = 2_000
}

/// Result of an intra-line character diff: the changed character-offset ranges on each side plus
/// a rough similarity ratio, all computed from a single Myers pass.
struct CharDiffResult {
    var left: [Range<Int>]
    var right: [Range<Int>]
    var similarity: Double   // in [0, 1]
}

/// Character-level intra-line diff. Runs Myers once and derives both the highlight ranges and the
/// similarity ratio from it (they used to be two separate diffs over the same input).
func charDiff(_ a: String, _ b: String) -> CharDiffResult {
    let aChars = Array(a)
    let bChars = Array(b)

    // Long lines: skip the char diff and estimate similarity from shared prefix/suffix length so
    // the "modified vs replaced" decision still works without highlighting.
    if max(aChars.count, bChars.count) > CharDiff.maxLineLength {
        return CharDiffResult(left: [], right: [], similarity: cheapSimilarity(aChars, bChars))
    }

    let edits = myersDiff(aChars, bChars)
    var left: [Range<Int>] = []
    var right: [Range<Int>] = []
    var equal = 0
    for edit in edits {
        switch edit {
        case .equal: equal += 1
        case .delete(let i): append(&left, index: i)
        case .insert(let j): append(&right, index: j)
        }
    }
    let total = max(aChars.count, bChars.count)
    let similarity = total == 0 ? 1 : Double(equal) / Double(total)
    return CharDiffResult(left: left, right: right, similarity: similarity)
}

/// Backwards-compatible wrapper returning just the highlight ranges.
func charHighlights(_ a: String, _ b: String) -> (left: [Range<Int>], right: [Range<Int>]) {
    let result = charDiff(a, b)
    return (result.left, result.right)
}

/// Rough similarity ratio in [0, 1] based on shared characters.
func similarity(_ a: String, _ b: String) -> Double {
    charDiff(a, b).similarity
}

/// Cheap similarity estimate for lines too long to diff: common prefix + suffix over max length.
private func cheapSimilarity(_ a: [Character], _ b: [Character]) -> Double {
    if a.isEmpty && b.isEmpty { return 1 }
    let n = a.count, m = b.count
    var prefix = 0
    while prefix < n && prefix < m && a[prefix] == b[prefix] { prefix += 1 }
    var suffix = 0
    while suffix < (n - prefix) && suffix < (m - prefix) && a[n - 1 - suffix] == b[m - 1 - suffix] { suffix += 1 }
    let shared = prefix + suffix
    let total = max(n, m)
    return total == 0 ? 1 : Double(shared) / Double(total)
}

/// Append a single index to a list of ranges, merging into the previous range when contiguous.
private func append(_ ranges: inout [Range<Int>], index: Int) {
    if let last = ranges.last, last.upperBound == index {
        ranges[ranges.count - 1] = last.lowerBound..<(index + 1)
    } else {
        ranges.append(index..<(index + 1))
    }
}
