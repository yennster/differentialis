import Foundation

/// A thin wrapper that drives the system `git` binary via `Process`.
struct GitRepository {
    let url: URL          // working directory (any path inside the repo)

    static let gitPath = "/usr/bin/git"

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
    func untrackedFiles() -> [GitChangedFile] {
        guard let out = try? run(["ls-files", "--others", "--exclude-standard", "-z"]) else { return [] }
        return out.split(separator: "\u{0}", omittingEmptySubsequences: true).map {
            GitChangedFile(path: String($0), oldPath: nil, status: .untracked)
        }
    }

    /// Working-copy changes relative to HEAD/index.
    func workingChanges(scope: WorkingScope) throws -> [GitChangedFile] {
        switch scope {
        case .staged:
            return parseNameStatus(try run(["diff", "--name-status", "-M", "-z", "--cached"]))
        case .unstaged:
            return parseNameStatus(try run(["diff", "--name-status", "-M", "-z"]))
        case .all:
            // -uall expands untracked directories to individual files (a bare "dir/" row can't be
            // diffed); the rewritten porcelain parser handles renames without phantom entries.
            return parsePorcelain(try run(["status", "--porcelain", "-uall", "-z"]))
        }
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
            let letter: Character = (x != " " && x != "?") ? x : (x == "?" ? "?" : y)
            let status = GitFileStatus(letter: letter == " " ? "M" : letter)
            files.append(GitChangedFile(path: path, oldPath: oldPath, status: status))
        }
        return files
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
