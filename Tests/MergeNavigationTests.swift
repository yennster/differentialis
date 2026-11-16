import Testing
import Foundation
@testable import Differentialis

@Suite("Merge navigation")
struct MergeNavigationTests {
    private typealias Stop = MergeNavigation.Stop

    private func context() -> Stop { Stop(id: UUID(), unresolvedConflict: false, changed: false) }
    private func change() -> Stop { Stop(id: UUID(), unresolvedConflict: false, changed: true) }
    private func conflict() -> Stop { Stop(id: UUID(), unresolvedConflict: true, changed: true) }

    @Test("next and previous step through unresolved conflicts only, wrapping at both ends")
    func cyclesConflicts() {
        let stops = [context(), conflict(), change(), conflict(), context(), conflict()]
        let c = [stops[1].id, stops[3].id, stops[5].id]

        #expect(MergeNavigation.target(from: nil, delta: 1, in: stops) == c[0])
        #expect(MergeNavigation.target(from: c[0], delta: 1, in: stops) == c[1])
        #expect(MergeNavigation.target(from: c[1], delta: 1, in: stops) == c[2])
        #expect(MergeNavigation.target(from: c[2], delta: 1, in: stops) == c[0])

        #expect(MergeNavigation.target(from: nil, delta: -1, in: stops) == c[2])
        #expect(MergeNavigation.target(from: c[0], delta: -1, in: stops) == c[2])
        #expect(MergeNavigation.target(from: c[2], delta: -1, in: stops) == c[1])
    }

    @Test("a single conflict is its own next and previous")
    func singleConflict() {
        let stops = [change(), conflict(), change()]
        #expect(MergeNavigation.target(from: stops[1].id, delta: 1, in: stops) == stops[1].id)
        #expect(MergeNavigation.target(from: stops[1].id, delta: -1, in: stops) == stops[1].id)
    }

    @Test("with no conflicts, navigation falls back to every changed region")
    func fallsBackToChanges() {
        let stops = [context(), change(), context(), change(), change()]
        #expect(MergeNavigation.target(from: nil, delta: 1, in: stops) == stops[1].id)
        #expect(MergeNavigation.target(from: stops[1].id, delta: 1, in: stops) == stops[3].id)
        #expect(MergeNavigation.target(from: stops[4].id, delta: 1, in: stops) == stops[1].id)
        #expect(MergeNavigation.target(from: stops[1].id, delta: -1, in: stops) == stops[4].id)
    }

    @Test("once every conflict is resolved, the resolved hunks are ordinary changes")
    func allResolved() {
        // A resolved conflict is still a changed region, just no longer a conflict stop.
        let stops = [change(), context(), change()]
        #expect(MergeNavigation.firstUnresolvedConflict(in: stops) == nil)
        #expect(MergeNavigation.target(from: stops[0].id, delta: 1, in: stops) == stops[2].id)
    }

    @Test("nothing to navigate when the merge is all context")
    func noChanges() {
        let stops = [context(), context()]
        #expect(MergeNavigation.target(from: nil, delta: 1, in: stops) == nil)
        #expect(MergeNavigation.target(from: nil, delta: -1, in: []) == nil)
        #expect(MergeNavigation.firstUnresolvedConflict(in: stops) == nil)
    }

    @Test("after resolving the current conflict, next continues from where it was")
    func continuesAfterResolving() {
        // The user was on stops[3] and resolved it, so it is now a plain change.
        let stops = [conflict(), change(), conflict(), change(), conflict()]
        let resolved = stops[3].id
        #expect(MergeNavigation.target(from: resolved, delta: 1, in: stops) == stops[4].id)
        #expect(MergeNavigation.target(from: resolved, delta: -1, in: stops) == stops[2].id)

        // Resolving the last conflict in the list wraps forward to the first.
        let last = [conflict(), change(), change()]
        #expect(MergeNavigation.target(from: last[2].id, delta: 1, in: last) == last[0].id)
        #expect(MergeNavigation.target(from: last[0].id, delta: -1, in: last) == last[0].id)
    }

    @Test("an id that is no longer listed (after a reload) starts from the ends")
    func staleCurrent() {
        let stops = [conflict(), change(), conflict()]
        #expect(MergeNavigation.target(from: UUID(), delta: 1, in: stops) == stops[0].id)
        #expect(MergeNavigation.target(from: UUID(), delta: -1, in: stops) == stops[2].id)
    }

    @Test("the first unresolved conflict is the earliest in display order")
    func firstConflict() {
        let stops = [change(), conflict(), conflict()]
        #expect(MergeNavigation.firstUnresolvedConflict(in: stops) == stops[1].id)
    }

    @Test("stops list the line-ending choice first, then hunks by their real state")
    @MainActor
    func stopsFromSession() async throws {
        let session = MergeSession(base: .text(content: "a\nshared\nz", name: "base"),
                                   left: .text(content: "a1\nshared\nz", name: "left"),
                                   right: .text(content: "a2\nshared\nz2", name: "right"))
        await session.load()
        let lineStyleID = UUID()

        let stops = MergeNavigation.stops(hunks: session.hunks, lineStyleConflict: true,
                                          lineStyleID: lineStyleID)
        #expect(stops.count == session.hunks.count + 1)
        #expect(stops.first == Stop(id: lineStyleID, unresolvedConflict: true, changed: true))
        #expect(MergeNavigation.firstUnresolvedConflict(in: stops) == lineStyleID)

        let plain = MergeNavigation.stops(hunks: session.hunks, lineStyleConflict: false,
                                          lineStyleID: lineStyleID)
        let conflictHunk = session.hunks.first { $0.isConflict }
        #expect(MergeNavigation.firstUnresolvedConflict(in: plain) == conflictHunk?.id)
        #expect(plain.contains { $0.changed && !$0.unresolvedConflict })  // the right-only edit to z
        #expect(plain.contains { !$0.changed })                             // the shared context

        let id = try #require(conflictHunk?.id)
        session.resolve(hunk: id, as: .takeLeft)
        let after = MergeNavigation.stops(hunks: session.hunks, lineStyleConflict: false,
                                          lineStyleID: lineStyleID)
        #expect(MergeNavigation.firstUnresolvedConflict(in: after) == nil)
        #expect(after.first { $0.id == id }?.changed == true)
    }
}
