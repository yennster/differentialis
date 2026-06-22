import Foundation

enum MergeResolution: String, Hashable {
    case unchanged
    case takeLeft
    case takeRight
    case takeBoth      // left and right made the same change
    case conflict
}

/// A contiguous region of a three-way merge.
struct MergeHunk: Identifiable, Hashable {
    let id = UUID()
    var resolution: MergeResolution
    var baseLines: [String]
    var leftLines: [String]
    var rightLines: [String]
    /// The resolved output lines (editable in the UI).
    var chosen: [String]
    /// Whether a conflict has been resolved by the user.
    var resolved: Bool

    var isConflict: Bool { resolution == .conflict }
    var isChange: Bool { resolution != .unchanged }
}

enum ThreeWayMerge {
    /// Produce merge hunks from a common ancestor (`base`) and two edited versions.
    static func merge(base: String, left: String, right: String) -> [MergeHunk] {
        let b = LineDiff.split(base)
        let l = LineDiff.split(left)
        let r = LineDiff.split(right)

        let leftMatch = equalMatches(myersDiff(b, l))
        let rightMatch = equalMatches(myersDiff(b, r))
        let stable = Set(leftMatch.keys).intersection(rightMatch.keys).sorted()

        var hunks: [MergeHunk] = []
        var unchanged: [String] = []
        var prevB = -1, prevL = -1, prevR = -1

        func flushUnchanged() {
            guard !unchanged.isEmpty else { return }
            hunks.append(MergeHunk(resolution: .unchanged,
                                   baseLines: unchanged, leftLines: unchanged, rightLines: unchanged,
                                   chosen: unchanged, resolved: true))
            unchanged = []
        }

        func classify(_ baseSlice: [String], _ leftSlice: [String], _ rightSlice: [String]) {
            if baseSlice.isEmpty && leftSlice.isEmpty && rightSlice.isEmpty { return }
            flushUnchanged()
            let leftChanged = leftSlice != baseSlice
            let rightChanged = rightSlice != baseSlice
            let resolution: MergeResolution
            let chosen: [String]
            var resolved = true
            if !leftChanged && !rightChanged {
                resolution = .unchanged; chosen = baseSlice
            } else if leftChanged && !rightChanged {
                resolution = .takeLeft; chosen = leftSlice
            } else if !leftChanged && rightChanged {
                resolution = .takeRight; chosen = rightSlice
            } else if leftSlice == rightSlice {
                resolution = .takeBoth; chosen = leftSlice
            } else {
                resolution = .conflict; chosen = leftSlice; resolved = false
            }
            hunks.append(MergeHunk(resolution: resolution,
                                   baseLines: baseSlice, leftLines: leftSlice, rightLines: rightSlice,
                                   chosen: chosen, resolved: resolved))
        }

        for sb in stable {
            let sl = leftMatch[sb]!
            let sr = rightMatch[sb]!
            classify(Array(b[(prevB + 1)..<sb]),
                     Array(l[(prevL + 1)..<sl]),
                     Array(r[(prevR + 1)..<sr]))
            unchanged.append(b[sb])
            prevB = sb; prevL = sl; prevR = sr
        }
        classify(Array(b[(prevB + 1)..<b.count]),
                 Array(l[(prevL + 1)..<l.count]),
                 Array(r[(prevR + 1)..<r.count]))
        flushUnchanged()
        return hunks
    }

    static func mergedText(_ hunks: [MergeHunk]) -> String {
        hunks.flatMap(\.chosen).joined(separator: "\n")
    }

    static func conflictCount(_ hunks: [MergeHunk]) -> Int {
        hunks.filter { $0.isConflict && !$0.resolved }.count
    }

    private static func equalMatches(_ edits: [Edit]) -> [Int: Int] {
        var map: [Int: Int] = [:]
        for case let .equal(i, j) in edits { map[i] = j }
        return map
    }
}
