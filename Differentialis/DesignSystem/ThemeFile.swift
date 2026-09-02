import SwiftUI
import AppKit

/// The on-disk JSON format for an importable color theme.
///
/// ```json
/// {
///   "name": "My Theme",
///   "appearance": "dark",              // "dark" or "light"
///   "background": "#101218",           // canvas top; bottom is derived unless given
///   "canvasBottom": "#05060A",         // optional
///   "added": "#4DD17F",
///   "removed": "#F56680",
///   "modified": "#6BA8FF",
///   "conflict": "#FFB347",             // optional
///   "brand": "#9E73F5",                // optional — accent for selections and chips
///   "brandAlt": "#5CC7FA",             // optional — secondary accent
///   "badgeForeground": "#090910"       // optional — text on solid color badges
/// }
/// ```
///
/// Colors are `#RGB`, `#RRGGBB`, or `#RRGGBBAA` hex strings. Optional keys fall back to
/// the built-in default theme for the file's appearance. Export the current theme from
/// Settings to get a complete, editable example.
struct ThemeFile: Codable {
    var name: String
    var appearance: String
    var background: String?
    var canvasTop: String?
    var canvasBottom: String?
    var added: String
    var removed: String
    var modified: String
    var conflict: String?
    var brand: String?
    var brandAlt: String?
    var badgeForeground: String?

    enum ThemeFileError: LocalizedError {
        case unreadableJSON
        case invalidAppearance
        case missingBackground
        case badColor(key: String, value: String)

        var errorDescription: String? {
            switch self {
            case .unreadableJSON:
                return "The file isn't valid theme JSON. Export the current theme from Settings to see the expected format."
            case .invalidAppearance:
                return "\"appearance\" must be \"light\" or \"dark\"."
            case .missingBackground:
                return "The theme needs a \"background\" (or \"canvasTop\") color."
            case .badColor(let key, let value):
                return "\"\(key)\" has an unreadable color \"\(value)\" — use #RGB, #RRGGBB, or #RRGGBBAA."
            }
        }
    }

    static func decode(_ data: Data) throws -> ThemeFile {
        do {
            return try JSONDecoder().decode(ThemeFile.self, from: data)
        } catch {
            throw ThemeFileError.unreadableJSON
        }
    }

    /// Builds the runtime theme, filling optional slots from the appearance's default theme.
    func colorTheme() throws -> ColorTheme {
        let isDark: Bool
        switch appearance.lowercased() {
        case "dark": isDark = true
        case "light": isDark = false
        default: throw ThemeFileError.invalidAppearance
        }
        let fallback = isDark ? ColorTheme.defaultDark : ColorTheme.defaultLight

        guard let topHex = background ?? canvasTop else { throw ThemeFileError.missingBackground }
        let top = try rgb(topHex, key: background != nil ? "background" : "canvasTop")
        // Without an explicit bottom, deepen the top slightly so the canvas keeps its gradient.
        let bottom = try canvasBottom.map { try rgb($0, key: "canvasBottom") }
            ?? top.scaled(by: isDark ? 0.72 : 0.94)

        return ColorTheme(
            id: Self.customID(name: name, isDark: isDark),
            name: name, isDark: isDark,
            canvasTop: top.color, canvasBottom: bottom.color,
            added: try color(added, key: "added"),
            removed: try color(removed, key: "removed"),
            modified: try color(modified, key: "modified"),
            conflict: try conflict.map { try color($0, key: "conflict") } ?? fallback.conflict,
            brand: try brand.map { try color($0, key: "brand") } ?? fallback.brand,
            brandAlt: try brandAlt.map { try color($0, key: "brandAlt") } ?? fallback.brandAlt,
            badgeForeground: try badgeForeground.map { try color($0, key: "badgeForeground") }
                ?? fallback.badgeForeground,
            isCustom: true)
    }

