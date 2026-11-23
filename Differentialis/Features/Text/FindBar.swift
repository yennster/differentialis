import SwiftUI
import AppKit

/// The Find bar shown under a diff's or merge Review's toolbar (⌘F). Return finds the next match,
/// ⇧Return the previous, Escape closes; ⌘G / ⇧⌘G work from the menu wherever focus is.
struct FindBar: View {
    @Binding var query: String
    @Binding var options: TextSearchOptions
    let matchCount: Int
    /// 0-based index of the current match.
    let currentIndex: Int?
    /// Bumped by ⌘F while the bar is already open, to put the cursor back in the field.
    let focusRequest: Int
    let next: () -> Void
    let previous: () -> Void
    let close: () -> Void

    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("Find", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($fieldFocused)
                    .onSubmit(next)
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.shift) else { return .ignored }
                        previous()
                        return .handled
                    }
                    .onExitCommand(perform: close)
                    .accessibilityLabel("Find")
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Theme.wellStrong.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
            .frame(maxWidth: 320)

            Text(countLabel)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(!query.isEmpty && matchCount == 0 ? Theme.conflict : .secondary)
                .accessibilityLabel(countAccessibilityLabel)

            HStack(spacing: 4) {
                Button(action: previous) { Image(systemName: "chevron.up") }
                    .help("Previous match (⇧⌘G)")
                    .accessibilityLabel("Previous match")
                Button(action: next) { Image(systemName: "chevron.down") }
                    .help("Next match (⌘G)")
                    .accessibilityLabel("Next match")
            }
            .buttonStyle(.borderless)
            .disabled(matchCount == 0)

            Toggle("Match Case", isOn: $options.caseSensitive)
                .toggleStyle(.checkbox)
                .controlSize(.small)
            Toggle("Changed Lines Only", isOn: $options.changedLinesOnly)
                .toggleStyle(.checkbox)
                .controlSize(.small)

            Spacer(minLength: 0)
            Button("Done", action: close)
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .onAppear { fieldFocused = true }
        .onChange(of: focusRequest) { _, _ in fieldFocused = true }
    }

    private var countLabel: String {
        if query.isEmpty { return "" }
        if matchCount == 0 { return "No matches" }
        if let currentIndex { return "\(currentIndex + 1) of \(matchCount)" }
        return "\(matchCount) match\(matchCount == 1 ? "" : "es")"
    }

    private var countAccessibilityLabel: String {
        countLabel.isEmpty ? "No search" : countLabel
    }
}

/// The Go to Line bar (⌘L). In a two-way diff it asks which side's line numbers to use.
struct GoToLineBar: View {
    @Binding var side: DiffSide
    /// Shows the A / B picker; merge Result has one set of line numbers.
    var showsSidePicker = true
    /// Bumped by ⌘L while the bar is already open.
    let focusRequest: Int
    let go: (Int) -> Void
    let close: () -> Void

    @State private var text = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.right.to.line")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Go to line").font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("Line", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5).monospacedDigit())
                .frame(width: 70)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Theme.wellStrong.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
                .focused($fieldFocused)
                .onSubmit(submit)
                .onExitCommand(perform: close)
                .accessibilityLabel("Line number")
            if showsSidePicker {
                Picker("Side", selection: $side) {
                    Text("A").tag(DiffSide.left)
                    Text("B").tag(DiffSide.right)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Which side’s line numbers to use")
                .accessibilityLabel("Side")
            }
            Button("Go", action: submit)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(lineNumber == nil)
            Spacer(minLength: 0)
            Button("Done", action: close)
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .onAppear { fieldFocused = true }
        .onChange(of: focusRequest) { _, _ in fieldFocused = true }
    }

    private var lineNumber: Int? {
        Int(text.trimmingCharacters(in: .whitespaces))
    }

    private func submit() {
        guard let lineNumber else { return }
        go(lineNumber)
        close()
    }
}

/// Sends a standard text-finder action (the Find bar of an `NSTextView`, such as the pasted-text
/// editors or merge Result) up the responder chain. The Find menu falls back to this when the
/// focused view has no Find of its own.
@MainActor
enum TextFinderCommand {
    static func send(_ action: NSTextFinder.Action) {
        _ = NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: sender(action))
    }

    static func perform(_ action: NSTextFinder.Action, on textView: NSTextView) {
        textView.performTextFinderAction(sender(action))
    }

    /// `performTextFinderAction(_:)` reads the action from the sender's tag.
    private static func sender(_ action: NSTextFinder.Action) -> NSMenuItem {
        let item = NSMenuItem()
        item.tag = action.rawValue
        return item
    }
}
