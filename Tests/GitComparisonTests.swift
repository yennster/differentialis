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

    @Test("re-resolving a Working Copy changeset picks up edits, new files, and reverts")
    func workingCopyChangesetRefresh() throws {
        let fixture = try TemporaryGitRepository()
        try fixture.write("a\n", to: "a.txt")
        try fixture.write("b\n", to: "b.txt")
        try fixture.commitAll("base")
        try fixture.write("a changed\n", to: "a.txt")

        let opened = try fixture.repository.customChangeset(
            a: .reference("HEAD"), b: .workingCopy(.all))
        #expect(opened.files.map(\.path) == ["a.txt"])

        try fixture.write("a\n", to: "a.txt")
        try fixture.write("b changed\n", to: "b.txt")
        try fixture.write("new\n", to: "new.txt")
        let refreshed = try fixture.repository.customChangeset(
            a: .reference("HEAD"), b: .workingCopy(.all))
        #expect(Set(refreshed.files.map(\.path)) == ["b.txt", "new.txt"])

        // Staging the new file can change its row's status, and with it the row's ID. The
        // selection follows the path rather than falling back to the first row.
        let selected = try #require(refreshed.files.first { $0.path == "new.txt" })
        try fixture.git(["add", "--", "new.txt"])
        let staged = try fixture.repository.customChangeset(
            a: .reference("HEAD"), b: .workingCopy(.all))
        let stagedRow = try #require(staged.files.first { $0.path == "new.txt" })
        #expect(stagedRow.id != selected.id)
        #expect(GitChangedFile.selection(keeping: selected.id, path: selected.path, in: staged.files)
                == stagedRow.id)
    }

    @Test("a refreshed list keeps the selected row, else its path, else the first row")
    func changesetSelectionAcrossRefresh() {
        let modified = GitChangedFile(path: "src/a.swift", status: .modified)
        let untracked = GitChangedFile(path: "src/new.swift", status: .untracked)
        let added = GitChangedFile(path: "src/new.swift", status: .added)
        let other = GitChangedFile(path: "README.md", status: .modified)

        #expect(GitChangedFile.selection(keeping: modified.id, path: modified.path,
                                         in: [other, modified]) == modified.id)
        #expect(GitChangedFile.selection(keeping: untracked.id, path: untracked.path,
                                         in: [other, added]) == added.id)
        #expect(GitChangedFile.selection(keeping: modified.id, path: modified.path,
                                         in: [other, added]) == other.id)
        #expect(GitChangedFile.selection(keeping: nil, path: nil, in: [added, other]) == added.id)
        #expect(GitChangedFile.selection(keeping: modified.id, path: modified.path, in: []) == nil)
    }

    @Test("only the newest changeset refresh lands, and a close drops it")
    func latestRequestsSupersede() {
        // `finish` is mutating, which `#expect` can't call inside its expansion, so each result
        // is taken first.
        var requests = LatestRequests<String>()
        let first = requests.begin("changeset")
        let second = requests.begin("changeset")
        #expect(requests.isPending("changeset"))
        let firstLanded = requests.finish("changeset", first)
        #expect(!firstLanded)
        #expect(requests.isPending("changeset"))
        let secondLanded = requests.finish("changeset", second)
        #expect(secondLanded)
        #expect(!requests.isPending("changeset"))
        let secondLandedTwice = requests.finish("changeset", second)
        #expect(!secondLandedTwice)

        let closed = requests.begin("changeset")
        let other = requests.begin("other")
        requests.cancel("changeset")
        #expect(!requests.isPending("changeset"))
        let closedLanded = requests.finish("changeset", closed)
        #expect(!closedLanded)
        let otherLanded = requests.finish("other", other)
        #expect(otherLanded)
    }

    @Test("eol=crlf snapshots read as checked out, so HEAD vs Working Copy has no line-ending noise")
    func checkoutLineEndings() throws {
        let fixture = try TemporaryGitRepository()
        try fixture.write("* text eol=crlf\n", to: ".gitattributes")
        try fixture.write("one\r\ntwo\r\n", to: "file.txt")
        try fixture.commitAll("base")
        try fixture.write("one\r\nTWO\r\n", to: "file.txt")

        // Git stores the normalized LF blob; only the read path applies the CRLF conversion.
        let stored = try fixture.repository.rawBlobData(object: "HEAD:file.txt")
        #expect(String(decoding: stored, as: UTF8.self) == "one\ntwo\n")

        let head = ComparisonSource.gitBlob(repo: fixture.directory, ref: "HEAD", path: "file.txt", label: "HEAD")
        let working = ComparisonSource.workingCopy(repo: fixture.directory, path: "file.txt")
        let headText = try head.loadText()
        let workingText = try working.loadText()
        #expect(headText == "one\r\ntwo\r\n")
        #expect(textFormatDifferences(headText, workingText).isEmpty)

        let index = ComparisonSource.gitIndex(repo: fixture.directory, path: "file.txt")
        #expect(try index.loadText() == "one\r\ntwo\r\n")
        #expect(FilePropertiesBuilder.properties(for: head)["Size"]?.contains("10 bytes") == true)
    }

    @Test("smudge filters apply to commit, index, and conflict-stage reads")
    func smudgeFilterApplied() throws {
        let fixture = try TemporaryGitRepository()
        try fixture.git(["config", "filter.upper.smudge", "tr a-z A-Z"])
        try fixture.write("*.up filter=upper\n", to: ".gitattributes")
        try fixture.write("hello\n", to: "greeting.up")
        try fixture.commitAll("base")
        let base = try fixture.git(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(try fixture.repository.rawBlobData(object: "HEAD:greeting.up") == Data("hello\n".utf8))
        #expect(try fixture.repository.blobData(ref: "HEAD", path: "greeting.up") == Data("HELLO\n".utf8))
        #expect(try fixture.repository.blobData(ref: base, path: "greeting.up") == Data("HELLO\n".utf8))
        #expect(try fixture.repository.indexData(path: "greeting.up") == Data("HELLO\n".utf8))

        try fixture.git(["checkout", "--quiet", "-b", "other"])
        try fixture.write("theirs\n", to: "greeting.up")
        try fixture.commitAll("theirs")
        try fixture.git(["checkout", "--quiet", "-"])
        try fixture.write("ours\n", to: "greeting.up")
        try fixture.commitAll("ours")
        #expect(throws: GitError.self) { try fixture.git(["merge", "--quiet", "other"]) }

        #expect(try fixture.repository.blobData(ref: ":2", path: "greeting.up") == Data("OURS\n".utf8))
        #expect(try fixture.repository.blobData(ref: ":3", path: "greeting.up") == Data("THEIRS\n".utf8))
        // An unmerged path still has no single stage-0 snapshot, filtered or not.
        #expect(throws: GitError.self) { try fixture.repository.indexData(path: "greeting.up") }
    }

    @Test("a required filter that cannot run falls back to the stored blob")
    func failingFilterFallsBack() throws {
        let fixture = try TemporaryGitRepository()
        try fixture.write("*.bin filter=broken\n", to: ".gitattributes")
        try fixture.write("stored\n", to: "data.bin")
        try fixture.commitAll("base")
        try fixture.git(["config", "filter.broken.smudge", "differentialis-missing-filter-binary"])
        try fixture.git(["config", "filter.broken.required", "true"])

        #expect(throws: GitError.self) {
            try fixture.git(["cat-file", "--filters", "HEAD:data.bin"])
        }
        #expect(try fixture.repository.blobData(ref: "HEAD", path: "data.bin") == Data("stored\n".utf8))
        #expect(try fixture.repository.indexData(path: "data.bin") == Data("stored\n".utf8))

        // Falling back never turns a missing object into an empty or wrong read.
        #expect(throws: GitError.self) { try fixture.repository.blobData(ref: "HEAD", path: "missing.bin") }
        #expect(throws: GitError.self) { try fixture.repository.indexData(path: "missing.bin") }
    }

    @Test("a non-required filter that fails passes the stored blob through")
    func optionalFilterPassesThrough() throws {
        let fixture = try TemporaryGitRepository()
        try fixture.write("*.txt filter=flaky\n", to: ".gitattributes")
        try fixture.write("stored\n", to: "note.txt")
        try fixture.commitAll("base")
        try fixture.git(["config", "filter.flaky.smudge", "false"])

        #expect(try fixture.repository.blobData(ref: "HEAD", path: "note.txt") == Data("stored\n".utf8))
    }

    @Test("a filter that outlives the timeout falls back to the stored blob promptly")
    func slowFilterTimesOut() throws {
        let fixture = try TemporaryGitRepository()
        try fixture.write("*.txt filter=slow\n", to: ".gitattributes")
        try fixture.write("stored\n", to: "note.txt")
        try fixture.commitAll("base")
        try fixture.git(["config", "filter.slow.smudge", "sleep 20; tr a-z A-Z"])

        let start = Date()
        let data = try fixture.repository.checkoutData(object: "HEAD:note.txt", timeout: 1)
        #expect(data == Data("stored\n".utf8))
        #expect(Date().timeIntervalSince(start) < 10)
    }

    @Test("an LFS pointer above the smudge limit is compared as its pointer")
    func largeLFSPointerIsNotSmudged() throws {
        let fixture = try TemporaryGitRepository()
        let pointer = """
            version https://git-lfs.github.com/spec/v1
            oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
            size \(GitLFSPointer.smudgeLimit + 1)

            """
        // A stand-in filter name: CI machines may have git-lfs configured globally for `lfs`.
        try fixture.write("*.mov filter=fakelfs\n", to: ".gitattributes")
        try fixture.write(pointer, to: "movie.mov")
        try fixture.commitAll("base")
        // Had the read smudged, the bytes would come back uppercased.
        try fixture.git(["config", "filter.fakelfs.smudge", "tr a-z A-Z"])

        let head = ComparisonSource.gitBlob(repo: fixture.directory, ref: "HEAD", path: "movie.mov", label: "HEAD")
        #expect(try head.loadData() == Data(pointer.utf8))
        let size = FilePropertiesBuilder.properties(for: head)["Size"]
        #expect(size?.hasSuffix("in Git LFS") == true)
        #expect(size?.contains((GitLFSPointer.smudgeLimit + 1).formatted()) == true)
    }

    @Test("LFS pointers parse their declared size and reject other text")
    func lfsPointerParsing() {
        let pointer = """
            version https://git-lfs.github.com/spec/v1
            oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
            size 12345

            """
        #expect(GitLFSPointer(data: Data(pointer.utf8))?.size == 12345)
        #expect(GitLFSPointer(data: Data("hello\n".utf8)) == nil)
        #expect(GitLFSPointer(data: Data("version https://git-lfs.github.com/spec/v1\nsize 5\n".utf8)) == nil)
        #expect(GitLFSPointer(data: Data((pointer + String(repeating: "x", count: 2_000)).utf8)) == nil)
    }

    @Test("remote HEAD symrefs are not listed as an extra ref named after the remote")
    func refsSkipRemoteHead() throws {
        let fixture = try TemporaryGitRepository()
        try fixture.write("base\n", to: "file.txt")
        try fixture.commitAll("base")
        try fixture.git(["branch", "-M", "main"])
        try fixture.git(["branch", "feature/HEAD"])

        let remote = fixture.directory.appendingPathComponent("remote.git", isDirectory: true)
        try fixture.git(["init", "--quiet", "--bare", remote.path])
        try fixture.git(["remote", "add", "origin", remote.path])
        try fixture.git(["push", "--quiet", "origin", "main"])
        try fixture.git(["fetch", "--quiet", "origin"])
        try fixture.git(["remote", "set-head", "origin", "main"])
        #expect(try fixture.git(["for-each-ref", "--format=%(refname:short)",
                                 "refs/remotes/origin/HEAD"])
                .trimmingCharacters(in: .whitespacesAndNewlines) == "origin")

        let refs = try fixture.repository.refs()
        let names = refs.map(\.name)
        #expect(!names.contains("origin"))
        #expect(!refs.contains { $0.fullName == "refs/remotes/origin/HEAD" })
        #expect(names.filter { $0 == "origin/main" }.count == 1)
        #expect(refs.first { $0.name == "origin/main" }?.kind == .remoteBranch)
        // A local branch whose last component is HEAD is a real branch and stays listed.
        #expect(refs.first { $0.name == "feature/HEAD" }?.kind == .branch)
    }

    @Test("filter search paths are appended once and keep the user's PATH first")
    func filterSearchPaths() {
        #expect(GitRepository.appendingSearchPaths(["/opt/homebrew/bin", "/usr/local/bin"],
                                                   to: "/usr/local/bin:/usr/bin")
                == "/usr/local/bin:/usr/bin:/opt/homebrew/bin")
        #expect(GitRepository.appendingSearchPaths(["/opt/homebrew/bin"], to: nil)
                == "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin")
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
