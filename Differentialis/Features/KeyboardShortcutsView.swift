import SwiftUI

struct KeyboardShortcutsView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Shortcut: Identifiable { let id = UUID(); let label: String; let keys: [String] }
    private struct Group: Identifiable { let id = UUID(); let title: String; let items: [Shortcut] }

    private let groups: [Group] = [
        Group(title: "General", items: [
            Shortcut(label: "New Text Comparison", keys: ["⌘", "N"]),
            Shortcut(label: "New Image Comparison", keys: ["⇧", "⌘", "N"]),
            Shortcut(label: "New Folder Comparison", keys: ["⌥", "⌘", "N"]),
            Shortcut(label: "Open Repository", keys: ["⌘", "O"]),
            Shortcut(label: "Keyboard Shortcuts", keys: ["⌘", "/"]),
            Shortcut(label: "Go to Welcome", keys: ["⇧", "⌘", "0"]),
        ]),
        Group(title: "Text Diff", items: [
            Shortcut(label: "Next change", keys: ["⌘", "]"]),
            Shortcut(label: "Previous change", keys: ["⌘", "["]),
            Shortcut(label: "Toggle Split / Unified", keys: ["⌘", "U"]),
        ]),
        Group(title: "Image Diff", items: [
            Shortcut(label: "Two-Up", keys: ["⌘", "1"]),
            Shortcut(label: "One-Up", keys: ["⌘", "2"]),
            Shortcut(label: "Split", keys: ["⌘", "3"]),
            Shortcut(label: "Difference", keys: ["⌘", "4"]),
        ]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "keyboard").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.brand)
                Text("Keyboard Shortcuts").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider().opacity(0.4)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 9) {
                            Text(group.title.uppercased())
                                .font(.system(size: 10.5, weight: .bold)).tracking(0.9)
                                .foregroundStyle(Theme.brand)
                            ForEach(group.items) { item in
                                HStack(spacing: 12) {
                                    Text(item.label).font(.system(size: 13)).foregroundStyle(.primary)
                                    Spacer(minLength: 12)
                                    HStack(spacing: 4) {
                                        ForEach(Array(item.keys.enumerated()), id: \.offset) { _, key in
                                            keycap(key)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 430, height: 540)
        .background(Theme.canvas)
    }

    private func keycap(_ symbol: String) -> some View {
        Text(symbol)
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .frame(minWidth: 26, minHeight: 26)
            .padding(.horizontal, 4)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.16)))
            .foregroundStyle(.primary)
    }
}
