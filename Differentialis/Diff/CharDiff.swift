import Foundation

/// Character-level intra-line diff. Returns the changed character-offset ranges on
/// each side, used to highlight exactly what differs within a modified line pair.
func charHighlights(_ a: String, _ b: String) -> (left: [Range<Int>], right: [Range<Int>]) {
    let aChars = Array(a)
    let bChars = Array(b)
    let edits = myersDiff(aChars, bChars)

    var left: [Range<Int>] = []
    var right: [Range<Int>] = []

    for edit in edits {
        switch edit {
        case .equal:
            continue
        case .delete(let i):
            append(&left, index: i)
        case .insert(let j):
            append(&right, index: j)
        }
    }
    return (left, right)
}

/// Append a single index to a list of ranges, merging into the previous range when contiguous.
private func append(_ ranges: inout [Range<Int>], index: Int) {
    if let last = ranges.last, last.upperBound == index {
        ranges[ranges.count - 1] = last.lowerBound..<(index + 1)
    } else {
        ranges.append(index..<(index + 1))
    }
}

/// Rough similarity ratio in [0, 1] based on shared characters — used to decide
/// whether two lines are similar enough to show as a highlighted "modified" pair.
func similarity(_ a: String, _ b: String) -> Double {
    if a.isEmpty && b.isEmpty { return 1 }
    let aChars = Array(a)
    let bChars = Array(b)
    let edits = myersDiff(aChars, bChars)
    let equal = edits.reduce(0) { $0 + (isEqual($1) ? 1 : 0) }
    let total = max(aChars.count, bChars.count)
    return total == 0 ? 1 : Double(equal) / Double(total)
}

private func isEqual(_ edit: Edit) -> Bool {
    if case .equal = edit { return true }
    return false
}
