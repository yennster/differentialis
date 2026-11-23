import Testing
import Foundation
@testable import Differentialis

@Suite("Command line tool install status")
struct CommandLineToolStatusTests {
    private func launcher(version: Int?) -> String {
        var lines = [
            "#!/bin/bash",
            "#",
            "# differentialis — thin CLI launcher bundled inside Differentialis.app.",
            "#",
        ]
        if let version { lines.append("# differentialis-launcher-version: \(version)") }
        lines += ["set -euo pipefail", "exec open -b app.differentialis.Differentialis \"$@\""]
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Marker parsing

    @Test("the marker's version is read from the header")
    func parsesMarker() {
        #expect(CommandLineToolStatus.launcherVersion(in: launcher(version: 3)) == 3)
        #expect(CommandLineToolStatus.launcherVersion(in: "#!/bin/sh\n  # differentialis-launcher-version:12  \n") == 12)
        #expect(CommandLineToolStatus.launcherVersion(in: launcher(version: nil)) == nil)
        #expect(CommandLineToolStatus.launcherVersion(in: "#!/bin/sh\r\n# differentialis-launcher-version: 4\r\n") == 4)
    }

    @Test("a malformed marker or one past the header isn't a version")
    func rejectsMalformedMarker() {
        #expect(CommandLineToolStatus.launcherVersion(in: "# differentialis-launcher-version: two\n") == nil)
        #expect(CommandLineToolStatus.launcherVersion(in: "# differentialis-launcher-version: -1\n") == nil)
        #expect(CommandLineToolStatus.launcherVersion(in: "# differentialis-launcher-version:\n") == nil)
        let late = String(repeating: "#\n", count: CommandLineToolStatus.headerLineLimit)
            + "# differentialis-launcher-version: 1\n"
        #expect(CommandLineToolStatus.launcherVersion(in: late) == nil)
    }

    @Test("the bundled launcher carries a version marker")
    func bundledLauncherHasMarker() throws {
        let url = try #require(Bundle.main.url(forResource: "differentialis", withExtension: nil))
        let text = try String(contentsOf: url, encoding: .utf8)
        let version = try #require(CommandLineToolStatus.launcherVersion(in: text))
        #expect(version >= 1)
        #expect(CommandLineToolStatus.evaluate(installed: text, bundled: text) == .current)
    }

    // MARK: - Status

    @Test("nothing installed")
    func absent() {
        #expect(CommandLineToolStatus.evaluate(installed: nil, bundled: launcher(version: 2)) == .notInstalled)
    }

    @Test("an installed copy at the bundled version, or newer, is current")
    func current() {
        #expect(CommandLineToolStatus.evaluate(installed: launcher(version: 2), bundled: launcher(version: 2)) == .current)
        #expect(CommandLineToolStatus.evaluate(installed: launcher(version: 3), bundled: launcher(version: 2)) == .current)
    }

    @Test("an older installed copy is outdated, including one from before the marker")
    func outdated() {
        #expect(CommandLineToolStatus.evaluate(installed: launcher(version: 1), bundled: launcher(version: 2)) == .outdated)
        #expect(CommandLineToolStatus.evaluate(installed: launcher(version: nil), bundled: launcher(version: 1)) == .outdated)
    }

    @Test("someone else's file at the install path is foreign")
    func foreign() {
        let bundled = launcher(version: 1)
        #expect(CommandLineToolStatus.evaluate(installed: "#!/bin/sh\necho hello\n", bundled: bundled) == .foreign)
        #expect(CommandLineToolStatus.evaluate(installed: "", bundled: bundled) == .foreign)
        // Mentioning the app isn't enough: a legacy copy has both signature lines.
        #expect(CommandLineToolStatus.evaluate(
            installed: "#!/bin/sh\nexec open -b app.differentialis.Differentialis \"$@\"\n",
            bundled: bundled) == .foreign)
    }

    @Test("with no readable bundled launcher, any copy of ours is current")
    func missingBundle() {
        #expect(CommandLineToolStatus.evaluate(installed: launcher(version: nil), bundled: nil) == .current)
        #expect(CommandLineToolStatus.evaluate(installed: "#!/bin/sh\n", bundled: nil) == .foreign)
    }

    // MARK: - Reading files

    @Test("files on disk: absent, ours, a symlink to ours, a directory")
    func readsFiles() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("differentialis-cli-status-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let bundled = dir.appendingPathComponent("bundled")
        try launcher(version: 2).write(to: bundled, atomically: true, encoding: .utf8)
        let installed = dir.appendingPathComponent("installed")

        #expect(CommandLineToolStatus.read(installPath: installed.path, bundledPath: bundled.path) == .notInstalled)

        try launcher(version: 1).write(to: installed, atomically: true, encoding: .utf8)
        #expect(CommandLineToolStatus.read(installPath: installed.path, bundledPath: bundled.path) == .outdated)

        try FileManager.default.removeItem(at: installed)
        try FileManager.default.createSymbolicLink(at: installed, withDestinationURL: bundled)
        #expect(CommandLineToolStatus.read(installPath: installed.path, bundledPath: bundled.path) == .current)

        try FileManager.default.removeItem(at: installed)
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: false)
        #expect(CommandLineToolStatus.read(installPath: installed.path, bundledPath: bundled.path) == .foreign)

        // A symlink to someone else's file is foreign; a dangling one is nothing installed.
        try FileManager.default.removeItem(at: installed)
        let other = dir.appendingPathComponent("other")
        try "#!/bin/sh\necho hi\n".write(to: other, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: installed, withDestinationURL: other)
        #expect(CommandLineToolStatus.read(installPath: installed.path, bundledPath: bundled.path) == .foreign)
        try FileManager.default.removeItem(at: other)
        #expect(CommandLineToolStatus.read(installPath: installed.path, bundledPath: bundled.path) == .notInstalled)
    }
}
