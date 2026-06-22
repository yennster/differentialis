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
        let out = try run(["diff-tree", "--no-commit-id", "--name-status", "-r", "--root", "-M", sha])
        return parseNameStatus(out)
    }

    func changedFiles(from: String, to: String) throws -> [GitChangedFile] {
        let out = try run(["diff", "--name-status", "-M", from, to])
        return parseNameStatus(out)
    }

    /// Working-copy changes relative to HEAD/index.
    func workingChanges(scope: WorkingScope) throws -> [GitChangedFile] {
        switch scope {
        case .staged:
            return parseNameStatus(try run(["diff", "--name-status", "-M", "--cached"]))
        case .unstaged:
            return parseNameStatus(try run(["diff", "--name-status", "-M"]))
        case .all:
            let out = try run(["status", "--porcelain", "-z"])
            return parsePorcelain(out)
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

    func parseNameStatus(_ out: String) -> [GitChangedFile] {
        var files: [GitChangedFile] = []
        for raw in out.split(separator: "\n") {
            let parts = raw.split(separator: "\t").map(String.init)
            guard let code = parts.first, let letter = code.first else { continue }
            let status = GitFileStatus(letter: letter)
            if (status == .renamed || status == .copied), parts.count >= 3 {
                files.append(GitChangedFile(path: parts[2], oldPath: parts[1], status: status))
            } else if parts.count >= 2 {
                files.append(GitChangedFile(path: parts[1], oldPath: nil, status: status))
            }
        }
        return files
    }

    private func parsePorcelain(_ out: String) -> [GitChangedFile] {
        var files: [GitChangedFile] = []
        let entries = out.split(separator: "\u{0}").map(String.init)
        var i = 0
        while i < entries.count {
            let entry = entries[i]
            guard entry.count >= 3 else { i += 1; continue }
            let x = Array(entry)[0]
            let y = Array(entry)[1]
            let path = String(entry.dropFirst(3))
            let letter: Character = x != " " && x != "?" ? x : y
            let status = GitFileStatus(letter: letter == " " ? "M" : letter)
            files.append(GitChangedFile(path: path, oldPath: nil, status: status))
            i += 1
        }
        return files
    }

    // MARK: - Process

    @discardableResult
    func run(_ args: [String]) throws -> String {
        let data = try runData(args)
        return String(data: data, encoding: .utf8) ?? ""
    }

    func runData(_ args: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.gitPath)
        process.arguments = ["-C", url.path] + args
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw GitError.commandFailed("Failed to launch git: \(error.localizedDescription)")
        }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let message = String(data: errData, encoding: .utf8) ?? "git exited with \(process.terminationStatus)"
            throw GitError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return outData
    }
}
