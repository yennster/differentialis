import Foundation

/// One step in an alignment produced by the Myers diff algorithm.
enum Edit: Equatable {
    case equal(Int, Int)   // a[aIndex] aligns with b[bIndex]
    case delete(Int)       // a[aIndex] removed
    case insert(Int)       // b[bIndex] added
}

/// Upper bound on the edit distance the core algorithm will explore before giving up and
/// emitting the remaining span as a block replacement. The backtrace stores one diagonal band
/// per step, so peak memory is ~`budget²` ints — this cap keeps that under a few hundred MB even
/// for pathological (large, wholly dissimilar) inputs, which would otherwise grow without bound
/// and OOM-kill the app. Common-prefix/suffix trimming means realistic edits stay far below it.
private let myersMaxEditDistance = 4096

/// Myers' O(ND) shortest-edit-script diff over any `Equatable` element.
/// Used for both line-level and character-level diffing.
///
/// Two guards keep it safe on large or wholly-dissimilar inputs (see `myersMaxEditDistance`):
/// common prefix/suffix are trimmed before the search, and the search abandons once the edit
/// distance exceeds the budget, degrading to a valid (if non-minimal) block-replace diff.
func myersDiff<T: Equatable>(_ a: [T], _ b: [T]) -> [Edit] {
    let aN = a.count
    let bN = b.count
    if aN == 0 && bN == 0 { return [] }

    // Trim the common prefix and suffix; they align 1:1 and shrink the search dramatically for
    // the typical case of two mostly-similar files.
    var lo = 0
    while lo < aN && lo < bN && a[lo] == b[lo] { lo += 1 }
    var aHi = aN
    var bHi = bN
    while aHi > lo && bHi > lo && a[aHi - 1] == b[bHi - 1] { aHi -= 1; bHi -= 1 }

    var edits: [Edit] = []
    edits.reserveCapacity((aN - (aHi - lo)) + (bN - (bHi - lo)))
    for i in 0..<lo { edits.append(.equal(i, i)) }

    myersCore(a, b, aLo: lo, aHi: aHi, bLo: lo, bHi: bHi, into: &edits)

    let suffix = aN - aHi   // == bN - bHi
    for i in 0..<suffix { edits.append(.equal(aHi + i, bHi + i)) }
    return edits
}

/// Runs the Myers middle-snake search over the sub-ranges `a[aLo..<aHi]` / `b[bLo..<bHi]`,
/// appending edits (in original-index space) to `edits`.
private func myersCore<T: Equatable>(_ a: [T], _ b: [T],
                                     aLo: Int, aHi: Int, bLo: Int, bHi: Int,
                                     into edits: inout [Edit]) {
    let n = aHi - aLo
    let m = bHi - bLo
    if n == 0 && m == 0 { return }
    if n == 0 { for j in 0..<m { edits.append(.insert(bLo + j)) }; return }
    if m == 0 { for i in 0..<n { edits.append(.delete(aLo + i)) }; return }

    let maxD = n + m
    let budget = min(maxD, myersMaxEditDistance)
    let offset = maxD
    var v = [Int](repeating: 0, count: 2 * maxD + 1)
    // Store only the active diagonal band [-d, d] per step, not the whole `v` — bounds memory to
    // ~budget² instead of O((n+m)·budget).
    var trace: [[Int]] = []
    trace.reserveCapacity(budget + 1)

    var reached = false
    outer: for d in 0...budget {
        trace.append(Array(v[(offset - d)...(offset + d)]))
        for k in stride(from: -d, through: d, by: 2) {
            var x: Int
            if k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]) {
                x = v[offset + k + 1]          // move down  → insertion
            } else {
                x = v[offset + k - 1] + 1      // move right → deletion
            }
            var y = x - k
            while x < n && y < m && a[aLo + x] == b[bLo + y] { x += 1; y += 1 }
            v[offset + k] = x
            if x >= n && y >= m { reached = true; break outer }
        }
    }

    guard reached else {
        // Edit distance exceeded the budget: the two ranges are too dissimilar to diff cheaply.
        // Emit a valid block replacement (delete all of A, insert all of B) rather than hang.
        for i in 0..<n { edits.append(.delete(aLo + i)) }
        for j in 0..<m { edits.append(.insert(bLo + j)) }
        return
    }

    // Backtrack over the stored bands. Each band `trace[d]` holds v[offset-d ... offset+d] as it
    // was at the top of step d, so v[offset+k] == band[k + d]; out-of-band diagonals read as 0,
    // matching the untouched `v` in the classic full-array formulation.
    var local: [Edit] = []
    var x = n
    var y = m
    for d in stride(from: trace.count - 1, through: 0, by: -1) {
        let band = trace[d]
        func bandVal(_ kk: Int) -> Int {
            let idx = kk + d
            return (idx >= 0 && idx < band.count) ? band[idx] : 0
        }
        let k = x - y
        let prevK: Int
        if k == -d || (k != d && bandVal(k - 1) < bandVal(k + 1)) {
            prevK = k + 1
        } else {
            prevK = k - 1
        }
        let prevX = bandVal(prevK)
        let prevY = prevX - prevK

        while x > prevX && y > prevY {
            local.append(.equal(aLo + x - 1, bLo + y - 1))
            x -= 1
            y -= 1
        }
        if d > 0 {
            if x == prevX {
                local.append(.insert(bLo + y - 1))
                y -= 1
            } else {
                local.append(.delete(aLo + x - 1))
                x -= 1
            }
        }
    }
    edits.append(contentsOf: local.reversed())
}