    /// Stable identifier for an imported theme; also names its file in the themes folder.
    static func customID(name: String, isDark: Bool) -> String {
        let slug = name.lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { result, char in
                if char != "-" || result.last != "-" { result.append(char) }
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "custom-\(isDark ? "dark" : "light")-\(slug.isEmpty ? "theme" : slug)"
    }

    private func color(_ hex: String, key: String) throws -> Color {
        try rgb(hex, key: key).color
    }

    private func rgb(_ hex: String, key: String) throws -> RGB {
        guard let rgb = RGB(hex: hex) else { throw ThemeFileError.badColor(key: key, value: hex) }
        return rgb
    }
}

/// Minimal sRGB triple used for hex parsing, serialization, and simple color math.
struct RGB {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        let shift: UInt64 = s.count == 8 ? 8 : 0  // ignore trailing alpha
        r = Double((value >> (16 + shift)) & 0xFF) / 255
        g = Double((value >> (8 + shift)) & 0xFF) / 255
        b = Double((value >> shift) & 0xFF) / 255
    }

    @MainActor init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        r = ns.redComponent; g = ns.greenComponent; b = ns.blueComponent
    }

    var color: Color { Color(red: r, green: g, blue: b) }

    var hexString: String {
        String(format: "#%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }

    func scaled(by factor: Double) -> RGB {
        RGB(r: min(1, r * factor), g: min(1, g * factor), b: min(1, b * factor))
    }

    /// Linear interpolation toward `other`; amounts past 1 extrapolate, clamped per channel.
    func interpolated(to other: RGB, amount: Double) -> RGB {
        func lerp(_ a: Double, _ b: Double) -> Double { min(1, max(0, a + (b - a) * amount)) }
        return RGB(r: lerp(r, other.r), g: lerp(g, other.g), b: lerp(b, other.b))
    }
}

extension ColorTheme {
    /// A version of this theme re-derived for the other appearance: the canvas becomes a
    /// near-white (or near-black) surface tinted by the original, and any accent without
    /// enough contrast against the new canvas is rescaled toward readability. Judgement is
    /// based on the actual colors, so it also repairs a theme registered under the wrong
    /// appearance.
    @MainActor func converted(toDark: Bool) -> ColorTheme {
        let top = RGB(canvasTop)
        let newTop = toDark
            ? RGB(r: 0.07, g: 0.08, b: 0.11).interpolated(to: top, amount: 0.10)
            : RGB(r: 1, g: 1, b: 1).interpolated(to: top, amount: 0.05)
        let newBottom = newTop.scaled(by: toDark ? 0.72 : 0.96)

        func adapt(_ color: Color) -> Color {
            let rgb = RGB(color)
            let luminance = rgb.luminance
            if toDark {
                guard luminance > 0, luminance < 0.35 else { return color }
                return rgb.scaled(by: 0.45 / luminance).color
            } else {
                guard luminance > 0.55 else { return color }
                return rgb.scaled(by: 0.55 / luminance).color
            }
        }

        return ColorTheme(
            id: ThemeFile.customID(name: name, isDark: toDark),
            name: name, isDark: toDark,
            canvasTop: newTop.color, canvasBottom: newBottom.color,
            added: adapt(added), removed: adapt(removed), modified: adapt(modified),
            conflict: adapt(conflict), brand: adapt(brand), brandAlt: adapt(brandAlt),
            badgeForeground: toDark ? RGB(r: 0.05, g: 0.05, b: 0.07).color
                                    : RGB(r: 0.99, g: 0.99, b: 1.00).color,
            isCustom: true)
    }
}

extension ThemeFile {
    /// A complete file for an existing theme — the template users edit and re-import.
    @MainActor init(_ theme: ColorTheme) {
        name = theme.name
        appearance = theme.isDark ? "dark" : "light"
        background = RGB(theme.canvasTop).hexString
        canvasTop = nil
        canvasBottom = RGB(theme.canvasBottom).hexString
        added = RGB(theme.added).hexString
        removed = RGB(theme.removed).hexString
        modified = RGB(theme.modified).hexString
        conflict = RGB(theme.conflict).hexString
        brand = RGB(theme.brand).hexString
        brandAlt = RGB(theme.brandAlt).hexString
        badgeForeground = RGB(theme.badgeForeground).hexString
    }
}
