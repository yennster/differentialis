import SwiftUI

/// Foreground colors for syntax tokens. Every `ColorTheme` resolves to one: built-in themes
/// carry their own, imported themes may (JSON `syntax` object, `.tmTheme` scopes), and anything
/// else uses the default for its appearance. Change tints are backgrounds, so these sit on top
/// of added/removed/modified rows without competing with them.
struct SyntaxPalette: Hashable {
    var keyword: Color
    var type: Color
    var string: Color
    var number: Color
    var comment: Color
    var literal: Color
    var attribute: Color
    var property: Color
    var heading: Color

    func color(for kind: SyntaxTokenKind) -> Color {
        switch kind {
        case .keyword: return keyword
        case .type: return type
        case .string: return string
        case .number: return number
        case .comment: return comment
        case .literal: return literal
        case .attribute: return attribute
        case .property: return property
        case .heading: return heading
        }
    }

    /// A palette from `#RRGGBB` strings in `SyntaxTokenKind` order — for the built-in tables.
    init(hex keyword: String, _ type: String, _ string: String, _ number: String,
         _ comment: String, _ literal: String, _ attribute: String, _ property: String,
         _ heading: String) {
        func color(_ hex: String) -> Color { (RGB(hex: hex) ?? RGB(r: 0.5, g: 0.5, b: 0.5)).color }
        self.init(keyword: color(keyword), type: color(type), string: color(string),
                  number: color(number), comment: color(comment), literal: color(literal),
                  attribute: color(attribute), property: color(property), heading: color(heading))
    }

    init(keyword: Color, type: Color, string: Color, number: Color, comment: Color,
         literal: Color, attribute: Color, property: Color, heading: Color) {
        self.keyword = keyword
        self.type = type
        self.string = string
        self.number = number
        self.comment = comment
        self.literal = literal
        self.attribute = attribute
        self.property = property
        self.heading = heading
    }

    static func defaultPalette(isDark: Bool) -> SyntaxPalette {
        isDark ? defaultDark : defaultLight
    }

    //                                keyword    type       string     number     comment    literal    attribute  property   heading
    static let defaultDark = SyntaxPalette(
        hex: "#D08CF2", "#6FCBE0", "#E3BE7A", "#F0997A", "#7D8595", "#F0997A", "#E6C46E", "#8DB8F5", "#8DB8F5")
    static let defaultLight = SyntaxPalette(
        hex: "#9A2BA6", "#0F6C8A", "#9A5B12", "#B5481C", "#6B7280", "#B5481C", "#7A5A00", "#2457B0", "#2457B0")

    static let mariana = SyntaxPalette(
        hex: "#C695C6", "#5FB4B4", "#99C794", "#F9AE58", "#A6ACB8", "#EC5F66", "#F9AE58", "#6699CC", "#6699CC")
    static let monokai = SyntaxPalette(
        hex: "#F92672", "#66D9EF", "#E6DB74", "#AE81FF", "#88846F", "#AE81FF", "#A6E22E", "#FD971F", "#A6E22E")
    static let oneDark = SyntaxPalette(
        hex: "#C678DD", "#E5C07B", "#98C379", "#D19A66", "#7F848E", "#D19A66", "#61AFEF", "#E06C75", "#E06C75")
    static let solarizedDark = SyntaxPalette(
        hex: "#859900", "#B58900", "#2AA198", "#D33682", "#6E8A92", "#CB4B16", "#6C71C4", "#268BD2", "#268BD2")
    static let solarizedLight = SyntaxPalette(
        hex: "#859900", "#B58900", "#2AA198", "#D33682", "#93A1A1", "#CB4B16", "#6C71C4", "#268BD2", "#268BD2")
    static let gitHubLight = SyntaxPalette(
        hex: "#CF222E", "#953800", "#0A3069", "#0550AE", "#6E7781", "#0550AE", "#8250DF", "#0550AE", "#0550AE")
}

/// The JSON form of a `SyntaxPalette` inside a theme file: every key optional, missing keys
/// fall back to the default palette for the theme's appearance.
struct SyntaxColorsFile: Codable, Equatable {
    var keyword: String?
    var type: String?
    var string: String?
    var number: String?
    var comment: String?
    var literal: String?
    var attribute: String?
    var property: String?
    var heading: String?

    init(keyword: String? = nil, type: String? = nil, string: String? = nil,
         number: String? = nil, comment: String? = nil, literal: String? = nil,
         attribute: String? = nil, property: String? = nil, heading: String? = nil) {
        self.keyword = keyword
        self.type = type
        self.string = string
        self.number = number
        self.comment = comment
        self.literal = literal
        self.attribute = attribute
        self.property = property
        self.heading = heading
    }

    @MainActor init(_ palette: SyntaxPalette) {
        func hexString(_ color: Color) -> String { RGB(color).hexString }
        self.init(keyword: hexString(palette.keyword), type: hexString(palette.type),
                  string: hexString(palette.string), number: hexString(palette.number),
                  comment: hexString(palette.comment), literal: hexString(palette.literal),
                  attribute: hexString(palette.attribute), property: hexString(palette.property),
                  heading: hexString(palette.heading))
    }

    /// The hex string stored for `kind`, if any.
    func hex(for kind: SyntaxTokenKind) -> String? {
        switch kind {
        case .keyword: return keyword
        case .type: return type
        case .string: return string
        case .number: return number
        case .comment: return comment
        case .literal: return literal
        case .attribute: return attribute
        case .property: return property
        case .heading: return heading
        }
    }

    /// Resolves to a palette, or reports the first unreadable color as `syntax.<kind>`.
    func palette(fallback: SyntaxPalette) throws -> SyntaxPalette {
        func color(_ kind: SyntaxTokenKind) throws -> Color {
            guard let value = hex(for: kind) else { return fallback.color(for: kind) }
            guard let rgb = RGB(hex: value) else {
                throw ThemeFile.ThemeFileError.badColor(key: "syntax.\(kind.rawValue)", value: value)
            }
            return rgb.color
        }
        return SyntaxPalette(
            keyword: try color(.keyword), type: try color(.type), string: try color(.string),
            number: try color(.number), comment: try color(.comment), literal: try color(.literal),
            attribute: try color(.attribute), property: try color(.property),
            heading: try color(.heading))
    }
}
