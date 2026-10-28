import Foundation

/// The app side of `differentialis --wait`, which lets `git difftool` and `git mergetool` block
/// until a comparison is finished.
///
/// The launcher writes a request file into `<user temp dir>/differentialis-wait/` and opens it with
/// `open -b`, so it reaches `AppModel.open(urls:)` like any other document. The app acknowledges the
/// request with `<token>.ack` (so the launcher can tell an older app that ignores it), and writes the
/// exit status to `<token>.status` when the comparison is closed. Only a request file inside that
/// per-user, owner-only directory is honored: a path named in a request is never taken from a URL
/// or Apple Event alone.
enum CommandLineWait {
    static let requestExtension = "differentialis-wait"
    static let formatHeader = "differentialis-wait 1"

    /// Exit statuses reported to the launcher.
    static let success: Int32 = 0
    static let unresolved: Int32 = 1

    struct Request: Hashable, Sendable {
        enum Kind: String, Hashable, Sendable { case compare, merge }

        let token: String
        let kind: Kind
        let paths: [URL]
        /// Where a merge's Save writes, instead of asking with a save panel.
        let output: URL?
    }

    enum RequestError: Error, Equatable, LocalizedError {
        case malformed
        case unsupportedVersion
        case wrongPathCount
        case relativePath
        case mixedFilesAndFolders
        case mergeNeedsFiles

        var errorDescription: String? {
            switch self {
            case .malformed: return "The command-line request couldn’t be read."
            case .unsupportedVersion: return "The command-line tool is a different version than the app. Reinstall it from the app menu."
            case .wrongPathCount: return "--wait compares two files or folders, or merges three files into --output."
            case .relativePath: return "The command-line request contained a relative path."
            case .mixedFilesAndFolders: return "Choose either two files or two folders to compare."
            case .mergeNeedsFiles: return "A 3-way merge requires three files: base, left, and right."
            }
        }
    }

    /// `<DARWIN_USER_TEMP_DIR>/differentialis-wait`, matching `getconf DARWIN_USER_TEMP_DIR` in the
    /// launcher. NSTemporaryDirectory honors `$TMPDIR`, which a terminal session may have changed.
    static var directory: URL {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let length = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
        let temp: URL
        if length > 0, length <= buffer.count {
            temp = URL(fileURLWithPath: buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) },
                       isDirectory: true)
        } else {
            temp = FileManager.default.temporaryDirectory
        }
        return temp.appendingPathComponent("differentialis-wait", isDirectory: true)
    }

    /// The request's token when `url` names a request file directly inside `directory`, else nil.
    static func token(forRequestAt url: URL, in directory: URL) -> String? {
        guard url.isFileURL, url.pathExtension == requestExtension else { return nil }
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
        let expected = directory.resolvingSymlinksInPath().standardizedFileURL.path
        guard parent == expected else { return nil }
        let token = url.deletingPathExtension().lastPathComponent
        return isValidToken(token) ? token : nil
    }

    static func isValidToken(_ token: String) -> Bool {
        !token.isEmpty && token.count <= 64
            && token.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-") }
    }

    /// Parses the NUL-delimited fields the launcher writes: header, kind, output (empty for none),
    /// then the absolute paths in launcher order.
    static func parse(_ data: Data, token: String) throws -> Request {
        var fields = data.split(separator: 0, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        // Every field is NUL-terminated, so the split leaves one empty trailing element.
        guard fields.last == "" else { throw RequestError.malformed }
        fields.removeLast()
        guard let header = fields.first else { throw RequestError.malformed }
        guard header == formatHeader else {
            throw header.hasPrefix("differentialis-wait ") ? RequestError.unsupportedVersion : RequestError.malformed
        }
        guard fields.count >= 3, let kind = Request.Kind(rawValue: fields[1]) else {
            throw RequestError.malformed
        }
        let outputPath = fields[2]
        let paths = Array(fields.dropFirst(3))
        guard (paths + [outputPath]).allSatisfy({ $0.isEmpty || $0.hasPrefix("/") }),
              !paths.contains(where: \.isEmpty) else {
            throw RequestError.relativePath
        }
        switch kind {
        case .compare:
            guard paths.count == 2, outputPath.isEmpty else { throw RequestError.wrongPathCount }
        case .merge:
            guard paths.count == 3, !outputPath.isEmpty else { throw RequestError.wrongPathCount }
        }
        return Request(token: token, kind: kind,
                       paths: paths.map { URL(fileURLWithPath: $0) },
                       output: outputPath.isEmpty ? nil : URL(fileURLWithPath: outputPath))
    }

    /// The comparison a request opens, tagged with its token so closing it answers the launcher.
    static func comparison(for request: Request, isDirectory: (URL) -> Bool) throws -> Comparison {
        let sources = request.paths.map(source(for:))
        var comparison: Comparison
        switch request.kind {
        case .compare:
            // `git difftool --dir-diff` passes two folders; `/dev/null` is an absent file, never a folder.
            let kinds = Set(request.paths.filter { $0.path != "/dev/null" }.map(isDirectory))
            guard kinds.count <= 1 else { throw RequestError.mixedFilesAndFolders }
            comparison = Comparison.make(a: sources[0], b: sources[1])
        case .merge:
            guard !request.paths.contains(where: isDirectory) else { throw RequestError.mergeNeedsFiles }
            comparison = Comparison.merge(base: sources[0], left: sources[1], right: sources[2],
                                          output: request.output)
        }
        comparison.waitToken = request.token
        comparison.mergeSession?.waitToken = request.token
        return comparison
    }

    /// A comparison side for a path from git: `/dev/null` stands for a file that is absent on that
    /// side (an added or deleted file in `git difftool`), not an empty one.
    static func source(for url: URL) -> ComparisonSource {
        url.path == "/dev/null" ? .empty(name: "No File") : .file(url)
    }

    /// The launcher is still waiting: it removes its request file when it exits.
    static func isWaiting(token: String, in directory: URL = directory) -> Bool {
        FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("\(token).\(requestExtension)").path)
    }

    static func acknowledge(token: String, in directory: URL = directory) {
        write(Data(), to: directory.appendingPathComponent("\(token).ack"), token: token, in: directory)
    }

    /// Reports how the comparison ended. Skipped when the launcher has already gone (its request
    /// file is removed on exit), so an interrupted `--wait` leaves nothing behind.
    static func finish(token: String, status: Int32, in directory: URL = directory) {
        write(Data("\(status)\n".utf8), to: directory.appendingPathComponent("\(token).status"),
              token: token, in: directory)
    }

    private static func write(_ data: Data, to url: URL, token: String, in directory: URL) {
        guard isWaiting(token: token, in: directory) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
