import SwiftUI
import AppKit

/// How the app decides between light and dark chrome.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

/// A named color scheme for the diff canvas and semantic diff colors — one is
/// active per appearance (light/dark), Sublime Text–style.
struct ColorTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let isDark: Bool

    let canvasTop: Color
    let canvasBottom: Color
    let added: Color
    let removed: Color
    let modified: Color
    let conflict: Color
    let brand: Color
    let brandAlt: Color
    /// Text drawn on top of solid semantic-color badges.
    let badgeForeground: Color
    /// True for imported / user-created themes (removable, backed by a file).
    var isCustom: Bool = false

    // Row fills and intra-line highlights are stronger on dark canvases.
    var fillOpacity: Double { isDark ? 0.16 : 0.13 }
    var highlightOpacity: Double { isDark ? 0.38 : 0.28 }

    static let defaultDark = ColorTheme(
        id: "differentialis-dark", name: "Differentialis", isDark: true,
        canvasTop: Color(red: 0.06, green: 0.07, blue: 0.11),
        canvasBottom: Color(red: 0.02, green: 0.02, blue: 0.04),
        added: Color(red: 0.30, green: 0.82, blue: 0.50),
        removed: Color(red: 0.96, green: 0.40, blue: 0.50),
        modified: Color(red: 0.42, green: 0.66, blue: 1.00),
        conflict: Color(red: 1.00, green: 0.70, blue: 0.28),
        brand: Color(red: 0.62, green: 0.45, blue: 0.96),
        brandAlt: Color(red: 0.36, green: 0.78, blue: 0.98),
        badgeForeground: Color(red: 0.035, green: 0.035, blue: 0.055))

    static let defaultLight = ColorTheme(
        id: "differentialis-light", name: "Differentialis", isDark: false,
        canvasTop: Color(red: 0.995, green: 0.995, blue: 1.00),
        canvasBottom: Color(red: 0.962, green: 0.962, blue: 0.978),
        added: Color(red: 0.11, green: 0.55, blue: 0.28),
        removed: Color(red: 0.80, green: 0.18, blue: 0.30),
        modified: Color(red: 0.08, green: 0.42, blue: 0.85),
        conflict: Color(red: 0.72, green: 0.47, blue: 0.03),
        brand: Color(red: 0.46, green: 0.30, blue: 0.85),
        brandAlt: Color(red: 0.02, green: 0.52, blue: 0.76),
        badgeForeground: Color(red: 0.99, green: 0.99, blue: 1.00))

    static let darkThemes: [ColorTheme] = [
        .defaultDark,
        ColorTheme(
            id: "mariana", name: "Mariana", isDark: true,
            canvasTop: Color(red: 0.22, green: 0.26, blue: 0.29),
            canvasBottom: Color(red: 0.15, green: 0.18, blue: 0.21),
            added: Color(red: 0.60, green: 0.78, blue: 0.58),
            removed: Color(red: 0.93, green: 0.37, blue: 0.40),
            modified: Color(red: 0.40, green: 0.60, blue: 0.80),
            conflict: Color(red: 0.98, green: 0.68, blue: 0.35),
            brand: Color(red: 0.78, green: 0.58, blue: 0.78),
            brandAlt: Color(red: 0.37, green: 0.71, blue: 0.71),
            badgeForeground: Color(red: 0.10, green: 0.13, blue: 0.15)),
        ColorTheme(
            id: "monokai", name: "Monokai", isDark: true,
            canvasTop: Color(red: 0.18, green: 0.19, blue: 0.16),
            canvasBottom: Color(red: 0.12, green: 0.125, blue: 0.10),
            added: Color(red: 0.65, green: 0.89, blue: 0.18),
            removed: Color(red: 0.98, green: 0.15, blue: 0.45),
            modified: Color(red: 0.40, green: 0.85, blue: 0.94),
            conflict: Color(red: 0.99, green: 0.59, blue: 0.12),
            brand: Color(red: 0.68, green: 0.51, blue: 1.00),
            brandAlt: Color(red: 0.90, green: 0.86, blue: 0.45),
            badgeForeground: Color(red: 0.11, green: 0.11, blue: 0.09)),
        ColorTheme(
            id: "one-dark", name: "One Dark", isDark: true,
            canvasTop: Color(red: 0.18, green: 0.20, blue: 0.24),
            canvasBottom: Color(red: 0.12, green: 0.14, blue: 0.17),
            added: Color(red: 0.60, green: 0.76, blue: 0.47),
            removed: Color(red: 0.88, green: 0.42, blue: 0.46),
            modified: Color(red: 0.38, green: 0.69, blue: 0.94),
            conflict: Color(red: 0.90, green: 0.75, blue: 0.48),
            brand: Color(red: 0.78, green: 0.47, blue: 0.87),
            brandAlt: Color(red: 0.34, green: 0.71, blue: 0.76),
            badgeForeground: Color(red: 0.10, green: 0.11, blue: 0.13)),
        ColorTheme(
            id: "solarized-dark", name: "Solarized", isDark: true,
            canvasTop: Color(red: 0.03, green: 0.24, blue: 0.30),
            canvasBottom: Color(red: 0.00, green: 0.13, blue: 0.16),
            added: Color(red: 0.55, green: 0.63, blue: 0.00),
            removed: Color(red: 0.86, green: 0.20, blue: 0.18),
            modified: Color(red: 0.15, green: 0.55, blue: 0.82),
            conflict: Color(red: 0.71, green: 0.54, blue: 0.00),
            brand: Color(red: 0.42, green: 0.44, blue: 0.77),
            brandAlt: Color(red: 0.16, green: 0.63, blue: 0.60),
            badgeForeground: Color(red: 0.00, green: 0.10, blue: 0.12)),
    ]

    static let lightThemes: [ColorTheme] = [
        .defaultLight,
        ColorTheme(
            id: "solarized-light", name: "Solarized", isDark: false,
            canvasTop: Color(red: 0.99, green: 0.96, blue: 0.89),
            canvasBottom: Color(red: 0.93, green: 0.91, blue: 0.84),
            added: Color(red: 0.45, green: 0.52, blue: 0.00),
            removed: Color(red: 0.86, green: 0.20, blue: 0.18),
            modified: Color(red: 0.15, green: 0.55, blue: 0.82),
            conflict: Color(red: 0.71, green: 0.54, blue: 0.00),
            brand: Color(red: 0.42, green: 0.44, blue: 0.77),
            brandAlt: Color(red: 0.16, green: 0.63, blue: 0.60),
            badgeForeground: Color(red: 0.99, green: 0.96, blue: 0.89)),
        ColorTheme(
            id: "github-light", name: "GitHub", isDark: false,
            canvasTop: Color(red: 1.00, green: 1.00, blue: 1.00),
            canvasBottom: Color(red: 0.95, green: 0.96, blue: 0.97),
            added: Color(red: 0.10, green: 0.50, blue: 0.22),
            removed: Color(red: 0.81, green: 0.13, blue: 0.18),
            modified: Color(red: 0.04, green: 0.41, blue: 0.85),
            conflict: Color(red: 0.60, green: 0.40, blue: 0.00),
            brand: Color(red: 0.51, green: 0.31, blue: 0.87),
            brandAlt: Color(red: 0.04, green: 0.41, blue: 0.85),
            badgeForeground: Color(red: 1.00, green: 1.00, blue: 1.00)),
    ]

}

