import Foundation

/// Next / Previous Change in a three-way merge. Pure so the wraparound and fallback rules can be
/// tested without a view.
///
/// Unresolved conflicts are the stops while any remain. Once every conflict is resolved, the stops
/// fall back to every changed region, so the shortcuts still step through what the merge did.
enum MergeNavigation {
    /// One navigable region of the Review list, in display order.
    struct Stop: Equatable {
        let id: UUID
        /// A conflict (content or line style) that still needs a choice.
        let unresolvedConflict: Bool
        /// Anything that differs from plain context: a change, a conflict, or a resolved conflict.
        let changed: Bool
    }

    /// The stops `MergeView` lists for a session: the line-style choice first (it renders above
    /// the hunks), then every hunk in order.
    static func stops(hunks: [MergeHunk], lineStyleConflict: Bool, lineStyleID: UUID) -> [Stop] {
        var stops: [Stop] = []
        if lineStyleConflict {
            stops.append(Stop(id: lineStyleID, unresolvedConflict: true, changed: true))
        }
        for hunk in hunks {
            stops.append(Stop(id: hunk.id,
                              unresolvedConflict: hunk.isConflict && !hunk.resolved,
                              changed: hunk.isChange))
        }
        return stops
    }

    /// The stop to move to from `current`, `delta` steps forward (positive) or back (negative),
    /// wrapping at either end. Returns nil when there is nowhere to go.
    ///
    /// `current` need not be a stop itself: after the user resolves the conflict they were on, it
    /// drops out of the conflict stops, and moving on should continue from where it sat in the
    /// list rather than restart from the top. An unknown `current` (nil, or gone after a reload)
    /// starts from the first stop going forward or the last going back.
    static func target(from current: UUID?, delta: Int, in stops: [Stop]) -> UUID? {
        guard delta != 0 else { return current }
        let conflicts = stops.indices.filter { stops[$0].unresolvedConflict }
        let candidates = conflicts.isEmpty ? stops.indices.filter { stops[$0].changed } : conflicts
        guard !candidates.isEmpty else { return nil }
        let forward = delta > 0
        let steps = abs(delta)

        guard let current, let position = stops.firstIndex(where: { $0.id == current }) else {
            let start = forward ? 0 : candidates.count - 1
            return stops[candidates[wrap(start + (forward ? steps - 1 : -(steps - 1)), candidates.count)]].id
        }

        let index: Int
        if let exact = candidates.firstIndex(of: position) {
            index = exact + delta
        } else if forward {
            // The first candidate after the current position counts as one step.
            let after = candidates.firstIndex { $0 > position } ?? candidates.count
            index = after + steps - 1
        } else {
            let before = candidates.lastIndex { $0 < position } ?? -1
            index = before - (steps - 1)
        }
        return stops[candidates[wrap(index, candidates.count)]].id
    }

    /// The first unresolved conflict, for the header's conflict count. Nil when none remain.
    static func firstUnresolvedConflict(in stops: [Stop]) -> UUID? {
        stops.first { $0.unresolvedConflict }?.id
    }

    private static func wrap(_ index: Int, _ count: Int) -> Int {
        ((index % count) + count) % count
    }
}
