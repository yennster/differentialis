import Foundation
import SwiftUI

/// Imports Sublime Text / TextMate `.tmTheme` color schemes (XML plists, as distributed by
/// colorsublime.github.io) by mapping their colors onto Differentialis' semantic slots.
///
/// The global `background` becomes the canvas and decides light vs dark. Diff colors prefer
/// the theme's own `markup.inserted` / `markup.deleted` / `markup.changed` scopes; anything
/// missing is filled by hue-matching the theme's saturated scope colors (green → added,
/// red → removed, blue → modified, orange → conflict, purple → accent, cyan → alt accent),
/// falling back to the built-in default theme for that appearance.
enum TmThemeImporter {
    enum TmThemeError: LocalizedError {
        case notAPlist
        case missingBackground

        var errorDescription: String? {
            switch self {
            case .notAPlist:
                return "The file isn't a readable .tmTheme (it should be an XML property list)."
            case .missingBackground:
                return "The .tmTheme has no global background color."
            }
        }
    }

    static func colorTheme(from data: Data, fallbackName: String) throws -> ColorTheme {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let root = plist as? [String: Any],
              let settings = root["settings"] as? [[String: Any]] else {
            throw TmThemeError.notAPlist
        }
        let globals = settings.first { $0["scope"] == nil }?["settings"] as? [String: Any] ?? [:]
        guard let bgHex = globals["background"] as? String, let background = RGB(hex: bgHex) else {
            throw TmThemeError.missingBackground
        }
        let isDark = background.luminance < 0.5
        let name = (root["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName
        let fallback = isDark ? ColorTheme.defaultDark : ColorTheme.defaultLight

        var scoped: [(scope: String, color: RGB)] = []
        for entry in settings {
            guard let scope = entry["scope"] as? String,
                  let entrySettings = entry["settings"] as? [String: Any],
                  let hex = entrySettings["foreground"] as? String,
                  let rgb = RGB(hex: hex) else { continue }
            scoped.append((scope.lowercased(), rgb))
        }

        func scopeColor(containing needle: String) -> RGB? {
            scoped.first { $0.scope.contains(needle) }?.color
        }

        // Hue-match against colors saturated enough to be accents and distinct from the canvas.
        let candidates = scoped.map(\.color).filter {
            $0.saturation > 0.25 && abs($0.luminance - background.luminance) > 0.15
        }
        func hueMatch(_ target: Double, within spread: Double) -> RGB? {
            candidates
                .map { (color: $0, distance: hueDistance($0.hue, target)) }
                .filter { $0.distance < spread }
                .min { $0.distance < $1.distance }?
                .color
        }

        let added = scopeColor(containing: "markup.inserted") ?? hueMatch(120, within: 70)
        let removed = scopeColor(containing: "markup.deleted") ?? hueMatch(0, within: 40)
        let modified = scopeColor(containing: "markup.changed") ?? hueMatch(220, within: 50)
        let conflict = hueMatch(40, within: 25)
        let caret = (globals["caret"] as? String).flatMap(RGB.init(hex:))
        let brand = hueMatch(285, within: 45) ?? caret.flatMap { $0.saturation > 0.25 ? $0 : nil }
        let brandAlt = hueMatch(190, within: 30)

        return ColorTheme(
            id: ThemeFile.customID(name: name, isDark: isDark),
            name: name, isDark: isDark,
            canvasTop: background.color,
            canvasBottom: background.scaled(by: isDark ? 0.72 : 0.94).color,
            added: added?.color ?? fallback.added,
            removed: removed?.color ?? fallback.removed,
            modified: modified?.color ?? fallback.modified,
            conflict: conflict?.color ?? fallback.conflict,
            brand: brand?.color ?? fallback.brand,
            brandAlt: brandAlt?.color ?? fallback.brandAlt,
            // Badges carry the theme's bright accents in dark themes (dark text keeps them
            // legible) and darker accents in light themes (white text does the same).
            badgeForeground: isDark ? background.scaled(by: 0.55).color : RGB(r: 1, g: 1, b: 1).color,
            isCustom: true)
    }

    private static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }
}

extension RGB {
    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    var saturation: Double {
        let maxC = max(r, g, b)
        guard maxC > 0 else { return 0 }
        return (maxC - min(r, g, b)) / maxC
    }

    /// Hue in degrees (0–360); 0 for grays.
    var hue: Double {
        let maxC = max(r, g, b)
        let delta = maxC - min(r, g, b)
        guard delta > 0 else { return 0 }
        let h: Double
        switch maxC {
        case r: h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        case g: h = (b - r) / delta + 2
        default: h = (r - g) / delta + 4
        }
        let degrees = h * 60
        return degrees < 0 ? degrees + 360 : degrees
    }
}
