import SwiftUI
import AppKit

@main
struct DifferentialisApp: App {
    @State private var model = AppModel()
    @State private var cliInstalled = CommandLineToolInstaller.isInstalled
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    init() {
        // Applies the persisted appearance (via NSApp.appearance) before any window appears,
        // so AppKit-hosted chrome — popovers, menus, alerts — matches from the first frame.
        _ = ThemeManager.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    model.updater.checkForUpdates()
                }
                .disabled(!model.updater.canCheckForUpdates)

                Button(cliInstalled ? "Uninstall Command Line Tool…" : "Install Command Line Tool…") {
                    if cliInstalled {
                        CommandLineToolInstaller.uninstall()
                    } else {
                        CommandLineToolInstaller.install()
                    }
                    cliInstalled = CommandLineToolInstaller.isInstalled
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("New Text Comparison…") { model.chooseFiles(mode: .text) }
                    .keyboardShortcut("n", modifiers: .command)
                Button("New Pasted Text Comparison") { model.newPastedTextComparison() }
                    .keyboardShortcut("t", modifiers: .command)
                Button("New Image Comparison…") { model.chooseFiles(mode: .image) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("New Folder Comparison…") { model.chooseFiles(mode: .folder) }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                Button("New 3-Way Merge…") { model.chooseFiles(mode: .merge) }
                Divider()
                Button("Open Repository…") { model.chooseFiles(mode: .repository) }
                    .keyboardShortcut("o", modifiers: .command)
            }
            AppMenuCommands(model: model)
        }

        // Adds "Settings…" (⌘,) to the application menu.
        Settings {
            SettingsView()
        }
    }
}

/// Handles the `open` Apple Event delivered by `open -a Differentialis <path>` and by Finder
/// "Open With…". LaunchServices only routes document types the app claims (see Info.plist
/// `CFBundleDocumentTypes`); without that, folder/repo args against an already-running app are
/// rejected before reaching here. Routes the URLs into the shared `AppModel.open(urls:)`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { await AppModel.shared.open(urls: urls) }
    }

    /// Unsaved 3-way merge work lives only in memory, so ask before quitting throws it away.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = AppModel.shared else { return .terminateNow }
        let unsaved = model.mergesWithUnsavedChanges
        guard let first = unsaved.first else { return .terminateNow }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = unsaved.count == 1
            ? "“\(first.title)” has unsaved changes"
            : "\(unsaved.count) merges have unsaved changes"
        alert.informativeText = "If you quit now, your conflict choices and Result edits will be lost."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit Anyway")
        guard alert.runModal() == .alertSecondButtonReturn else {
            model.route = .comparison(first.id)
            return .terminateCancel
        }
        return .terminateNow
    }

    /// A launcher still waiting on `--wait` would otherwise block git until it noticed the app is gone.
    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared?.finishAllWaits()
    }
}
