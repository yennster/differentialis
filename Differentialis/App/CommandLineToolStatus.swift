import Foundation

/// What's at the command-line tool's install path, compared with the launcher bundled in the app.
///
/// The launcher carries a version marker line (`# differentialis-launcher-version: N`). Bump `N`
/// whenever `Resources/differentialis` changes, so installed copies are offered an update.
/// Pure and nonisolated: the menu computes it off the main thread, and tests call it directly.
enum CommandLineToolStatus: Equatable, Sendable {
    /// Nothing at the install path.
    case notInstalled
    /// Our launcher, at least as new as the bundled one.
    case current
    /// Our launcher, older than the bundled one (including copies from before the marker existed).
    case outdated
    /// Something else is at the install path (another tool, a directory, an unreadable file).
    /// We never offer to uninstall it, and installing over it asks first.
    case foreign

    static let markerPrefix = "# differentialis-launcher-version:"

    /// Lines the launcher's header has carried since before the marker existed; a file with both
    /// and no marker is one of our old copies (version 0), not someone else's tool.
    static let legacySignatures = [
        "differentialis — thin CLI launcher bundled inside Differentialis.app",
        "open -b app.differentialis.Differentialis",
    ]

    /// Only the header is searched for the marker, so a big unrelated binary isn't scanned.
    static let headerLineLimit = 40

    /// The marker's version, or `nil` if the text has no valid marker in its header.
    static func launcherVersion(in text: String) -> Int? {
        // `isNewline`, not "\n": Swift treats "\r\n" as one Character, so CRLF text wouldn't split.
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).prefix(headerLineLimit) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(markerPrefix) else { continue }
            let value = trimmed.dropFirst(markerPrefix.count).trimmingCharacters(in: .whitespaces)
            guard let version = Int(value), version >= 0 else { return nil }
            return version
        }
        return nil
    }

    /// The installed file's launcher version: its marker, 0 for a pre-marker copy of ours, or
    /// `nil` if it isn't ours.
    static func installedVersion(in text: String) -> Int? {
        if let version = launcherVersion(in: text) { return version }
        if legacySignatures.allSatisfy({ text.contains($0) }) { return 0 }
        return nil
    }

    /// Classifies the installed file's contents against the bundled launcher's.
    ///
    /// - Parameters:
    ///   - installed: the installed file's contents; `nil` when nothing is there. Something that
    ///     exists but can't be read (a folder, no read permission) is passed as `""` and is
    ///     treated as foreign, conservatively, even if it might be ours.
    ///   - bundled: the bundled launcher's contents; `nil` if it couldn't be read (then any copy
    ///     of ours counts as current, since there's nothing to update it to).
    static func evaluate(installed: String?, bundled: String?) -> CommandLineToolStatus {
        guard let installed else { return .notInstalled }
        guard let installedVersion = installedVersion(in: installed) else { return .foreign }
        guard let bundled, let bundledVersion = launcherVersion(in: bundled) else { return .current }
        return installedVersion < bundledVersion ? .outdated : .current
    }

    /// Reads both files and classifies them. Does file I/O; call it off the main thread at launch.
    static func read(installPath: String, bundledPath: String) -> CommandLineToolStatus {
        evaluate(installed: header(at: installPath), bundled: header(at: bundledPath))
    }

    /// The start of the file at `path` as text: `nil` if nothing is there (a dangling symlink
    /// counts as nothing, as it does for `rm -f`), `""` for anything that isn't a readable regular
    /// file, so that it's treated as foreign. A symlink is followed, so one pointing into an app
    /// bundle reads the script it points at.
    private static func header(at path: String) -> String? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue { return "" }
        // Only open regular files: opening a FIFO would block, and install/uninstall call this on
        // the main thread.
        let target = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard (try? FileManager.default.attributesOfItem(atPath: target))?[.type] as? FileAttributeType == .typeRegular
        else { return "" }
        guard let handle = FileHandle(forReadingAtPath: path) else { return "" }
        defer { try? handle.close() }
        // The marker and legacy signatures sit well inside the first 16 KB of the launcher.
        guard let data = try? handle.read(upToCount: 16 * 1024) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
