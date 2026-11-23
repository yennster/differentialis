import Foundation
import AppKit
import Observation

/// Installs / uninstalls the `differentialis` command-line launcher into `/usr/local/bin`.
///
/// The launcher script is bundled at `Contents/Resources/differentialis`. This installs a *copy* of
/// it via a one-time administrator prompt — the same companion-tool pattern used by Tower,
/// SourceTree, and other developer apps — so drag-to-Applications users get the CLI without a manual
/// step. A copy (rather than a symlink into the bundle) keeps working even if the app later moves or
/// is launched from a translocated/quarantined path, and there's no dangling link after an eject.
/// The script resolves the app by bundle id, so the copy keeps finding the app; but it does go
/// stale when the launcher itself changes. `CommandLineToolStatus` compares the copy's version
/// marker with the bundled one, and the menu offers an update when the copy is older.
///
/// Everything runs on the main thread: `NSAppleScript` is main-thread-only (per Apple's docs), and
/// the administrator auth dialog is a separate process that blocks until the user responds — the
/// standard pattern for one-shot privileged installers.
@MainActor
enum CommandLineToolInstaller {
    nonisolated static let installPath = "/usr/local/bin/differentialis"

    /// Path to the bundled launcher inside the running app.
    static var bundledScriptPath: String {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/differentialis")
            .path
    }

    /// Reads and classifies the installed copy. Does a small file read; the menu calls it off the
    /// main thread at launch, and the actions below call it again right before acting.
    nonisolated static func currentStatus(bundledScriptPath: String) -> CommandLineToolStatus {
        CommandLineToolStatus.read(installPath: installPath, bundledPath: bundledScriptPath)
    }

    // MARK: - Install / update / uninstall

    /// Copies the bundled launcher to `installPath` via an administrator password prompt, which
    /// also updates an outdated copy. If something that isn't ours is already there, asks before
    /// replacing it. Shows a confirmation alert on success or a failure alert on error; a canceled
    /// password dialog is silent.
    static func install() {
        let status = currentStatus(bundledScriptPath: bundledScriptPath)
        if status == .foreign {
            // `rm -f` can't remove a real folder, and we won't `rm -rf` one; say so up front.
            let type = (try? FileManager.default.attributesOfItem(atPath: installPath))?[.type] as? FileAttributeType
            if type == .typeDirectory {
                present(error: "\(installPath) is a folder. Move or remove it, then try again.", action: "install")
                return
            }
            guard confirmReplacingForeignFile() else { return }
        }
        let updating = status == .outdated

        // Copy the launcher (don't symlink into the bundle) so it survives the app moving, and
        // chmod +x so it's directly runnable. `rm -f` first so a symlink at the path is replaced,
        // not written through.
        let shell = "mkdir -p /usr/local/bin && rm -f \(installPath) && cp \(quoted(bundledScriptPath)) \(installPath) && chmod 755 \(installPath)"
        let action = updating ? "update" : "install"
        switch runPrivileged(shell) {
        case .success:
            if updating {
                present(title: "Command Line Tool Updated",
                        message: "Updated `differentialis` at \(installPath) to the version in this copy of Differentialis.")
            } else {
                present(title: "Command Line Tool Installed",
                        message: "Installed `differentialis` to \(installPath).\nOpen Terminal and run `differentialis <path>`.")
            }
        case .canceled:
            break
        case .failure(let message):
            present(error: message, action: action)
        }
    }

    /// Removes the installed launcher. Refuses (with an explanation) if what's at `installPath`
    /// isn't ours, so an unrelated tool with the same name is never deleted.
    static func uninstall() {
        switch currentStatus(bundledScriptPath: bundledScriptPath) {
        case .notInstalled:
            return
        case .foreign:
            present(error: "The file at \(installPath) isn't the Differentialis command line tool, so it was left in place.",
                    action: "uninstall")
            return
        case .current, .outdated:
            break
        }
        switch runPrivileged("rm -f \(installPath)") {
        case .success:
            present(title: "Command Line Tool Removed",
                    message: "Removed `differentialis` from \(installPath).")
        case .canceled:
            break
        case .failure(let message):
            present(error: message, action: "uninstall")
        }
    }

    // MARK: - Privileged execution via NSAppleScript

    private enum PrivilegedResult {
        case success
        case canceled
        case failure(String)
    }

    /// Runs a shell command with administrator privileges, in-process via `NSAppleScript` so the
    /// auth prompt is attributed to Differentialis (not `osascript`). A user-canceled password
    /// dialog is reported as `errAEEventFailed (-128)` in the AppleScript error dictionary.
    private static func runPrivileged(_ command: String) -> PrivilegedResult {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"

        guard let script = NSAppleScript(source: source) else {
            return .failure("Couldn't build the installer script.")
        }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)

        if let info = errorInfo {
            let number = info[NSAppleScript.errorNumber] as? Int ?? 0
            if number == -128 {   // user canceled the auth dialog
                return .canceled
            }
            let message = (info[NSAppleScript.errorMessage] as? String)
                ?? "Install failed (error \(number))."
            return .failure(message)
        }
        return .success
    }

    /// Wraps a path in single quotes, escaping any embedded single quotes, for a shell literal.
    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Alerts

    private static func present(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// `action` is the verb that failed: "install", "update", or "uninstall".
    private static func present(error: String, action: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't \(action) the command line tool"
        alert.informativeText = error
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Asks before overwriting a file at `installPath` that isn't our launcher.
    private static func confirmReplacingForeignFile() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Replace the existing \"differentialis\"?"
        alert.informativeText = "\(installPath) already exists and isn't the Differentialis command line tool. Installing will replace it."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// The command line tool's install status for the app menu. Starts as "not installed" and is read
/// off the main thread at launch, whenever the app becomes active (the file may have changed in
/// Terminal or from another copy of the app), and after each install/update/uninstall. The actions
/// re-check the file themselves, so a briefly stale menu never deletes or overwrites the wrong file.
@MainActor
@Observable
final class CommandLineToolMenuState {
    private(set) var status: CommandLineToolStatus = .notInstalled
    @ObservationIgnored private var requests = LatestRequests<Int>()
    /// Never removed: this object lives as long as the app, and the block holds it weakly.
    @ObservationIgnored private var activeObserver: NSObjectProtocol?

    init() {
        refresh()
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let bundled = CommandLineToolInstaller.bundledScriptPath
        let request = requests.begin(0)
        Task {
            let status = await offMain {
                CommandLineToolInstaller.currentStatus(bundledScriptPath: bundled)
            }
            // A later refresh (e.g. after an install) supersedes a slower earlier read.
            guard requests.finish(0, request) else { return }
            self.status = status
        }
    }

    func install() {
        CommandLineToolInstaller.install()
        refresh()
    }

    func uninstall() {
        CommandLineToolInstaller.uninstall()
        refresh()
    }
}
