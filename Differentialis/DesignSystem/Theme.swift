import SwiftUI

/// Centralized colors, fonts, and spacing for Differentialis.
enum Theme {
    // Diff semantic colors (tuned to read well over dark glass).
    static let added = Color(red: 0.30, green: 0.82, blue: 0.50)
    static let removed = Color(red: 0.96, green: 0.40, blue: 0.50)
    static let modified = Color(red: 0.42, green: 0.66, blue: 1.00)
    static let conflict = Color(red: 1.00, green: 0.70, blue: 0.28)

    static let addedFill = added.opacity(0.16)
    static let removedFill = removed.opacity(0.16)
    static let modifiedFill = modified.opacity(0.16)
    static let highlightFill = Color.yellow.opacity(0.001) // replaced per-side below

    static let addedHighlight = added.opacity(0.38)
    static let removedHighlight = removed.opacity(0.38)

    static let brand = Color(red: 0.62, green: 0.45, blue: 0.96)
    static let brandAlt = Color(red: 0.36, green: 0.78, blue: 0.98)
    /// Semantic colors are intentionally bright; near-black text keeps their compact badges legible.
    static let badgeForeground = Color(red: 0.035, green: 0.035, blue: 0.055)

    static let codeFont = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let codeFontSize: CGFloat = 12
    static let gutterFont = Font.system(size: 10.5, weight: .regular, design: .monospaced)

    static let canvasTop = Color(red: 0.06, green: 0.07, blue: 0.11)
    static let canvasBottom = Color(red: 0.02, green: 0.02, blue: 0.04)

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
    var tint: Color {
        switch self {
        case .unchanged: return .secondary
        case .takeLeft: return Theme.removed
        case .takeRight: return Theme.modified
        case .takeBoth: return Theme.added
        case .conflict: return Theme.conflict
        }
    }

    var label: String {
        switch self {
        case .unchanged: return "Unchanged"
        case .takeLeft: return "Left"
        case .takeRight: return "Right"
        case .takeBoth: return "Both (same)"
        case .conflict: return "Conflict"
        }
    }
}

extension GitFileStatus {
    var tint: Color {
        switch self {
        case .added, .untracked: return Theme.added
        case .deleted: return Theme.removed
        case .modified, .typeChanged: return Theme.modified
        case .renamed, .copied: return Theme.brandAlt
        case .conflicted: return Theme.conflict
        }
    }
}
