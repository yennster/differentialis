import Foundation
import AppKit

/// Installs / uninstalls the `differentialis` command-line launcher into `/usr/local/bin`.
///
/// The launcher script is bundled at `Contents/Resources/differentialis`. This installs a *copy* of
/// it via a one-time administrator prompt — the same companion-tool pattern used by Tower,
/// SourceTree, and other developer apps — so drag-to-Applications users get the CLI without a manual
/// step. A copy (rather than a symlink into the bundle) keeps working even if the app later moves or
/// is launched from a translocated/quarantined path, and there's no dangling link after an eject.
/// The script resolves the app by bundle id, so a standalone copy never needs to be kept in sync.
///
/// Everything runs on the main thread: `NSAppleScript` is main-thread-only (per Apple's docs), and
/// the administrator auth dialog is a separate process that blocks until the user responds — the
/// standard pattern for one-shot privileged installers.
@MainActor
enum CommandLineToolInstaller {
    static let installPath = "/usr/local/bin/differentialis"

    /// Path to the bundled launcher inside the running app.
    static var bundledScriptPath: String {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/differentialis")
            .path
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: installPath)
    }

    // MARK: - Install / uninstall

    /// Creates the symlink via an administrator password prompt. Shows a confirmation alert on
    /// success or a failure alert on error; a canceled password dialog is silent.
    static func install() {
        // Copy the launcher (don't symlink into the bundle) so it survives the app moving, and
        // chmod +x so it's directly runnable.
        let shell = "mkdir -p /usr/local/bin && rm -f \(installPath) && cp \(quoted(bundledScriptPath)) \(installPath) && chmod 755 \(installPath)"
        switch runPrivileged(shell) {
        case .success:
            present(success: "Installed `differentialis` to \(installPath).\nOpen Terminal and run `differentialis <path>`.")
        case .canceled:
            break
        case .failure(let message):
            present(error: message)
        }
    }

    static func uninstall() {
        switch runPrivileged("rm -f \(installPath)") {
        case .success:
            present(success: "Removed `differentialis` from \(installPath).")
        case .canceled:
            break
        case .failure(let message):
            present(error: message)
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

    private static func present(success: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Command Line Tool Installed"
        alert.informativeText = success
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func present(error: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't install the command line tool"
        alert.informativeText = error
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
