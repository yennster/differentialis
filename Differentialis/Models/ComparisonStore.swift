import Foundation
import Observation

/// Decodes an element as `T?` — a failed decode yields nil instead of throwing, so one corrupt
/// entry can't take down an entire persisted array.
struct LenientDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// Persists saved custom comparisons to JSON under Application Support.
@Observable
final class ComparisonStore {
    private(set) var saved: [SavedComparison] = []
    private let fileURL: URL

    init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = support.appendingPathComponent("Differentialis", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("saved-comparisons.json")
        load()
    }

    func add(_ comparison: SavedComparison) {
        saved.removeAll { $0.id == comparison.id }
        saved.insert(comparison, at: 0)
        persist()
    }

    func remove(_ comparison: SavedComparison) {
        saved.removeAll { $0.id == comparison.id }
        persist()
    }

    func rename(_ comparison: SavedComparison, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = saved.firstIndex(where: { $0.id == comparison.id }) else { return }
        saved[index].name = trimmed
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Decode element-tolerantly: one malformed entry becomes nil instead of throwing and
        // wiping every saved comparison. If the whole file is unparseable, move it aside rather
        // than letting the next persist() silently overwrite recoverable data.
        if let decoded = try? decoder.decode([LenientDecodable<SavedComparison>].self, from: data) {
            saved = decoded.compactMap(\.value)
        } else {
            let backup = fileURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(saved) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
