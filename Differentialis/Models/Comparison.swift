import Foundation

/// A single open comparison tab.
struct Comparison: Identifiable, Hashable {
    enum Mode: Hashable { case text, image, folder, merge, binary, pasted }

    let id = UUID()
    var mode: Mode
    var title: String
    var a: ComparisonSource
    var b: ComparisonSource
    var base: ComparisonSource?   // only for `.merge`
    var pasted: PastedTextDocument?   // only for `.pasted`

    var symbol: String {
        switch mode {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .folder: return "folder"
        case .merge: return "arrow.triangle.merge"
        case .binary: return "doc"
        case .pasted: return "doc.on.clipboard"
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

    /// A comparison of two texts typed or pasted straight into the app — no files involved.
    static func pasted(title: String, document: PastedTextDocument = PastedTextDocument()) -> Comparison {
        Comparison(mode: .pasted, title: title,
                   a: .text(content: "", name: "Original"),
                   b: .text(content: "", name: "Modified"),
                   base: nil, pasted: document)
    }
}
