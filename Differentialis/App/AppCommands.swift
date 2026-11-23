import SwiftUI
import AppKit

/// Actions the currently-active comparison view publishes to the menu bar so
/// that menu commands (and their keyboard shortcuts) act on the focused window.
struct DiffCommandActions {
    var nextChange: (() -> Void)? = nil
    var prevChange: (() -> Void)? = nil
    var toggleLayout: (() -> Void)? = nil
    var setImageMode: ((Int) -> Void)? = nil
    var swapAB: (() -> Void)? = nil
    var refresh: (() -> Void)? = nil
    var copyChangeToA: (() -> Void)? = nil
    var copyChangeToB: (() -> Void)? = nil
    /// Find in the focused diff or merge. When nil, the Find menu goes to the focused text view's
    /// own find bar instead (the pasted-text editors, merge Result).
    var find: (() -> Void)? = nil
    var findNext: (() -> Void)? = nil
    var findPrevious: (() -> Void)? = nil
    var goToLine: (() -> Void)? = nil
    /// The view's Find runs in a text view's own find bar (merge Result), so the text-editor-only
    /// Find items (Replace, Use Selection, Jump to Selection) stay available.
    var findInTextView = false
}

/// Refreshes one open changeset's file list. Equatable (by changeset and model), so passing it
/// down the environment doesn't invalidate the open diff on every changeset body pass.
struct ChangesetRefreshAction: Equatable {
    let changesetID: UUID
    let model: AppModel

    @MainActor func callAsFunction() {
        Task { await model.refreshChangeset(changesetID) }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.changesetID == rhs.changesetID && lhs.model === rhs.model
    }
}

extension EnvironmentValues {
    /// Set by an open changeset (`ChangesetDetailView`). Views inside it route Refresh (⌘R) here,
    /// so ⌘R re-reads the file list too, not just the open file.
    @Entry var changesetRefresh: ChangesetRefreshAction? = nil
    /// Counts an open changeset's refreshes. Comparison views fold it into their load key, so each
    /// refresh also reloads the open file (as its own ⌘R would).
    @Entry var changesetRevision = 0
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

    /// Off where a diff or merge Review owns Find, since those items need a text view.
    private var textFinderItemsEnabled: Bool {
        diff?.find == nil || diff?.findInTextView == true
    }

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Go to Welcome") { model.route = .welcome }
                .keyboardShortcut("0", modifiers: [.command, .shift])
            Button("Refresh") { diff?.refresh?() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(diff?.refresh == nil)
            Divider()
            Button("Next Change") { diff?.nextChange?() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(diff?.nextChange == nil)
            Button("Previous Change") { diff?.prevChange?() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(diff?.prevChange == nil)
            Button("Go to Line…") { diff?.goToLine?() }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(diff?.goToLine == nil)
            Button("Copy Change to B") { diff?.copyChangeToB?() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(diff?.copyChangeToB == nil)
            Button("Copy Change to A") { diff?.copyChangeToA?() }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(diff?.copyChangeToA == nil)
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
            Button("Swap A / B Side") { diff?.swapAB?() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(diff?.swapAB == nil)
            Divider()
            Button("Increase Font Size") { ThemeManager.shared.adjustFontSize(by: 1) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Decrease Font Size") { ThemeManager.shared.adjustFontSize(by: -1) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Reset Font Size") { ThemeManager.shared.resetFontSize() }
                .keyboardShortcut("0", modifiers: .command)
        }

        // Replaces the standard Find submenu so ⌘F, ⌘G, and ⇧⌘G reach the diff and merge views,
        // which aren't text views. Without a Find of their own, each item goes to the focused text
        // view's find bar, as the standard menu would.
        CommandGroup(replacing: .textEditing) {
            Menu("Find") {
                Button("Find…") {
                    if let find = diff?.find { find() } else { TextFinderCommand.send(.showFindInterface) }
                }
                .keyboardShortcut("f", modifiers: .command)
                Button("Find and Replace…") { TextFinderCommand.send(.showReplaceInterface) }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                    .disabled(!textFinderItemsEnabled)
                Button("Find Next") {
                    if let next = diff?.findNext { next() } else { TextFinderCommand.send(.nextMatch) }
                }
                .keyboardShortcut("g", modifiers: .command)
                Button("Find Previous") {
                    if let previous = diff?.findPrevious { previous() } else { TextFinderCommand.send(.previousMatch) }
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                // Diff rows are SwiftUI text, whose selection can't be read, so this is for the
                // text editors; the diff Find bar shares the system find pasteboard instead.
                Button("Use Selection for Find") { TextFinderCommand.send(.setSearchString) }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(!textFinderItemsEnabled)
                Button("Jump to Selection") {
                    _ = NSApp.sendAction(#selector(NSTextView.centerSelectionInVisibleArea(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("j", modifiers: .command)
                .disabled(!textFinderItemsEnabled)
            }
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
