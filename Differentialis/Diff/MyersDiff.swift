import Foundation

/// One step in an alignment produced by the Myers diff algorithm.
enum Edit: Equatable {
    case equal(Int, Int)   // a[aIndex] aligns with b[bIndex]
    case delete(Int)       // a[aIndex] removed
    case insert(Int)       // b[bIndex] added
}

/// Myers' O(ND) shortest-edit-script diff over any `Equatable` element.
/// Used for both line-level and character-level diffing.
func myersDiff<T: Equatable>(_ a: [T], _ b: [T]) -> [Edit] {
    let n = a.count
    let m = b.count
    if n == 0 && m == 0 { return [] }

    let maxD = n + m
    let offset = maxD
    var v = [Int](repeating: 0, count: 2 * maxD + 1)
    var trace: [[Int]] = []

    outer: for d in 0...maxD {
        trace.append(v)
        for k in stride(from: -d, through: d, by: 2) {
            var x: Int
            if k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]) {
                x = v[offset + k + 1]          // move down  → insertion
            } else {
                x = v[offset + k - 1] + 1      // move right → deletion
            }
            var y = x - k
            while x < n && y < m && a[x] == b[y] { x += 1; y += 1 }
            v[offset + k] = x
            if x >= n && y >= m { break outer }
        }
    }

    var edits: [Edit] = []
    var x = n
    var y = m
    for d in stride(from: trace.count - 1, through: 0, by: -1) {
        let v = trace[d]
        let k = x - y
        let prevK: Int
        if k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]) {
            prevK = k + 1
        } else {
            prevK = k - 1
        }
        let prevX = v[offset + prevK]
        let prevY = prevX - prevK

        while x > prevX && y > prevY {
            edits.append(.equal(x - 1, y - 1))
            x -= 1
            y -= 1
        }
        if d > 0 {
            if x == prevX {
                edits.append(.insert(y - 1))
                y -= 1
            } else {
                edits.append(.delete(x - 1))
                x -= 1
            }
        }
    }

    return edits.reversed()
}
