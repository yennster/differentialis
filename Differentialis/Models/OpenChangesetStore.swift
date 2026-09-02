import Foundation
import Observation

/// The persistable definition of an open changeset: enough to re-resolve the file list
/// against its repository on the next launch.
struct PersistedChangeset: Codable, Hashable {
    var title: String
    var subtitle: String
    var repoPath: String
    var a: CustomSide
    var b: CustomSide
}

/// Persists the currently open changesets to Application Support so they survive a
/// relaunch; `AppModel.restoreOpenChangesets()` re-resolves them at startup.
@Observable
final class OpenChangesetStore {
    private(set) var items: [PersistedChangeset] = []
    private let fileURL: URL

    init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = support.appendingPathComponent("Differentialis", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("open-changesets.json")
        load()
    }

    func replace(with items: [PersistedChangeset]) {
        self.items = items
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        // Element-tolerant like the other stores: one malformed entry becomes nil instead of
        // throwing away the whole list; a wholly-corrupt file is quarantined, not overwritten.
        if let decoded = try? JSONDecoder().decode([LenientDecodable<PersistedChangeset>].self, from: data) {
            items = decoded.compactMap(\.value)
        } else {
            let backup = fileURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
