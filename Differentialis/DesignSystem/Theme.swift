import SwiftUI

/// Centralized colors, fonts, and spacing for Differentialis.
///
/// Every accessor reads through `ThemeManager.shared`, so views that use them
/// re-render automatically when the appearance, color theme, or font size changes.
@MainActor
enum Theme {
    private static var palette: ColorTheme { ThemeManager.shared.activeTheme }

    // Diff semantic colors (tuned per theme to read well over the canvas).
    static var added: Color { palette.added }
    static var removed: Color { palette.removed }
    static var modified: Color { palette.modified }
    static var conflict: Color { palette.conflict }

    static var addedFill: Color { added.opacity(palette.fillOpacity) }
    static var removedFill: Color { removed.opacity(palette.fillOpacity) }
    static var modifiedFill: Color { modified.opacity(palette.fillOpacity) }

    static var addedHighlight: Color { added.opacity(palette.highlightOpacity) }
    static var removedHighlight: Color { removed.opacity(palette.highlightOpacity) }

    // Recessed "well" backgrounds (tracks, panes, chips). A dark canvas can absorb a heavy
    // darkening; over a light canvas the same wash turns the whole surface gray and kills
    // text contrast, so wells fade to a hint of shade there.
    static var well: Color { .black.opacity(palette.isDark ? 0.18 : 0.02) }
    static var wellDeep: Color { .black.opacity(palette.isDark ? 0.22 : 0.035) }
    static var wellStrong: Color { .black.opacity(palette.isDark ? 0.40 : 0.10) }

    static var brand: Color { palette.brand }
    static var brandAlt: Color { palette.brandAlt }
    /// Semantic colors are intentionally saturated; the per-theme badge foreground
    /// keeps their compact badges legible.
    static var badgeForeground: Color { palette.badgeForeground }

    static var codeFontSize: CGFloat { ThemeManager.shared.codeFontSize }
    static var codeFont: Font { monospacedFont(size: codeFontSize) }
    static var gutterFont: Font { monospacedFont(size: max(8, codeFontSize - 1.5)) }

    /// The user's chosen code font family at the given size, or the system mono font.
    private static func monospacedFont(size: CGFloat) -> Font {
        if let name = ThemeManager.shared.codeFontName {
            return .custom(name, fixedSize: size)
        }
        return .system(size: size, weight: .regular, design: .monospaced)
    }
    /// Placeholder height for the absent side of a one-sided diff row — tracks the
    /// code font so both halves keep matching heights at any size (17pt at 12pt).
    static var codeEmptyLineHeight: CGFloat { (17 * codeFontSize / 12).rounded() }

    static var canvasTop: Color { palette.canvasTop }
    /// The theme's bottom color scaled by the user's per-appearance gradient setting:
    /// 0 = flat canvas, 1 = the authored shading, up to 2 = double (extrapolated).
    static var canvasBottom: Color {
        canvasBottom(for: palette, strength: ThemeManager.shared.activeCanvasGradient)
    }

    static func canvasBottom(for theme: ColorTheme, strength: Double) -> Color {
        RGB(theme.canvasTop).interpolated(to: RGB(theme.canvasBottom), amount: strength).color
    }

    static var canvas: LinearGradient {
        LinearGradient(colors: [canvasTop, canvasBottom], startPoint: .top, endPoint: .bottom)
    }

    static func color(for kind: DiffRow.Kind) -> Color {
        switch kind {
        case .equal: return .clear
        case .inserted: return added
        case .deleted: return removed
        case .modified: return modified
        }
    }

    static func fill(for kind: DiffRow.Kind) -> Color {
        switch kind {
        case .equal: return .clear
        case .inserted: return addedFill
        case .deleted: return removedFill
        case .modified: return modifiedFill
        }
    }
}

extension MergeResolution {
    @MainActor var tint: Color {
        switch self {
        case .unchanged: return .secondary
        case .takeLeft: return Theme.removed
        case .takeRight: return Theme.modified
        case .takeBoth: return Theme.added
        case .takeBase: return .secondary
        case .conflict: return Theme.conflict
        }
    }

    var label: String {
        switch self {
        case .unchanged: return "Unchanged"
        case .takeLeft: return "Left"
        case .takeRight: return "Right"
        case .takeBoth: return "Both"
        case .takeBase: return "Base"
        case .conflict: return "Conflict"
        }
    }
}

extension GitFileStatus {
    @MainActor var tint: Color {
        switch self {
        case .added, .untracked: return Theme.added
        case .deleted: return Theme.removed
        case .modified, .typeChanged: return Theme.modified
        case .renamed, .copied: return Theme.brandAlt
        case .conflicted: return Theme.conflict
        }
    }
}
