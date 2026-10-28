import Testing
import Foundation
@testable import Differentialis

@Suite("Command-line --wait")
@MainActor
struct CommandLineWaitTests {
    /// The fields exactly as the launcher writes them: each one NUL-terminated.
    private func requestData(_ fields: [String]) -> Data {
        Data(fields.map { $0 + "\0" }.joined().utf8)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("differentialis-wait-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Request parsing

    @Test("a two-path request compares; a three-path request merges into the output")
    func parsesCompareAndMerge() throws {
        let compare = try CommandLineWait.parse(
            requestData([CommandLineWait.formatHeader, "compare", "", "/tmp/a.txt", "/tmp/b.txt"]),
            token: "T")
        #expect(compare.kind == .compare)
        #expect(compare.paths.map(\.path) == ["/tmp/a.txt", "/tmp/b.txt"])
        #expect(compare.output == nil)

        let merge = try CommandLineWait.parse(
            requestData([CommandLineWait.formatHeader, "merge", "/repo/file.swift",
                         "/tmp/base", "/tmp/local", "/tmp/remote"]),
            token: "T")
        #expect(merge.kind == .merge)
        #expect(merge.paths.map(\.path) == ["/tmp/base", "/tmp/local", "/tmp/remote"])
        #expect(merge.output?.path == "/repo/file.swift")
    }

    @Test("paths keep spaces, quotes, and newlines")
    func parsesUnusualPaths() throws {
        let odd = "/tmp/a \"quoted\"\nname.txt"
        let request = try CommandLineWait.parse(
            requestData([CommandLineWait.formatHeader, "compare", "", odd, "/tmp/b"]), token: "T")
        #expect(request.paths.first?.path == odd)
    }

    @Test("malformed requests are rejected")
    func rejectsMalformed() {
        let header = CommandLineWait.formatHeader
        #expect(throws: CommandLineWait.RequestError.malformed) {
            try CommandLineWait.parse(Data("\(header)\0compare\0\0/a\0/b".utf8), token: "T")   // unterminated
        }
        #expect(throws: CommandLineWait.RequestError.malformed) {
            try CommandLineWait.parse(requestData(["something else", "compare", "", "/a", "/b"]), token: "T")
        }
        #expect(throws: CommandLineWait.RequestError.unsupportedVersion) {
            try CommandLineWait.parse(requestData(["differentialis-wait 2", "compare", "", "/a", "/b"]), token: "T")
        }
        #expect(throws: CommandLineWait.RequestError.malformed) {
            try CommandLineWait.parse(requestData([header, "rebase", "", "/a", "/b"]), token: "T")
        }
        #expect(throws: CommandLineWait.RequestError.wrongPathCount) {
            try CommandLineWait.parse(requestData([header, "compare", "", "/a"]), token: "T")
        }
        #expect(throws: CommandLineWait.RequestError.wrongPathCount) {
            try CommandLineWait.parse(requestData([header, "compare", "/out", "/a", "/b"]), token: "T")
        }
        #expect(throws: CommandLineWait.RequestError.wrongPathCount) {
            try CommandLineWait.parse(requestData([header, "merge", "/out", "/a", "/b"]), token: "T")
        }
        #expect(throws: CommandLineWait.RequestError.relativePath) {
            try CommandLineWait.parse(requestData([header, "compare", "", "a.txt", "/b"]), token: "T")
        }
        #expect(throws: CommandLineWait.RequestError.relativePath) {
            try CommandLineWait.parse(requestData([header, "merge", "out.txt", "/a", "/b", "/c"]), token: "T")
        }
    }

    // MARK: - Request location

    @Test("only a request file directly inside the wait directory is honored")
    func requestLocation() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let token = "0F4C2B1A-6E7D-4C55-9C1B-7A2D3E4F5A6B"

        let inside = directory.appendingPathComponent("\(token).differentialis-wait")
        #expect(CommandLineWait.token(forRequestAt: inside, in: directory) == token)

        let nested = directory.appendingPathComponent("sub/\(token).differentialis-wait")
        #expect(CommandLineWait.token(forRequestAt: nested, in: directory) == nil)
        let elsewhere = URL(fileURLWithPath: "/tmp/\(token).differentialis-wait")
        #expect(CommandLineWait.token(forRequestAt: elsewhere, in: directory) == nil)
        let wrongExtension = directory.appendingPathComponent("\(token).txt")
        #expect(CommandLineWait.token(forRequestAt: wrongExtension, in: directory) == nil)
        let badToken = directory.appendingPathComponent("bad token!.differentialis-wait")
        #expect(CommandLineWait.token(forRequestAt: badToken, in: directory) == nil)
    }

    @Test("a request reached through a symlinked path still matches (/var vs /private/var)")
    func requestThroughSymlink() throws {
        let directory = try temporaryDirectory()
        let link = directory.deletingLastPathComponent()
            .appendingPathComponent("differentialis-wait-link-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory)
        defer {
            try? FileManager.default.removeItem(at: link)
            try? FileManager.default.removeItem(at: directory)
        }
        let viaLink = link.appendingPathComponent("ABC-123.differentialis-wait")
        #expect(CommandLineWait.token(forRequestAt: viaLink, in: directory) == "ABC-123")
    }

    // MARK: - Answering the launcher

    @Test("the acknowledgement and status are written only while the launcher's request exists")
    func finishWritesStatus() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let status = directory.appendingPathComponent("T1.status")
        let ack = directory.appendingPathComponent("T1.ack")

        CommandLineWait.acknowledge(token: "T1", in: directory)
        CommandLineWait.finish(token: "T1", status: CommandLineWait.success, in: directory)
        #expect(!FileManager.default.fileExists(atPath: ack.path))
        #expect(!FileManager.default.fileExists(atPath: status.path))

        try Data().write(to: directory.appendingPathComponent("T1.differentialis-wait"))
        CommandLineWait.acknowledge(token: "T1", in: directory)
        #expect(FileManager.default.fileExists(atPath: ack.path))
        CommandLineWait.finish(token: "T1", status: CommandLineWait.unresolved, in: directory)
        #expect(try String(contentsOf: status, encoding: .utf8) == "1\n")
    }

    // MARK: - Opening

    @Test("a compare request opens a tagged comparison; /dev/null is an absent side")
    func compareComparison() throws {
        let request = CommandLineWait.Request(token: "T", kind: .compare,
                                              paths: [URL(fileURLWithPath: "/dev/null"),
                                                      URL(fileURLWithPath: "/tmp/new.txt")],
                                              output: nil)
        let comparison = try CommandLineWait.comparison(for: request, isDirectory: { _ in false })
        #expect(comparison.waitToken == "T")
        #expect(comparison.a == .empty(name: "No File"))
        #expect(comparison.b == .file(URL(fileURLWithPath: "/tmp/new.txt")))
        #expect(comparison.mergeSession == nil)
    }

    @Test("a folder diff opens; a file against a folder does not")
    func folderComparison() throws {
        let folders = CommandLineWait.Request(token: "T", kind: .compare,
                                              paths: [URL(fileURLWithPath: "/tmp/left"),
                                                      URL(fileURLWithPath: "/tmp/right")],
                                              output: nil)
        #expect(try CommandLineWait.comparison(for: folders, isDirectory: { _ in true }).waitToken == "T")
        #expect(throws: CommandLineWait.RequestError.mixedFilesAndFolders) {
            try CommandLineWait.comparison(for: folders, isDirectory: { $0.lastPathComponent == "left" })
        }
    }

    @Test("a merge request orders base, mine, theirs and saves to the output")
    func mergeComparison() throws {
        let output = URL(fileURLWithPath: "/repo/Sources/file.swift")
        let request = CommandLineWait.Request(token: "T", kind: .merge,
                                              paths: [URL(fileURLWithPath: "/tmp/BASE"),
                                                      URL(fileURLWithPath: "/tmp/LOCAL"),
                                                      URL(fileURLWithPath: "/tmp/REMOTE")],
                                              output: output)
        let comparison = try CommandLineWait.comparison(for: request, isDirectory: { _ in false })
        let session = try #require(comparison.mergeSession)
        #expect(comparison.waitToken == "T")
        #expect(comparison.title == "Merge: file.swift")
        #expect(session.base == .file(URL(fileURLWithPath: "/tmp/BASE")))
        #expect(session.left == .file(URL(fileURLWithPath: "/tmp/LOCAL")))
        #expect(session.right == .file(URL(fileURLWithPath: "/tmp/REMOTE")))
        #expect(session.output == output)
        #expect(session.defaultSaveName == "file.swift")

        #expect(throws: CommandLineWait.RequestError.mergeNeedsFiles) {
            try CommandLineWait.comparison(for: request, isDirectory: { $0.lastPathComponent == "BASE" })
        }
    }

    // MARK: - Merge save result

    @Test("a save reports resolved only when no conflict markers were written")
    func savedResolved() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("merged.txt")
        let session = MergeSession(base: .text(content: "value = 1\nshared", name: "base"),
                                   left: .text(content: "value = 2\nshared", name: "left"),
                                   right: .text(content: "value = 3\nshared", name: "right"),
                                   output: output)
        await session.load()
        #expect(!session.savedResolved)

        try session.write(to: output)
        #expect(!session.savedResolved)
        #expect(try String(contentsOf: output, encoding: .utf8).contains("<<<<<<< left"))

        session.editResult("value = 3\nshared")
        #expect(session.hasUnsavedChanges)
        try session.write(to: output)
        #expect(session.savedResolved)
        #expect(!session.hasUnsavedChanges)
        #expect(try String(contentsOf: output, encoding: .utf8) == "value = 3\nshared")
    }
}
