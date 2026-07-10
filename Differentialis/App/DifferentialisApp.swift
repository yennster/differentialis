import SwiftUI
import AppKit

@main
struct DifferentialisApp: App {
    @State private var model = AppModel()
    @State private var cliInstalled = CommandLineToolInstaller.isInstalled
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 640)
                // The UI is a deliberately dark, glass-on-gradient design with hard-coded white/black
                // overlays; it's unreadable under the Light system appearance, so pin it to dark.
                .preferredColorScheme(.dark)
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
}
