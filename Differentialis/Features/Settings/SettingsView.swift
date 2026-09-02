import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The app's Settings window (⌘,): appearance mode, per-appearance color themes
/// (built-in, imported, and user-created), and the code font size used by text comparisons.
struct SettingsView: View {
    @State private var theme = ThemeManager.shared
    @State private var themeError: String?
    @State private var editorContext: ThemeEditorContext?

    var body: some View {
        @Bindable var theme = theme
        VStack(alignment: .leading, spacing: 26) {
            section("Appearance") {
                VStack(alignment: .leading, spacing: 8) {
                    GlassSegmentedControl(
                        selection: $theme.appearance,
                        options: AppearanceMode.allCases.map {
                            .init(value: $0, title: $0.label, systemImage: $0.systemImage)
                        },
                        compact: true)
                    Text("Auto follows the system appearance.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Background gradient")
                            .font(.system(size: 12, weight: .semibold))
                        HStack(spacing: 10) {
                            Text("Light").font(.system(size: 11)).foregroundStyle(.secondary)
                            Slider(value: $theme.lightCanvasGradient,
                                   in: 0...ThemeManager.maxCanvasGradient)
                                .frame(width: 110)
                            gradientSwatch(isDark: false, strength: theme.lightCanvasGradient)
                            Text("Dark").font(.system(size: 11)).foregroundStyle(.secondary)
                                .padding(.leading, 8)
                            Slider(value: $theme.darkCanvasGradient,
                                   in: 0...ThemeManager.maxCanvasGradient)
                                .frame(width: 110)
                            gradientSwatch(isDark: true, strength: theme.darkCanvasGradient)
                        }
                        Text("Left is flat, the midpoint is the theme's own shading, right doubles it. Each slider affects its appearance only.")
                            .font(.system(size: 10.5)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 6)
                }
            }

            section("Theme") {
                VStack(alignment: .leading, spacing: 16) {
                    themeRow(title: "Light", isDark: false,
                             selection: $theme.lightThemeID, active: !theme.isDarkResolved)
                    themeRow(title: "Dark", isDark: true,
                             selection: $theme.darkThemeID, active: theme.isDarkResolved)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Button("New Theme…") {
                                editorContext = ThemeEditorContext(seed: theme.activeTheme, editingID: nil)
                            }
                            Button("Import…") { importTheme() }
                            Button("Export Current…") { exportCurrentTheme() }
                        }
                        Text("Import Differentialis JSON themes or .tmTheme color schemes. Export the current theme to see the JSON format.")
                            .font(.system(size: 10.5)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            section("Code Font") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Picker("Font", selection: Binding(
                            get: { theme.codeFontName ?? "" },
                            set: { theme.codeFontName = $0.isEmpty ? nil : $0 })) {
                            Text("System (SF Mono)").tag("")
                            Divider()
                            ForEach(ThemeManager.monospaceFontFamilies, id: \.self) { family in
                                Text(family).tag(family)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                        Stepper(value: $theme.codeFontSize,
                                in: ThemeManager.minFontSize...ThemeManager.maxFontSize, step: 1) {
                            Text("\(Int(theme.codeFontSize)) pt")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .frame(minWidth: 38, alignment: .leading)
                        }
                        Button("Reset") { theme.resetFontSize() }
                            .disabled(theme.codeFontSize == ThemeManager.defaultFontSize)
                        Spacer()
                        Text("⌘+  ⌘−  ⌘0 · or pinch on a comparison")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Text("func compare(a: Line, b: Line) -> Diff")
                        .font(Theme.codeFont)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.well, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.08)))
                }
            }
        }
        .padding(26)
        .frame(width: 620)
        .background(Theme.canvas)
        .sheet(item: $editorContext) { context in
            ThemeEditorView(seed: context.seed, editingID: context.editingID)
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { themeError != nil },
                                    set: { if !$0 { themeError = nil } })) {
            Button("OK", role: .cancel) { themeError = nil }
        } message: {
            Text(themeError ?? "")
        }
    }

    /// Live preview of one appearance's canvas at the given gradient strength — feedback
    /// even for the appearance that isn't currently active.
    private func gradientSwatch(isDark: Bool, strength: Double) -> some View {
        let swatchTheme = theme.selectedTheme(isDark: isDark)
        return RoundedRectangle(cornerRadius: 6)
            .fill(LinearGradient(
                colors: [swatchTheme.canvasTop,
                         Theme.canvasBottom(for: swatchTheme, strength: strength)],
                startPoint: .top, endPoint: .bottom))
            .frame(width: 36, height: 24)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.15)))
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func themeRow(title: String, isDark: Bool,
                          selection: Binding<String>, active: Bool) -> some View {
        let selectedCustom = theme.themes(isDark: isDark)
            .first { $0.id == selection.wrappedValue && $0.isCustom }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 12, weight: .semibold))
                if active {
                    StatChip(text: "Active", color: Theme.brand)
                }
                // Visible actions for the selected custom theme (the context menu on each
                // card offers the same, but these are discoverable without right-clicking).
                if let selectedCustom {
                    Spacer()
                    HStack(spacing: 8) {
                        Button("Edit…") {
                            editorContext = ThemeEditorContext(seed: selectedCustom,
                                                               editingID: selectedCustom.id)
                        }
                        Button(isDark ? "Convert to Light" : "Convert to Dark") {
                            do { try theme.convertAppearance(of: selectedCustom) }
                            catch { themeError = error.localizedDescription }
                        }
                        Button("Remove", role: .destructive) { theme.removeTheme(selectedCustom) }
                    }
                    .controlSize(.small)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)],
                      alignment: .leading, spacing: 12) {
                ForEach(theme.themes(isDark: isDark)) { option in
                    ThemeSwatchCard(theme: option, selected: option.id == selection.wrappedValue) {
                        selection.wrappedValue = option.id
                        // Picking a theme for the other appearance switches to that
                        // appearance so the choice is immediately visible.
                        if theme.isDarkResolved != isDark {
                            theme.appearance = isDark ? .dark : .light
                        }
                    }
                    .contextMenu {
                        Button("New Theme Based on This…") {
                            editorContext = ThemeEditorContext(seed: option, editingID: nil)
                        }
                        if option.isCustom {
                            Button("Edit Theme…") {
                                editorContext = ThemeEditorContext(seed: option, editingID: option.id)
                            }
                            Button(option.isDark ? "Convert to Light Theme" : "Convert to Dark Theme") {
                                do { try theme.convertAppearance(of: option) }
                                catch { themeError = error.localizedDescription }
                            }
                            Divider()
                            Button("Remove Theme", role: .destructive) { theme.removeTheme(option) }
                        }
                    }
                }
            }
        }
    }

    private func importTheme() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.json]
        if let tmTheme = UTType(filenameExtension: "tmtheme") { types.append(tmTheme) }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.message = "Choose a theme file (.json or .tmTheme)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try ThemeManager.shared.importTheme(from: url) }
        catch { themeError = error.localizedDescription }
    }

    private func exportCurrentTheme() {
        let active = ThemeManager.shared.activeTheme
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(active.name).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try ThemeManager.shared.exportTheme(active, to: url) }
        catch { themeError = error.localizedDescription }
    }
}

/// A small preview card for one color theme: its canvas with mock diff rows.
struct ThemeSwatchCard: View {
    let theme: ColorTheme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                preview
                Text(theme.name)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(theme.isCustom ? "\(theme.name) (custom)" : theme.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 4) {
            bar(theme.added, width: 40)
            bar(theme.removed, width: 52)
            bar(theme.modified, width: 32)
        }
        .padding(10)
        .frame(width: 96, height: 58, alignment: .topLeading)
        .background(
            LinearGradient(colors: [theme.canvasTop, theme.canvasBottom],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? theme.brand : Color.primary.opacity(0.12),
                              lineWidth: selected ? 2 : 1))
    }

    private func bar(_ color: Color, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: width, height: 5)
    }
}
