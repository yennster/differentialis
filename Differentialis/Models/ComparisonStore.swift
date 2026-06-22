import Foundation
import Observation

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
        guard let index = saved.firstIndex(where: { $0.id == comparison.id }) else { return }
        saved[index].name = name
        persist()
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([SavedComparison].self, from: data) else { return }
        saved = decoded
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(saved) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
