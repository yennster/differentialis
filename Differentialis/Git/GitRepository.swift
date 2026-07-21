import Foundation

/// A thin wrapper that drives the system `git` binary via `Process`.
struct GitRepository {
    let url: URL          // working directory (any path inside the repo)

    static let gitPath = "/usr/bin/git"

    private struct WorkingLayers {
        var staged: GitChangedFile?
        var unstaged: GitChangedFile?
        var untracked: GitChangedFile?
    }

    static func isRepository(_ url: URL) -> Bool {
        (try? GitRepository(url: url).run(["rev-parse", "--is-inside-work-tree"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    func root() throws -> URL {
        let path = try run(["rev-parse", "--show-toplevel"]).trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: path)
    }

    func displayName() -> String {
        ((try? root()) ?? url).lastPathComponent
    }

    // MARK: - Commits

    func commits(limit: Int = 200) throws -> [GitCommit] {
        // `git log` exits non-zero in a valid repository whose HEAD is still unborn. Treat that as
        // an empty history; working/index comparisons remain fully usable before the first commit.
        guard (try? run(["rev-parse", "--verify", "--quiet", "HEAD"])) != nil else { return [] }
        // Fields separated by US (0x1f), records terminated by RS (0x1e).
        let format = "%H\u{1f}%h\u{1f}%an\u{1f}%aI\u{1f}%P\u{1f}%s\u{1e}"
        let out = try run(["log", "--pretty=tformat:\(format)", "-n", "\(limit)"])
        let iso = ISO8601DateFormatter()
        return out.components(separatedBy: "\u{1e}").compactMap { record in
            let trimmed = record.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let fields = trimmed.components(separatedBy: "\u{1f}")
            guard fields.count >= 6 else { return nil }
            let parents = fields[4].split(separator: " ").map(String.init)
            return GitCommit(id: fields[0], shortSHA: fields[1], summary: fields[5],
                             author: fields[2], date: iso.date(from: fields[3]) ?? .distantPast,
                             parents: parents)
        }
    }

    func parentSHA(of sha: String) -> String? {
        let out = try? run(["rev-parse", "--verify", "--quiet", "\(sha)^"])
        let trimmed = out?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    // MARK: - Changed files

    func changedFiles(inCommit sha: String) throws -> [GitChangedFile] {
        let out = try run(["diff-tree", "--no-commit-id", "--name-status", "-r", "--root", "-M", "-z", sha])
        return parseNameStatus(out)
    }

    func changedFiles(from: String, to: String) throws -> [GitChangedFile] {
        let out = try run(["diff", "--name-status", "-M", "-z", from, to])
        return parseNameStatus(out)
    }

    /// Untracked files (used to complete "All Changes"), each surfaced as an added/untracked entry.
    func untrackedFiles() throws -> [GitChangedFile] {
        let out = try run(["ls-files", "--others", "--exclude-standard", "-z"])
        return out.split(separator: "\u{0}", omittingEmptySubsequences: true).map {
            GitChangedFile(path: String($0), oldPath: nil, status: .untracked)
        }
    }

    /// Working-copy changes relative to HEAD/index.
    func workingChanges(scope: WorkingScope) throws -> [GitChangedFile] {
        switch scope {
        case .staged:
            return try changedFilesFromReferenceToIndex("HEAD")
        case .unstaged:
            return try changedFilesFromIndexToWorkingTree()
        case .all:
            return try changedFilesAcrossWorkingLayers("HEAD", refLabel: "HEAD")
        }
    }

    /// Files changed from a selected reference to the index snapshot.
    func changedFilesFromReferenceToIndex(_ ref: String) throws -> [GitChangedFile] {
        let base = try diffBase(for: ref)
        let files = parseNameStatus(try run([
            "diff", "--name-status", "-M", "-z", "--cached", base, "--",
        ]))
        return try applyingCurrentConflicts(to: files)
    }

    /// Files changed from the index snapshot to the working tree.
    func changedFilesFromIndexToWorkingTree() throws -> [GitChangedFile] {
        let files = parseNameStatus(try run([
            "diff", "--name-status", "-M", "-z", "--",
        ]))
        return try applyingCurrentConflicts(to: files)
    }

    /// One coherent row per path across the reference→index and index→working-copy layers.
    ///
    /// A path changed in only one layer compares that layer's exact endpoints. When both layers
    /// changed, the row compares Index→Working Copy: the staged bytes remain visible even when the
    /// worktree happens to match the reference, and a staged deletion followed by a restored file
    /// becomes one inspectable row instead of contradictory Deleted + Untracked rows.
    func changedFilesAcrossWorkingLayers(_ ref: String, refLabel: String) throws -> [GitChangedFile] {
        let staged = try changedFilesFromReferenceToIndex(ref)
        let unstaged = try changedFilesFromIndexToWorkingTree()
        let untracked = try untrackedFiles()

        var layersByPath: [String: WorkingLayers] = [:]
        for file in staged { layersByPath[file.path, default: WorkingLayers()].staged = file }
        for file in unstaged { layersByPath[file.path, default: WorkingLayers()].unstaged = file }
        for file in untracked { layersByPath[file.path, default: WorkingLayers()].untracked = file }

        return layersByPath.keys.sorted().compactMap { path in
            guard let layers = layersByPath[path] else { return nil }
            return combinedWorkingFile(path: path, layers: layers, ref: ref, refLabel: refLabel)
        }
    }

    private func combinedWorkingFile(
        path: String,
        layers: WorkingLayers,
        ref: String,
        refLabel: String
    ) -> GitChangedFile? {
        // Conflict normalization already attached loadable Ours/Theirs stage endpoints. Prefer it
        // over ordinary layer composition and emit it only once even though both diffs may list it.
        if let conflict = [layers.staged, layers.unstaged]
            .compactMap({ $0 })
            .first(where: { $0.status == .conflicted }) {
            return conflict
        }

        let workLayer = layers.unstaged ?? layers.untracked
        if let staged = layers.staged, let workLayer {
            let indexPath = workLayer.oldPath ?? staged.path
            let indexSide: GitSide? = staged.status == .deleted ? nil : .index
            let workingSide: GitSide? = workLayer.status == .deleted ? nil : .workingCopy
            return GitChangedFile(
                path: path,
                oldPath: workLayer.oldPath,
                status: workLayer.status,
                comparison: GitFileComparison(
                    a: indexSide, aPath: indexPath, aLabel: "Index",
                    b: workingSide, bPath: workLayer.path, bLabel: "Working Copy"))
        }

        if var staged = layers.staged {
            staged.comparison = GitFileComparison(
                a: staged.status == .added ? nil : .ref(ref),
                aPath: staged.oldPath ?? staged.path,
                aLabel: refLabel,
                b: staged.status == .deleted ? nil : .index,
                bPath: staged.path,
                bLabel: "Index")
            return staged
        }

        if var unstaged = layers.unstaged {
            unstaged.comparison = GitFileComparison(
                a: unstaged.status == .added ? nil : .index,
                aPath: unstaged.oldPath ?? unstaged.path,
                aLabel: "Index",
                b: unstaged.status == .deleted ? nil : .workingCopy,
                bPath: unstaged.path,
                bLabel: "Working Copy")
            return unstaged
        }

        if var untracked = layers.untracked {
            untracked.comparison = GitFileComparison(
                a: nil, aPath: untracked.path, aLabel: "Index",
                b: .workingCopy, bPath: untracked.path, bLabel: "Working Copy")
            return untracked
        }
        return nil
    }

    // MARK: - Refs

    func refs() throws -> [GitRef] {
        var result: [GitRef] = [GitRef(name: "HEAD", fullName: "HEAD", kind: .head)]
        let out = try run(["for-each-ref",
                           "--format=%(refname)\u{1f}%(refname:short)",
                           "refs/heads", "refs/remotes", "refs/tags"])
        for line in out.split(separator: "\n") {
            let fields = line.components(separatedBy: "\u{1f}")
            guard fields.count == 2 else { continue }
            let full = fields[0]
            let short = fields[1]
            let kind: GitRefKind
            if full.hasPrefix("refs/heads/") { kind = .branch }
            else if full.hasPrefix("refs/remotes/") { kind = .remoteBranch }
            else { kind = .tag }
            if short.hasSuffix("/HEAD") { continue }
            result.append(GitRef(name: short, fullName: full, kind: kind))
        }
        return result
    }

    func currentBranch() -> String? {
        let out = try? run(["rev-parse", "--abbrev-ref", "HEAD"])
        return out?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Blobs

    func blobData(ref: String, path: String) throws -> Data {
        try runData(["show", "\(ref):\(path)"])
    }

    /// Reads the stage-0 blob for a path directly from the index, independent of both HEAD and the
    /// working tree. Unmerged paths intentionally fail because they have multiple index stages and
    /// therefore no single index snapshot to display.
    func indexData(path: String) throws -> Data {
        try runData(["show", ":\(path)"])
    }

    // MARK: - Parsing

    /// Parses NUL-delimited `git diff --name-status -z` output. `-z` is essential: without it git
    /// C-quotes any non-ASCII or whitespace-containing filename, and tab-splitting breaks on those.
    /// For a rename/copy, `-z` emits `STATUS\0oldpath\0newpath\0` (old before new).
    func parseNameStatus(_ out: String) -> [GitChangedFile] {
        var files: [GitChangedFile] = []
        let tokens = out.split(separator: "\u{0}", omittingEmptySubsequences: false).map(String.init)
        var i = 0
        while i < tokens.count {
            let code = tokens[i]
            i += 1
            guard let letter = code.first else { continue }   // skips the trailing empty token
            let status = GitFileStatus(letter: letter)
            if status == .renamed || status == .copied {
                guard i + 1 < tokens.count else { break }
                files.append(GitChangedFile(path: tokens[i + 1], oldPath: tokens[i], status: status))
                i += 2
            } else {
                guard i < tokens.count else { break }
                let path = tokens[i]
                i += 1
                if !path.isEmpty { files.append(GitChangedFile(path: path, oldPath: nil, status: status)) }
            }
        }
        return files
    }

    /// Parses NUL-delimited `git status --porcelain -z` output. Each record is `XY <path>`; for a
    /// rename/copy the ORIGINAL path follows as a separate NUL token AFTER the record (new-then-old,
    /// the reverse of `diff -z`). The previous tab/line parser produced phantom garbled entries from
    /// that trailing token and dropped rename origins.
    func parsePorcelain(_ out: String) -> [GitChangedFile] {
        let unmergedCodes: Set<String> = ["DD", "AU", "UD", "UA", "DU", "AA", "UU"]
        var files: [GitChangedFile] = []
        let tokens = out.split(separator: "\u{0}", omittingEmptySubsequences: false).map(String.init)
        var i = 0
        while i < tokens.count {
            let entry = tokens[i]
            i += 1
            guard entry.count >= 4 else { continue }   // "XY " + at least one path char
            let chars = Array(entry)
            let x = chars[0]
            let y = chars[1]
            let path = String(entry.dropFirst(3))
            var oldPath: String? = nil
            if x == "R" || x == "C" || y == "R" || y == "C", i < tokens.count {
                oldPath = tokens[i]   // the rename/copy origin
                i += 1
            }
            let xy = String([x, y])
            let status: GitFileStatus
            if unmergedCodes.contains(xy) {
                status = .conflicted
            } else {
                let letter: Character = (x != " " && x != "?") ? x : (x == "?" ? "?" : y)
                status = GitFileStatus(letter: letter == " " ? "M" : letter)
            }
            files.append(GitChangedFile(path: path, oldPath: oldPath, status: status))
        }
        return files
    }

    /// Resolves HEAD to this repository's empty-tree object when it has no commits yet. Asking Git
    /// to hash empty tree input derives the correct object ID for both SHA-1 and SHA-256 repos.
    /// Other references retain normal Git error behavior rather than becoming an empty tree.
    private func diffBase(for ref: String) throws -> String {
        guard ref == "HEAD" else { return ref }
        guard (try? run(["rev-parse", "--verify", "--quiet", "HEAD^{tree}"])) != nil else {
            let hash = try run(["hash-object", "-t", "tree", "--stdin"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !hash.isEmpty else {
                throw GitError.commandFailed("Git did not return an empty-tree object ID.")
            }
            return hash
        }
        return ref
    }

    /// Porcelain is authoritative for unmerged state, while `git diff <ref>` may report the same
    /// path as merely modified and `git diff` can emit both U and M records. Replace all records for
    /// a conflicted path with exactly one conflicted entry, and include index-only conflicts that a
    /// net reference-to-worktree diff might otherwise omit.
    private func applyingCurrentConflicts(to files: [GitChangedFile]) throws -> [GitChangedFile] {
        let status = try run(["status", "--porcelain", "-uall", "-z"])
        let parsedConflicts = parsePorcelain(status).filter { $0.status == .conflicted }
        guard !parsedConflicts.isEmpty else { return files }
        let stagesByPath = try unmergedStages()
        let conflicts = parsedConflicts.map { file -> GitChangedFile in
            var file = file
            let stages = stagesByPath[file.path, default: []]
            file.comparison = GitFileComparison(
                a: stages.contains(2) ? .indexStage(2) : nil,
                aPath: file.path,
                aLabel: "Ours",
                b: stages.contains(3) ? .indexStage(3) : nil,
                bPath: file.path,
                bLabel: "Theirs")
            return file
        }

        let conflictsByPath = Dictionary(uniqueKeysWithValues: conflicts.map { ($0.path, $0) })
        var emitted = Set<String>()
        var result: [GitChangedFile] = []
        result.reserveCapacity(files.count + conflicts.count)

        for file in files {
            guard let conflict = conflictsByPath[file.path] else {
                result.append(file)
                continue
            }
            if emitted.insert(file.path).inserted { result.append(conflict) }
        }
        for conflict in conflicts where emitted.insert(conflict.path).inserted {
            result.append(conflict)
        }
        return result
    }

    /// Index stages present for each unresolved path. Stage 2 is ours and stage 3 is theirs; a
    /// missing stage represents a deletion and is intentionally modeled as an empty comparison
    /// source rather than making `git show :path` fail on the absent stage-0 entry.
    private func unmergedStages() throws -> [String: Set<Int>] {
        let out = try run(["ls-files", "--unmerged", "-z", "--"])
        var result: [String: Set<Int>] = [:]
        for record in out.split(separator: "\u{0}", omittingEmptySubsequences: true) {
            guard let tab = record.firstIndex(of: "\t") else { continue }
            let header = record[..<tab]
            guard let stageText = header.split(separator: " ").last,
                  let stage = Int(stageText) else { continue }
            let path = String(record[record.index(after: tab)...])
            result[path, default: []].insert(stage)
        }
        return result
    }

    // MARK: - Process

    @discardableResult
    func run(_ args: [String]) throws -> String {
        let data = try runData(args)
        // Lossy decode: a single invalid UTF-8 byte becomes U+FFFD rather than nil'ing the whole
        // string (which used to blank the entire commit history / diff). The ASCII record
        // separators we parse on (NUL, US, RS, tab) survive lossy decoding intact.
        return String(decoding: data, as: UTF8.self)
    }

    func runData(_ args: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.gitPath)
        process.arguments = ["-C", url.path] + args

        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"   // never block waiting for credentials on stdin
        env["GIT_OPTIONAL_LOCKS"] = "0"    // read-only ops shouldn't contend for the index lock
        env["LC_ALL"] = "C"                // stable, non-localized output for parsing
        process.environment = env
        process.standardInput = FileHandle.nullDevice

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw GitError.commandFailed("Failed to launch git: \(error.localizedDescription)")
        }

        // Drain both pipes without deadlocking: a large diff can fill the stdout pipe buffer and
        // block git before it ever writes stderr, while the old code sat reading stderr first.
        // Read stderr concurrently and stdout on this thread, then join.
        let errSink = ByteSink()
        let stderrHandle = stderr.fileHandleForReading
        let queue = DispatchQueue(label: "app.differentialis.git.stderr")
        queue.async { errSink.data = stderrHandle.readDataToEndOfFile() }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        queue.sync {}   // ensure the stderr read has finished before we touch errSink

        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let message = String(data: errSink.data, encoding: .utf8) ?? "git exited with \(process.terminationStatus)"
            throw GitError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return outData
    }
}

/// Reference box so a background pipe read can hand its bytes back without a data race on a `var`.
private final class ByteSink: @unchecked Sendable {
    var data = Data()
}
