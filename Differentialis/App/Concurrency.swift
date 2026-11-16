import Foundation

/// Runs blocking work — git subprocesses (`Process.waitUntilExit`), file I/O, image decoding,
/// large diffs — off the main actor and delivers the result back on the caller's actor.
///
/// None of that work may run on the main thread: it freezes the UI, and worse, `waitUntilExit`
/// pumps the run loop, which re-enters SwiftUI's update cycle and crashes with EXC_BAD_ACCESS.
/// Wrap the blocking call in `await offMain { … }` and assign the result afterwards (back on the
/// main actor) — see RepositoryView / AppModel / TextComparisonView for the pattern.
func offMain<T: Sendable>(_ work: @Sendable @escaping () -> T) async -> T {
    await Task.detached(priority: .userInitiated, operation: work).value
}

/// Carries a value that isn't `Sendable` (e.g. AppKit `NSImage`) across an actor hop. Safe only
/// when the value isn't mutated concurrently — here we just hand a freshly-decoded image back.
struct Unchecked<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// Tracks the newest request for each key, so async work that a newer request (or a cancel)
/// superseded can tell its result is stale and drop it.
struct LatestRequests<Key: Hashable> {
    private var pending: [Key: UUID] = [:]

    func isPending(_ key: Key) -> Bool { pending[key] != nil }

    /// Starts a request for `key`, superseding any earlier one.
    mutating func begin(_ key: Key) -> UUID {
        let request = UUID()
        pending[key] = request
        return request
    }

    /// True when `request` is still the newest for `key`; it is then no longer pending.
    mutating func finish(_ key: Key, _ request: UUID) -> Bool {
        guard pending[key] == request else { return false }
        pending[key] = nil
        return true
    }

    /// Drops the pending request for `key`, so its result is ignored when it finishes.
    mutating func cancel(_ key: Key) { pending[key] = nil }
}
