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

struct TextLineStyle: Hashable {
    var ending: String
    var finalNewline: Bool

    var label: String {
        let name: String
        switch ending {
        case "\r\n": name = "CRLF"
        case "\r": name = "CR"
        default: name = "LF"
        }
        return "\(name) · \(finalNewline ? "final newline" : "no final newline")"
    }
}

struct MergeLineStyleDecision: Hashable {
    var selected: TextLineStyle
    var base: TextLineStyle
    var left: TextLineStyle
    var right: TextLineStyle
    var hasConflict: Bool
}

enum ThreeWayMerge {
    /// One contiguous edit expressed in the common ancestor's coordinate space.
    private struct BaseChange: Hashable {
        var range: Range<Int>
        var replacement: [String]
    }

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
            } else if let compatible = compatibleHunks(base: baseSlice, left: leftSlice, right: rightSlice) {
                // There was no common stable anchor inside this region, but the edits themselves
                // touch disjoint base ranges (or are exactly the same). Apply both rather than
                // turning adjacent independent edits into a false conflict.
                hunks.append(contentsOf: compatible)
                return
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

    /// The merged output. `lineEnding` and `finalNewline` let callers reproduce the source file's
    /// exact terminator style instead of always emitting LF with no trailing newline (which
    /// rewrites every line of a CRLF file and drops the final newline). Unresolved conflicts are
    /// written as standard git-style `<<<<<<< / ======= / >>>>>>>` markers so nothing is silently
    /// dropped; pass `markConflicts: false` only when conflicts are known to be resolved.
    static func mergedText(_ hunks: [MergeHunk],
                           lineEnding: String = "\n",
                           finalNewline: Bool = false,
                           markConflicts: Bool = true) -> String {
        var lines: [String] = []
        for hunk in hunks {
            if markConflicts, hunk.isConflict, !hunk.resolved {
                lines.append("<<<<<<< left")
                lines.append(contentsOf: hunk.leftLines)
                lines.append("=======")
                lines.append(contentsOf: hunk.rightLines)
                lines.append(">>>>>>> right")
            } else {
                lines.append(contentsOf: hunk.chosen)
            }
        }
        let body = lines.joined(separator: lineEnding)
        // `lines == [""]` represents a file containing exactly one newline. Its joined body is
        // empty, but it still needs the terminator. An actually empty merge has no lines at all.
        return finalNewline && !lines.isEmpty ? body + lineEnding : body
    }

    static func conflictCount(_ hunks: [MergeHunk]) -> Int {
        hunks.filter { $0.isConflict && !$0.resolved }.count
    }

    /// The dominant line terminator of `text` and whether it ends with a newline, so merged output
    /// can round-trip the original file's style.
    static func lineStyle(of text: String) -> TextLineStyle {
        var crlfCount = 0
        var crCount = 0
        var lfCount = 0
        var pendingCR = false

        // Count terminators without counting the LF half of CRLF twice. Streaming the scalars keeps
        // this bounded for large files and also handles Swift's single-Character CRLF grapheme.
        for scalar in text.unicodeScalars {
            if pendingCR {
                if scalar.value == 0x0A {
                    crlfCount += 1
                    pendingCR = false
                    continue
                }
                crCount += 1
                pendingCR = false
            }
            if scalar.value == 0x0D {
                pendingCR = true
            } else if scalar.value == 0x0A {
                lfCount += 1
            }
        }
        if pendingCR { crCount += 1 }

        let dominant = max(crlfCount, crCount, lfCount)
        let ending: String
        if dominant == 0 { ending = "\n" }
        else if crlfCount == dominant { ending = "\r\n" }
        else if crCount == dominant { ending = "\r" }
        else { ending = "\n" }
        // Check unicode scalars, not graphemes: Swift treats "\r\n" as one Character, so
        // hasSuffix("\n") is false on a CRLF file even though it ends with a newline.
        let last = text.unicodeScalars.last
        let finalNewline = last == "\n" || last == "\r"
        return TextLineStyle(ending: ending, finalNewline: finalNewline)
    }

    /// Merge the file-wide line-ending style with the same three-way rules as content. A style
    /// changed on only one side wins; matching changes deduplicate. When both sides choose
    /// different styles, keep the left style as a preview but require an explicit UI resolution.
    static func lineStyleDecision(base: String, left: String, right: String) -> MergeLineStyleDecision {
        let baseStyle = lineStyle(of: base)
        let leftStyle = lineStyle(of: left)
        let rightStyle = lineStyle(of: right)

        let selected: TextLineStyle
        let conflict: Bool
        if leftStyle == rightStyle {
            selected = leftStyle
            conflict = false
        } else if leftStyle == baseStyle {
            selected = rightStyle
            conflict = false
        } else if rightStyle == baseStyle {
            selected = leftStyle
            conflict = false
        } else {
            selected = leftStyle
            conflict = true
        }
        return MergeLineStyleDecision(selected: selected, base: baseStyle,
                                      left: leftStyle, right: rightStyle,
                                      hasConflict: conflict)
    }

    /// If both sides' edits are compatible, return independently resolved hunks; otherwise return
    /// nil. Empty ranges are insertions. An insertion exactly at an edited range's boundary is
    /// independent, while one inside that range overlaps it.
    private static func compatibleHunks(base: [String], left: [String], right: [String]) -> [MergeHunk]? {
        let leftChanges = changes(from: base, to: left)
        let rightChanges = changes(from: base, to: right)

        // Changes on either individual side are ordered and non-overlapping, so a two-pointer scan
        // is enough to find every cross-side overlap without a quadratic all-pairs comparison.
        var li = 0
        var ri = 0
        while li < leftChanges.count && ri < rightChanges.count {
            let l = leftChanges[li]
            let r = rightChanges[ri]
            if overlaps(l.range, r.range) {
                guard l == r else { return nil }
                li += 1
                ri += 1
            } else if l.range.upperBound <= r.range.lowerBound {
                li += 1
            } else if r.range.upperBound <= l.range.lowerBound {
                ri += 1
            } else {
                // Defensive fallback: every non-overlap should have a strict ordering above.
                return nil
            }
        }

        var all = leftChanges.map { ($0, MergeResolution.takeLeft) }
        var indices = Dictionary(uniqueKeysWithValues: leftChanges.enumerated().map { ($1, $0) })
        for change in rightChanges {
            if let index = indices[change] {
                all[index].1 = .takeBoth
            } else {
                indices[change] = all.count
                all.append((change, .takeRight))
            }
        }
        all.sort {
            if $0.0.range.lowerBound != $1.0.range.lowerBound {
                return $0.0.range.lowerBound < $1.0.range.lowerBound
            }
            if $0.0.range.isEmpty != $1.0.range.isEmpty {
                return $0.0.range.isEmpty   // insertion before an edit starting at the same boundary
            }
            return $0.0.range.upperBound < $1.0.range.upperBound
        }

        var hunks: [MergeHunk] = []
        var cursor = 0
        for (change, resolution) in all {
            guard change.range.lowerBound >= cursor else { return nil }
            if cursor < change.range.lowerBound {
                let stable = Array(base[cursor..<change.range.lowerBound])
                hunks.append(MergeHunk(resolution: .unchanged,
                                       baseLines: stable, leftLines: stable, rightLines: stable,
                                       chosen: stable, resolved: true))
            }

            let original = Array(base[change.range])
            let leftLines = resolution == .takeRight ? original : change.replacement
            let rightLines = resolution == .takeLeft ? original : change.replacement
            hunks.append(MergeHunk(resolution: resolution,
                                   baseLines: original, leftLines: leftLines, rightLines: rightLines,
                                   chosen: change.replacement, resolved: true))
            cursor = change.range.upperBound
        }
        if cursor < base.count {
            let stable = Array(base[cursor..<base.count])
            hunks.append(MergeHunk(resolution: .unchanged,
                                   baseLines: stable, leftLines: stable, rightLines: stable,
                                   chosen: stable, resolved: true))
        }
        return hunks
    }

    /// Convert a Myers edit script into replacement ranges in base coordinates.
    private static func changes(from base: [String], to edited: [String]) -> [BaseChange] {
        var result: [BaseChange] = []
        var baseCursor = 0
        var editedCursor = 0
        var changeBaseStart: Int?
        var changeEditedStart: Int?

        func beginChange() {
            guard changeBaseStart == nil else { return }
            changeBaseStart = baseCursor
            changeEditedStart = editedCursor
        }

        func flushChange() {
            guard let baseStart = changeBaseStart, let editedStart = changeEditedStart else { return }
            let range = baseStart..<baseCursor
            let replacement = Array(edited[editedStart..<editedCursor])
            if range.count == replacement.count, range.count > 1 {
                // Myers has no stable anchor inside a run where every adjacent line changed, so it
                // reports the whole run as one replacement. Split same-length replacements into
                // line-sized edits; this lets a change shared by both sides coexist with an
                // additional adjacent change made on only one side.
                for offset in 0..<range.count {
                    let index = range.lowerBound + offset
                    guard base[index] != replacement[offset] else { continue }
                    result.append(BaseChange(range: index..<(index + 1),
                                             replacement: [replacement[offset]]))
                }
            } else {
                result.append(BaseChange(range: range, replacement: replacement))
            }
            changeBaseStart = nil
            changeEditedStart = nil
        }

        for edit in myersDiff(base, edited) {
            switch edit {
            case let .equal(baseIndex, editedIndex):
                flushChange()
                baseCursor = baseIndex + 1
                editedCursor = editedIndex + 1
            case let .delete(baseIndex):
                beginChange()
                baseCursor = baseIndex + 1
            case let .insert(editedIndex):
                beginChange()
                editedCursor = editedIndex + 1
            }
        }
        flushChange()
        return result
    }

    private static func overlaps(_ a: Range<Int>, _ b: Range<Int>) -> Bool {
        if a.isEmpty && b.isEmpty { return a.lowerBound == b.lowerBound }
        if a.isEmpty { return a.lowerBound > b.lowerBound && a.lowerBound < b.upperBound }
        if b.isEmpty { return b.lowerBound > a.lowerBound && b.lowerBound < a.upperBound }
        return a.lowerBound < b.upperBound && b.lowerBound < a.upperBound
    }

    private static func equalMatches(_ edits: [Edit]) -> [Int: Int] {
        var map: [Int: Int] = [:]
        for case let .equal(i, j) in edits { map[i] = j }
        return map
    }
}
