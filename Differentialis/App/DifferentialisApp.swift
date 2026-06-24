import SwiftUI

@main
struct DifferentialisApp: App {
    @State private var model = AppModel()

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
