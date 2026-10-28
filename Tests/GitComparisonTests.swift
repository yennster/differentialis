import Foundation
import Testing
@testable import Differentialis

@Suite("Git comparison layers")
struct GitComparisonTests {
    @Test("all seven porcelain unmerged codes are conflicts")
    func allUnmergedCodes() throws {
        let fixture = try TemporaryGitRepository()
        let codes = ["DD", "AU", "UD", "UA", "DU", "AA", "UU"]
        let output = codes.enumerated().map { pair in
            "\(pair.element) conflict-\(pair.offset).txt\u{0}"
        }.joined()

        let files = fixture.repository.parsePorcelain(output)

        #expect(files.count == codes.count)
        #expect(files.allSatisfy { $0.status == .conflicted })
        #expect(Set(files.map(\.path)).count == codes.count)
    }

    @Test("staged and unstaged comparisons load their actual snapshots")
    func indexAndWorkingTreeSnapshots() throws {
        let fixture = try TemporaryGitRepository()
        try fixture.write("base\n", to: "file.txt")
        try fixture.commitAll("base")
        try fixture.git(["tag", "--no-sign", "baseline"])
        try fixture.write("head\n", to: "file.txt")
        try fixture.commitAll("head")
        try fixture.write("staged\n", to: "file.txt")
        try fixture.git(["add", "--", "file.txt"])
        try fixture.write("working\n", to: "file.txt")

        let staged = try fixture.repository.customChangeset(
            a: .reference("baseline"), b: .workingCopy(.staged))
        #expect(staged.a == .ref("baseline"))
        #expect(staged.b == .index)
        #expect(staged.bLabel == "Index")
        let stagedFile = try #require(staged.files.first)
        let stagedComparison = fixture.repository.makeComparison(
            file: stagedFile,
            a: staged.a, aLabel: staged.aLabel,
            b: staged.b, bLabel: staged.bLabel)
        #expect(try stagedComparison.a.loadText() == "base\n")
        #expect(try stagedComparison.b.loadText() == "staged\n")
        #expect(stagedComparison.b.displayName == "file.txt — Index")
        #expect(stagedComparison.b.subtitle == "Index · file.txt")
        #expect(FilePropertiesBuilder.properties(for: stagedComparison.b)["Size"]?.contains("7 bytes") == true)

        let unstaged = try fixture.repository.customChangeset(
            a: .reference("baseline"), b: .workingCopy(.unstaged))
        #expect(unstaged.a == .index)
        #expect(unstaged.b == .workingCopy)
        #expect(unstaged.aLabel == "Index")
        let unstagedFile = try #require(unstaged.files.first)
        let unstagedComparison = fixture.repository.makeComparison(
            file: unstagedFile,
            a: unstaged.a, aLabel: unstaged.aLabel,
            b: unstaged.b, bLabel: unstaged.bLabel)
        #expect(try unstagedComparison.a.loadText() == "staged\n")
        #expect(try unstagedComparison.b.loadText() == "working\n")

        let all = try fixture.repository.customChangeset(
            a: .reference("baseline"), b: .workingCopy(.all))
        let allFile = try #require(all.files.first { $0.path == "file.txt" })
        let allComparison = fixture.repository.makeComparison(
            file: allFile,
            a: all.a, aLabel: all.aLabel,
            b: all.b, bLabel: all.bLabel)
        // This path changed in both layers, so All Changes exposes the exact layer boundary.
        #expect(try allComparison.a.loadText() == "staged\n")
        #expect(try allComparison.b.loadText() == "working\n")
        #expect(allComparison.a.displayName == "file.txt — Index")
    }

