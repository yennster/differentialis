import SwiftUI

/// What the theme editor sheet opens with: the theme it starts from and, when
/// editing an existing custom theme, that theme's id (nil creates a new one).
struct ThemeEditorContext: Identifiable {
    let id = UUID()
    var seed: ColorTheme
    var editingID: String?
}

/// Create or edit a custom color theme. Everything is a draft — the preview updates
/// live, and nothing is applied until Save, which persists the theme to the themes
/// folder and selects it for its appearance.
struct ThemeEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let editingID: String?
    @State private var name: String
    @State private var isDark: Bool
    @State private var canvasTop: Color
    @State private var canvasBottom: Color
    @State private var added: Color
    @State private var removed: Color
    @State private var modified: Color
    @State private var conflict: Color
    @State private var brand: Color
    @State private var brandAlt: Color
    @State private var badgeForeground: Color
    @State private var saveError: String?

    init(seed: ColorTheme, editingID: String?) {
        self.editingID = editingID
        _name = State(initialValue: editingID == nil ? "\(seed.name) Copy" : seed.name)
        _isDark = State(initialValue: seed.isDark)
        _canvasTop = State(initialValue: seed.canvasTop)
        _canvasBottom = State(initialValue: seed.canvasBottom)
        _added = State(initialValue: seed.added)
        _removed = State(initialValue: seed.removed)
        _modified = State(initialValue: seed.modified)
        _conflict = State(initialValue: seed.conflict)
        _brand = State(initialValue: seed.brand)
        _brandAlt = State(initialValue: seed.brandAlt)
        _badgeForeground = State(initialValue: seed.badgeForeground)
    }

    private var draft: ColorTheme {
        ColorTheme(
            id: "draft", name: name.trimmingCharacters(in: .whitespaces),
            isDark: isDark,
            canvasTop: canvasTop, canvasBottom: canvasBottom,
            added: added, removed: removed, modified: modified, conflict: conflict,
            brand: brand, brandAlt: brandAlt, badgeForeground: badgeForeground,
            isCustom: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "paintpalette")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.brand)
                Text(editingID == nil ? "New Theme" : "Edit Theme")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }

            HStack(spacing: 14) {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                GlassSegmentedControl(
                    selection: $isDark,
                    options: [.init(value: false, title: "Light", systemImage: "sun.max"),
                              .init(value: true, title: "Dark", systemImage: "moon")],
                    compact: true)
                    .frame(width: 190)
                Spacer()
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3),
                      alignment: .leading, spacing: 10) {
                colorField("Background", $canvasTop)
                colorField("Background Base", $canvasBottom)
                colorField("Badge Text", $badgeForeground)
                colorField("Added", $added)
                colorField("Removed", $removed)
                colorField("Modified", $modified)
                colorField("Conflict", $conflict)
                colorField("Accent", $brand)
                colorField("Accent Alt", $brandAlt)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("PREVIEW")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                ThemePreview(theme: draft)
            }

            HStack(spacing: 10) {
                if let saveError {
                    Text(saveError)
                        .font(.system(size: 11)).foregroundStyle(Theme.removed)
                        .lineLimit(2)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button(editingID == nil ? "Add Theme" : "Save Changes") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brand)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 580)
        .background(Theme.canvas)
    }

    private func colorField(_ label: String, _ color: Binding<Color>) -> some View {
        ColorPicker(selection: color, supportsOpacity: false) {
            Text(label).font(.system(size: 12))
        }
    }

    private func save() {
        do {
            try ThemeManager.shared.saveCustomTheme(ThemeFile(draft), replacing: editingID)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

/// A mock two-line-number diff rendered entirely from one `ColorTheme`, independent of
/// the app's active theme — used by the editor to preview a draft before it's applied.
struct ThemePreview: View {
    let theme: ColorTheme

    private var ink: Color { theme.isDark ? .white.opacity(0.92) : .black.opacity(0.88) }
    private var inkFaint: Color { theme.isDark ? .white.opacity(0.45) : .black.opacity(0.45) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(ink.opacity(0.08)).frame(height: 1)
            row(1, "func compare(a: Line, b: Line) {", accent: nil, fill: nil)
            row(2, "    return lines(a).changes(b)", accent: theme.removed,
                fill: theme.removed.opacity(theme.fillOpacity),
                highlight: (18, 29, theme.removed.opacity(theme.highlightOpacity)))
            row(3, "    return Myers.diff(a, b)", accent: theme.added,
                fill: theme.added.opacity(theme.fillOpacity),
                highlight: (18, 28, theme.added.opacity(theme.highlightOpacity)))
            row(4, "    // tuned for large files", accent: theme.modified,
                fill: theme.modified.opacity(theme.fillOpacity))
            row(5, "}", accent: nil, fill: nil)
        }
        .background(
            LinearGradient(colors: [theme.canvasTop, theme.canvasBottom],
                           startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.12)))
    }

    private var header: some View {
        HStack(spacing: 8) {
            badge("A", color: theme.removed)
            Text("draft.swift — Index")
                .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(ink)
            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .bold)).foregroundStyle(inkFaint)
            badge("B", color: theme.modified)
            Text("Working Copy")
                .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(ink)
            Spacer()
            Image(systemName: "bookmark.fill")
                .font(.system(size: 10)).foregroundStyle(theme.brand)
            chip("+1", color: theme.added)
            chip("−1", color: theme.removed)
            chip("~1", color: theme.brandAlt)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    private func badge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(theme.badgeForeground)
            .frame(width: 15, height: 15)
            .background(color, in: RoundedRectangle(cornerRadius: 4))
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }

    private func row(_ number: Int, _ text: String, accent: Color?, fill: Color?,
                     highlight: (start: Int, end: Int, color: Color)? = nil) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(accent ?? .clear).frame(width: 2.5)
            Text("\(number)")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(inkFaint)
                .frame(width: 24, alignment: .trailing)
                .padding(.trailing, 7)
            Text(highlight.map { highlightedLine(text, ranges: [$0.start..<$0.end], color: $0.color) }
                 ?? AttributedString(text))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(ink)
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.vertical, 2.5)
        .background(fill ?? .clear)
    }
}
