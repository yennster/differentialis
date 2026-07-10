import Foundation

/// A single open comparison tab.
struct Comparison: Identifiable, Hashable {
    enum Mode: Hashable { case text, image, folder, merge, binary }

    let id = UUID()
    var mode: Mode
    var title: String
    var a: ComparisonSource
    var b: ComparisonSource
    var base: ComparisonSource?   // only for `.merge`

    var symbol: String {
        switch mode {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .folder: return "folder"
        case .merge: return "arrow.triangle.merge"
        case .binary: return "doc"
        }
    }

    /// Auto-detect the best comparison mode from two sources.
    static func mode(for a: ComparisonSource, _ b: ComparisonSource) -> Mode {
        if a.isDirectory || b.isDirectory { return .folder }
        if a.kind == .image || b.kind == .image { return .image }
        if a.kind == .binary || b.kind == .binary { return .binary }
        return .text
    }

    static func make(a: ComparisonSource, b: ComparisonSource, title: String? = nil) -> Comparison {
        let mode = mode(for: a, b)
        let resolvedTitle = title ?? "\(a.displayName) ↔ \(b.displayName)"
        return Comparison(mode: mode, title: resolvedTitle, a: a, b: b, base: nil)
    }

    static func merge(base: ComparisonSource, left: ComparisonSource, right: ComparisonSource,
                      title: String? = nil) -> Comparison {
        Comparison(mode: .merge,
                   title: title ?? "Merge: \(left.displayName)",
                   a: left, b: right, base: base)
    }
}