    @Test("all changes preserve staged bytes when the worktree reverts to HEAD")
    func stagedThenReverted() throws {
        let fixture = try TemporaryGitRepository()
        try fixture.write("base\n", to: "tracked.txt")
        try fixture.commitAll("base")
        try fixture.write("staged\n", to: "tracked.txt")
        try fixture.git(["add", "--", "tracked.txt"])
        try fixture.write("base\n", to: "tracked.txt")
        try fixture.write("new\n", to: "untracked.txt")

        #expect(try fixture.repository.workingChanges(scope: .staged).contains {
            $0.path == "tracked.txt"
        })
        #expect(try fixture.repository.workingChanges(scope: .unstaged).contains {
            $0.path == "tracked.txt"
        })

        let all = try fixture.repository.workingChanges(scope: .all)
        let tracked = try #require(all.first { $0.path == "tracked.txt" })
        #expect(all.contains { $0.path == "untracked.txt" && $0.status == .untracked })
        #expect(all.filter { $0.path == "tracked.txt" }.count == 1)
        let comparison = fixture.repository.makeComparison(
            file: tracked, a: .ref("HEAD"), aLabel: "HEAD",
            b: .workingCopy, bLabel: "Working Copy")
        #expect(try comparison.a.loadText() == "staged\n")
        #expect(try comparison.b.loadText() == "base\n")
        #expect(comparison.a.displayName == "tracked.txt — Index")

        let customAll = try fixture.repository.customChangeset(
            a: .reference("HEAD"), b: .workingCopy(.all))
        #expect(customAll.files.contains { $0.path == "tracked.txt" })
        #expect(customAll.files.contains {
            $0.path == "untracked.txt" && $0.status == .untracked
        })
    }

    @Test("all changes coalesce a staged deletion and restored worktree file")
    func stagedDeletionRestored() throws {
        let fixture = try TemporaryGitRepository()
        try fixture.write("base\n", to: "tracked.txt")
        try fixture.commitAll("base")
        try fixture.git(["rm", "--cached", "--quiet", "--", "tracked.txt"])

        let all = try fixture.repository.workingChanges(scope: .all)
        let rows = all.filter { $0.path == "tracked.txt" }
        let file = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(file.status == .untracked)

        let comparison = fixture.repository.makeComparison(
            file: file, a: .ref("HEAD"), aLabel: "HEAD",
            b: .workingCopy, bLabel: "Working Copy")
        #expect(try comparison.a.loadData().isEmpty)
        #expect(try comparison.b.loadText() == "base\n")
        #expect(comparison.a.displayName == "tracked.txt — Index (absent)")
    }

    @Test("unborn HEAD compares the empty tree to index and working tree")
    func unbornHead() throws {
        let fixture = try TemporaryGitRepository()
        #expect(try fixture.repository.commits().isEmpty)
        try fixture.write("index bytes\n", to: "tracked.txt")
        try fixture.git(["add", "--", "tracked.txt"])
        try fixture.write("working bytes\n", to: "tracked.txt")
        try fixture.write("untracked bytes\n", to: "untracked.txt")

        let staged = try fixture.repository.customChangeset(
            a: .reference("HEAD"), b: .workingCopy(.staged))
        let stagedFile = try #require(staged.files.first { $0.path == "tracked.txt" })
        #expect(stagedFile.status == .added)
        let stagedComparison = fixture.repository.makeComparison(
            file: stagedFile,
            a: staged.a, aLabel: staged.aLabel,
            b: staged.b, bLabel: staged.bLabel)
        #expect(try stagedComparison.a.loadData().isEmpty)
        #expect(try stagedComparison.b.loadText() == "index bytes\n")

        let unstaged = try fixture.repository.customChangeset(
            a: .reference("HEAD"), b: .workingCopy(.unstaged))
        let unstagedFile = try #require(unstaged.files.first { $0.path == "tracked.txt" })
        let unstagedComparison = fixture.repository.makeComparison(
            file: unstagedFile,
            a: unstaged.a, aLabel: unstaged.aLabel,
            b: unstaged.b, bLabel: unstaged.bLabel)
        #expect(try unstagedComparison.a.loadText() == "index bytes\n")
        #expect(try unstagedComparison.b.loadText() == "working bytes\n")

        let all = try fixture.repository.workingChanges(scope: .all)
        #expect(all.contains { $0.path == "tracked.txt" && $0.status == .modified })
        #expect(all.contains { $0.path == "untracked.txt" && $0.status == .untracked })

        let customAll = try fixture.repository.customChangeset(
            a: .reference("HEAD"), b: .workingCopy(.all))
        let allFile = try #require(customAll.files.first { $0.path == "tracked.txt" })
        let allComparison = fixture.repository.makeComparison(
            file: allFile,
            a: customAll.a, aLabel: customAll.aLabel,
            b: customAll.b, bLabel: customAll.bLabel)
        #expect(try allComparison.a.loadText() == "index bytes\n")
        #expect(try allComparison.b.loadText() == "working bytes\n")
    }

    @Test("conflicts are one conflicted row in every working scope")
    func conflictNormalization() throws {
        let fixture = try TemporaryGitRepository()
        try fixture.write("base\n", to: "conflict.txt")
        try fixture.commitAll("base")
        let primaryBranch = try fixture.git(["branch", "--show-current"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try fixture.git(["branch", "other"])

        try fixture.write("primary\n", to: "conflict.txt")
        try fixture.commitAll("primary edit")
        try fixture.git(["checkout", "--quiet", "other"])
        try fixture.write("other\n", to: "conflict.txt")
        try fixture.commitAll("other edit")

        do {
            try fixture.git(["merge", "--no-edit", primaryBranch])
            Issue.record("Expected the merge to produce a conflict")
        } catch {
            // A non-zero merge exit is the expected way Git reports an unresolved conflict.
        }

        for scope in WorkingScope.allCases {
            let files = try fixture.repository.workingChanges(scope: scope)
            let conflicts = files.filter { $0.path == "conflict.txt" }
            #expect(conflicts.count == 1, "scope: \(scope)")
            #expect(conflicts.first?.status == .conflicted, "scope: \(scope)")
            let file = try #require(conflicts.first)
            let comparison = fixture.repository.makeComparison(
                file: file, a: .ref("HEAD"), aLabel: "HEAD",
                b: .workingCopy, bLabel: "Working Copy")
            #expect(try comparison.a.loadText() == "other\n", "scope: \(scope)")
            #expect(try comparison.b.loadText() == "primary\n", "scope: \(scope)")
            #expect(comparison.a.displayName == "conflict.txt — Ours")
            #expect(comparison.b.displayName == "conflict.txt — Theirs")
        }
    }

    @Test("add-add conflicts load ours and theirs in every scope")
    func addAddConflictSnapshots() throws {
        let fixture = try TemporaryGitRepository()
        try fixture.write("seed\n", to: "seed.txt")
        try fixture.commitAll("base")
        let primaryBranch = try fixture.git(["branch", "--show-current"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try fixture.git(["branch", "other"])

        try fixture.write("primary addition\n", to: "added.txt")
        try fixture.commitAll("primary add")
        try fixture.git(["checkout", "--quiet", "other"])
        try fixture.write("other addition\n", to: "added.txt")
        try fixture.commitAll("other add")
        do {
            try fixture.git(["merge", "--no-edit", primaryBranch])
            Issue.record("Expected the merge to produce an add/add conflict")
        } catch {}

        for scope in WorkingScope.allCases {
            let file = try #require(try fixture.repository.workingChanges(scope: scope)
                .first { $0.path == "added.txt" && $0.status == .conflicted })
            let comparison = fixture.repository.makeComparison(
                file: file, a: .ref("HEAD"), aLabel: "HEAD",
                b: .workingCopy, bLabel: "Working Copy")
            #expect(try comparison.a.loadText() == "other addition\n", "scope: \(scope)")
            #expect(try comparison.b.loadText() == "primary addition\n", "scope: \(scope)")
        }
    }

    @Test("delete-modify conflicts use an empty missing stage in every scope")
    func deleteModifyConflictSnapshots() throws {
        let fixture = try TemporaryGitRepository()
        try fixture.write("base\n", to: "conflict.txt")
        try fixture.commitAll("base")
        let primaryBranch = try fixture.git(["branch", "--show-current"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try fixture.git(["branch", "other"])

        try fixture.write("primary modification\n", to: "conflict.txt")
        try fixture.commitAll("primary modify")
        try fixture.git(["checkout", "--quiet", "other"])
        try fixture.git(["rm", "--quiet", "--", "conflict.txt"])
        try fixture.git(["commit", "--quiet", "--message", "other delete"])
        do {
            try fixture.git(["merge", "--no-edit", primaryBranch])
            Issue.record("Expected the merge to produce a delete/modify conflict")
        } catch {}

        for scope in WorkingScope.allCases {
            let file = try #require(try fixture.repository.workingChanges(scope: scope)
                .first { $0.path == "conflict.txt" && $0.status == .conflicted })
            let comparison = fixture.repository.makeComparison(
                file: file, a: .ref("HEAD"), aLabel: "HEAD",
                b: .workingCopy, bLabel: "Working Copy")
            #expect(try comparison.a.loadData().isEmpty, "scope: \(scope)")
            #expect(try comparison.b.loadText() == "primary modification\n", "scope: \(scope)")
            #expect(comparison.a.displayName == "conflict.txt — Ours (absent)")
            #expect(comparison.b.displayName == "conflict.txt — Theirs")
        }
    }

    @Test("unborn SHA-256 repositories derive their own empty tree")
    func unbornSHA256() throws {
        let fixture = try TemporaryGitRepository(objectFormat: "sha256")
        #expect(try fixture.repository.commits().isEmpty)
        try fixture.write("staged bytes\n", to: "file.txt")
        try fixture.git(["add", "--", "file.txt"])

        let staged = try fixture.repository.customChangeset(
            a: .reference("HEAD"), b: .workingCopy(.staged))
        let file = try #require(staged.files.first { $0.path == "file.txt" })
        let comparison = fixture.repository.makeComparison(
            file: file, a: staged.a, aLabel: staged.aLabel,
            b: staged.b, bLabel: staged.bLabel)
        #expect(try comparison.a.loadData().isEmpty)
        #expect(try comparison.b.loadText() == "staged bytes\n")
    }

    @Test("option-like refs fail cleanly and never reach git as options")
    func optionLikeRefsRejected() throws {
        let fixture = try TemporaryGitRepository()
        try fixture.write("base\n", to: "file.txt")
        try fixture.commitAll("base")
        let target = fixture.directory.appendingPathComponent("x")
        let injected = "--output=\(target.path)"

        let sides: [(CustomSide, CustomSide)] = [
            (.commit(injected), .reference("HEAD")),
            (.reference("HEAD"), .commit(injected)),
            (.commit(injected), .workingCopy(.staged)),
            (.commit(injected), .workingCopy(.all)),
        ]
        for (a, b) in sides {
            let error = #expect(throws: GitError.self) {
                try fixture.repository.customChangeset(a: a, b: b)
            }
            guard case .unknownRevision(let ref)? = error else {
                Issue.record("Expected unknownRevision, got \(String(describing: error))")
                continue
            }
            #expect(ref == injected)
        }
        #expect(!FileManager.default.fileExists(atPath: target.path))

        // The lower-level entry points pass revisions after --end-of-options, so even an
        // unvalidated caller makes git report a bad revision rather than write the file.
        #expect(throws: GitError.self) { try fixture.repository.changedFiles(from: injected, to: "HEAD") }
        #expect(throws: GitError.self) { try fixture.repository.changedFiles(inCommit: injected) }
        #expect(throws: GitError.self) { try fixture.repository.changedFilesFromReferenceToIndex(injected) }
        #expect(throws: GitError.self) { try fixture.repository.blobData(ref: injected, path: "file.txt") }
        #expect(fixture.repository.parentSHA(of: injected) == nil)
        #expect(!FileManager.default.fileExists(atPath: target.path))

        #expect(CustomSide.commit(injected).hasOptionLikeRef)
        #expect(!CustomSide.reference("main").hasOptionLikeRef)
        #expect(!CustomSide.workingCopy(.all).hasOptionLikeRef)
    }

    @Test("unknown refs report a clean error instead of raw git output")
    func unknownRefRejected() throws {
        let fixture = try TemporaryGitRepository()
        try fixture.write("base\n", to: "file.txt")
        try fixture.commitAll("base")

        let error = #expect(throws: GitError.self) {
            try fixture.repository.customChangeset(a: .commit("deadbeef"), b: .reference("HEAD"))
        }
        #expect(error?.localizedDescription == "Unknown commit or reference “deadbeef”.")

        // HEAD is only exempt from the lookup as a working-copy base; ref↔ref on an unborn HEAD
        // still gets the clean error.
        let unborn = try TemporaryGitRepository()
        let unbornError = #expect(throws: GitError.self) {
            try unborn.repository.customChangeset(a: .reference("HEAD"), b: .reference("HEAD"))
        }
        #expect(unbornError?.localizedDescription == "Unknown commit or reference “HEAD”.")
        #expect(throws: GitError.self) {
            try fixture.repository.customChangeset(a: .commit(""), b: .reference("HEAD"))
        }
    }

    @Test("a branch named like a tracked file still compares")
    func branchNamedLikeFile() throws {
        let fixture = try TemporaryGitRepository()
        try fixture.write("base\n", to: "notes")
        try fixture.commitAll("base")
        try fixture.git(["branch", "notes"])
        try fixture.write("changed\n", to: "notes")
        try fixture.commitAll("changed")

        let commitRange = try fixture.repository.customChangeset(
            a: .reference("notes"), b: .reference("HEAD"))
        #expect(commitRange.files.map(\.path) == ["notes"])

        try fixture.write("working\n", to: "notes")
        try fixture.git(["add", "--", "notes"])
        let staged = try fixture.repository.customChangeset(
            a: .reference("notes"), b: .workingCopy(.staged))
        let file = try #require(staged.files.first { $0.path == "notes" })
        let comparison = fixture.repository.makeComparison(
            file: file, a: staged.a, aLabel: staged.aLabel, b: staged.b, bLabel: staged.bLabel)
        #expect(try comparison.a.loadText() == "base\n")
        #expect(try comparison.b.loadText() == "working\n")
    }
}

private final class TemporaryGitRepository {
    let directory: URL
    let repository: GitRepository

    init(objectFormat: String? = nil) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DifferentialisGitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        repository = GitRepository(url: directory)
        var initArguments = ["init", "--quiet"]
        if let objectFormat { initArguments.append("--object-format=\(objectFormat)") }
        try git(initArguments)
        try git(["config", "user.name", "Differentialis Tests"])
        try git(["config", "user.email", "tests@example.invalid"])
        try git(["config", "commit.gpgSign", "false"])
        try git(["config", "tag.gpgSign", "false"])
        try git(["config", "tag.forceSignAnnotated", "false"])
        try git(["config", "core.autocrlf", "false"])
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func write(_ text: String, to path: String) throws {
        let destination = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: destination)
    }

    @discardableResult
    func git(_ arguments: [String]) throws -> String {
        try repository.run(arguments)
    }

    func commitAll(_ message: String) throws {
        try git(["add", "--all"])
        try git(["commit", "--quiet", "--message", message])
    }
}
