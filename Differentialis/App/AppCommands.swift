import SwiftUI
import AppKit

/// Actions the currently-active comparison view publishes to the menu bar so
/// that menu commands (and their keyboard shortcuts) act on the focused window.
struct DiffCommandActions {
    var nextChange: (() -> Void)? = nil
    var prevChange: (() -> Void)? = nil
    var toggleLayout: (() -> Void)? = nil
    var setImageMode: ((Int) -> Void)? = nil
}

struct DiffCommandsKey: FocusedValueKey {
    typealias Value = DiffCommandActions
}

extension FocusedValues {
    var diffCommands: DiffCommandActions? {
        get { self[DiffCommandsKey.self] }
        set { self[DiffCommandsKey.self] = newValue }
    }
}

/// The app's View and Help menus. Navigation/mode items are enabled only when
/// the focused comparison exposes the matching action.
struct AppMenuCommands: Commands {
    let model: AppModel
    @FocusedValue(\.diffCommands) private var diff

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Go to Welcome") { model.route = .welcome }
                .keyboardShortcut("0", modifiers: [.command, .shift])
            Divider()
            Button("Next Change") { diff?.nextChange?() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(diff?.nextChange == nil)
            Button("Previous Change") { diff?.prevChange?() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(diff?.prevChange == nil)
            Button("Toggle Split / Unified") { diff?.toggleLayout?() }
                .keyboardShortcut("u", modifiers: .command)
                .disabled(diff?.toggleLayout == nil)
            Divider()
            Button("Image: Two-Up") { diff?.setImageMode?(1) }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(diff?.setImageMode == nil)
            Button("Image: One-Up") { diff?.setImageMode?(2) }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(diff?.setImageMode == nil)
            Button("Image: Split") { diff?.setImageMode?(3) }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(diff?.setImageMode == nil)
            Button("Image: Difference") { diff?.setImageMode?(4) }
                .keyboardShortcut("4", modifiers: .command)
                .disabled(diff?.setImageMode == nil)
        }

        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") { model.showShortcuts = true }
                .keyboardShortcut("/", modifiers: .command)
            Divider()
            Button("Changelog") {
                NSWorkspace.shared.open(URL(string: "https://github.com/yennster/differentialis/blob/main/CHANGELOG.md")!)
            }
            Button("Differentialis on GitHub") {
                NSWorkspace.shared.open(URL(string: "https://github.com/yennster/differentialis")!)
            }
            Button("Visit differentialis.app") {
                NSWorkspace.shared.open(URL(string: "https://www.differentialis.app")!)
            }
        }
    }
}