/// App-wide appearance, color theme, and code-font settings. Persisted to
/// UserDefaults; observed by every view through the `Theme` accessors.
@MainActor
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    static let minFontSize: CGFloat = 9
    static let maxFontSize: CGFloat = 24
    static let defaultFontSize: CGFloat = 12

    var appearance: AppearanceMode {
        didSet {
            defaults.set(appearance.rawValue, forKey: "appearanceMode")
            applyAppearance()
        }
    }
    var darkThemeID: String {
        didSet { defaults.set(darkThemeID, forKey: "darkThemeID") }
    }
    var lightThemeID: String {
        didSet { defaults.set(lightThemeID, forKey: "lightThemeID") }
    }
    // Corrective writes inside these observers must be conditional: under @Observable,
    // assigning to the property from its own didSet re-enters the observer through the
    // macro-generated accessor, so an unconditional self-assignment recurses until the
    // stack overflows. Reassign only when clamping changes the value, and return — the
    // re-entrant call persists the corrected value.
    var codeFontSize: CGFloat {
        didSet {
            let clamped = codeFontSize.clamped(to: Self.minFontSize...Self.maxFontSize)
            if codeFontSize != clamped {
                codeFontSize = clamped
                return
            }
            defaults.set(Double(codeFontSize), forKey: "codeFontSize")
        }
    }

    /// Font family for code text; nil means the system monospaced font (SF Mono).
    var codeFontName: String? {
        didSet { defaults.set(codeFontName, forKey: "codeFontName") }
    }

    /// Installed fixed-pitch font families, for the Settings font picker.
    static let monospaceFontFamilies: [String] = {
        NSFontManager.shared.availableFontFamilies.filter { family in
            guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family),
                  let name = members.first?.first as? String,
                  let font = NSFont(name: name, size: 12) else { return false }
            return font.isFixedPitch
        }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }()

    /// How much of the theme's top-to-bottom canvas shading to apply, per appearance:
    /// 0 is a flat canvas (the theme's top color everywhere), 1 the authored gradient,
    /// up to 2 for double the authored shading (extrapolated past the bottom color).
    static let maxCanvasGradient: Double = 2

    var lightCanvasGradient: Double {
        didSet {
            let clamped = min(max(lightCanvasGradient, 0), Self.maxCanvasGradient)
            if lightCanvasGradient != clamped {
                lightCanvasGradient = clamped
                return
            }
            defaults.set(lightCanvasGradient, forKey: "lightCanvasGradient")
        }
    }
    var darkCanvasGradient: Double {
        didSet {
            let clamped = min(max(darkCanvasGradient, 0), Self.maxCanvasGradient)
            if darkCanvasGradient != clamped {
                darkCanvasGradient = clamped
                return
            }
            defaults.set(darkCanvasGradient, forKey: "darkCanvasGradient")
        }
    }

    var activeCanvasGradient: Double {
        isDarkResolved ? darkCanvasGradient : lightCanvasGradient
    }

    /// Whether the app is effectively dark right now — follows `NSApp.effectiveAppearance`,
    /// which reflects both a forced appearance and (in Auto) the OS setting.
    private(set) var isDarkResolved: Bool = true

    /// Imported and user-created themes, loaded from the themes folder.
    private(set) var customThemes: [ColorTheme] = []

    var activeTheme: ColorTheme {
        isDarkResolved ? resolveTheme(id: darkThemeID, isDark: true)
                       : resolveTheme(id: lightThemeID, isDark: false)
    }

    /// Built-in themes for one appearance followed by the custom ones.
    func themes(isDark: Bool) -> [ColorTheme] {
        (isDark ? ColorTheme.darkThemes : ColorTheme.lightThemes)
            + customThemes.filter { $0.isDark == isDark }
    }

    private func resolveTheme(id: String, isDark: Bool) -> ColorTheme {
        themes(isDark: isDark).first { $0.id == id } ?? (isDark ? .defaultDark : .defaultLight)
    }

    /// The theme currently chosen for one appearance, whether or not it's active.
    func selectedTheme(isDark: Bool) -> ColorTheme {
        resolveTheme(id: isDark ? darkThemeID : lightThemeID, isDark: isDark)
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?

    private init() {
        let defaults = UserDefaults.standard
        appearance = AppearanceMode(rawValue: defaults.string(forKey: "appearanceMode") ?? "") ?? .system
        darkThemeID = defaults.string(forKey: "darkThemeID") ?? ColorTheme.defaultDark.id
        lightThemeID = defaults.string(forKey: "lightThemeID") ?? ColorTheme.defaultLight.id
        let stored = defaults.double(forKey: "codeFontSize")
        codeFontSize = stored == 0 ? Self.defaultFontSize
                                   : CGFloat(stored).clamped(to: Self.minFontSize...Self.maxFontSize)
        codeFontName = defaults.string(forKey: "codeFontName")
        lightCanvasGradient = min(max(defaults.object(forKey: "lightCanvasGradient") as? Double ?? 1, 0), Self.maxCanvasGradient)
        darkCanvasGradient = min(max(defaults.object(forKey: "darkCanvasGradient") as? Double ?? 1, 0), Self.maxCanvasGradient)
        applyAppearance()
        refreshResolvedAppearance()
        loadCustomThemes()
        // effectiveAppearance is KVO-observable; changes land on the main thread.
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance) { _, _ in
            Task { @MainActor in ThemeManager.shared.refreshResolvedAppearance() }
        }
    }

    /// Forces (or, for Auto, un-forces) the appearance at the application level so that
    /// AppKit-hosted chrome — popovers, menus, alerts — matches the SwiftUI windows.
    private func applyAppearance() {
        switch appearance {
        case .system: NSApplication.shared.appearance = nil
        case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
        refreshResolvedAppearance()
    }

    private func refreshResolvedAppearance() {
        let match = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        isDarkResolved = match == .darkAqua
    }

    func adjustFontSize(by delta: CGFloat) {
        codeFontSize = (codeFontSize + delta).clamped(to: Self.minFontSize...Self.maxFontSize)
    }

    /// Absolute size, for continuous gestures (pinch zoom). The property's `didSet` clamps.
    func setFontSize(_ size: CGFloat) {
        codeFontSize = size
    }

    func resetFontSize() {
        codeFontSize = Self.defaultFontSize
    }

    // MARK: - Custom themes

    /// Imported and user-created themes live here as JSON files (see `ThemeFile`);
    /// files dropped into the folder by hand are picked up on the next launch.
    static var themesDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Differentialis/Themes", isDirectory: true)
    }

    private func loadCustomThemes() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: Self.themesDirectory, includingPropertiesForKeys: nil)) ?? []
        customThemes = files
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let file = try? ThemeFile.decode(data),
                      let theme = try? file.colorTheme() else { return nil }
                return theme
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Validates and registers a theme file chosen by the user, then selects it.
    /// Accepts Differentialis JSON themes and Sublime Text `.tmTheme` color schemes
    /// (both are stored in the themes folder as our JSON format).
    func importTheme(from url: URL) throws {
        let data = try Data(contentsOf: url)
        if url.pathExtension.lowercased() == "tmtheme" {
            let theme = try TmThemeImporter.colorTheme(
                from: data, fallbackName: url.deletingPathExtension().lastPathComponent)
            try saveCustomTheme(ThemeFile(theme), replacing: nil)
        } else {
            try saveCustomTheme(try ThemeFile.decode(data), replacing: nil)
        }
    }

    /// Persists `file` to the themes folder, replacing `oldID`'s file when editing, and
    /// selects the result for its appearance.
    func saveCustomTheme(_ file: ThemeFile, replacing oldID: String?) throws {
        let theme = try file.colorTheme()
        if let oldID, oldID != theme.id {
            deleteThemeFiles(id: oldID)
            customThemes.removeAll { $0.id == oldID }
            if darkThemeID == oldID { darkThemeID = theme.isDark ? theme.id : ColorTheme.defaultDark.id }
            if lightThemeID == oldID { lightThemeID = theme.isDark ? ColorTheme.defaultLight.id : theme.id }
        }
        try FileManager.default.createDirectory(at: Self.themesDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(file).write(to: Self.themesDirectory.appendingPathComponent("\(theme.id).json"))
        customThemes.removeAll { $0.id == theme.id }
        customThemes.append(theme)
        customThemes.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        select(theme)
    }

    func removeTheme(_ theme: ColorTheme) {
        guard theme.isCustom else { return }
        deleteThemeFiles(id: theme.id)
        customThemes.removeAll { $0.id == theme.id }
        if darkThemeID == theme.id { darkThemeID = ColorTheme.defaultDark.id }
        if lightThemeID == theme.id { lightThemeID = ColorTheme.defaultLight.id }
    }

    func select(_ theme: ColorTheme) {
        if theme.isDark { darkThemeID = theme.id } else { lightThemeID = theme.id }
    }

    func exportTheme(_ theme: ColorTheme, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(ThemeFile(theme)).write(to: url)
    }

    /// Removes every file in the themes folder whose contents resolve to `id` — files can
    /// be hand-renamed, so matching by decoded identity is the only reliable way.
    private func deleteThemeFiles(id: String) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: Self.themesDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: url),
                  let file = try? ThemeFile.decode(data),
                  let theme = try? file.colorTheme(), theme.id == id else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

/// Trackpad pinch-to-zoom for the code font, mirroring the image panes' magnification
/// gesture: the pinch scales from the size at gesture start (half-point steps while
/// pinching, snapped to a whole point on release).
private struct CodeFontZoomModifier: ViewModifier {
    @State private var baseSize: CGFloat?

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let base = baseSize ?? ThemeManager.shared.codeFontSize
                    baseSize = base
                    ThemeManager.shared.setFontSize((base * value.magnification * 2).rounded() / 2)
                }
                .onEnded { _ in
                    baseSize = nil
                    ThemeManager.shared.setFontSize(ThemeManager.shared.codeFontSize.rounded())
                }
        )
    }
}

extension View {
    /// Lets a comparison surface resize the shared code font with a trackpad pinch.
    func codeFontZoomGesture() -> some View {
        modifier(CodeFontZoomModifier())
    }
}
