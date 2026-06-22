import Foundation
import Observation

/// A git repository the user has opened, shown persistently in the sidebar.
struct RecentProject: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var path: String
    var lastOpened: Date

    var url: URL { URL(fileURLWithPath: path) }
    var parentPath: String { (path as NSString).deletingLastPathComponent }
}

/// Persists the list of opened repositories (most-recent first) to Application Support.
@Observable
final class RecentProjectsStore {
    private(set) var projects: [RecentProject] = []
    private let fileURL: URL
    private let limit = 16

    init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = support.appendingPathComponent("Differentialis", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("recent-projects.json")
        load()
    }

    func record(name: String, url: URL) {
        let path = url.standardizedFileURL.path
        projects.removeAll { $0.path == path }
        projects.insert(RecentProject(name: name, path: path, lastOpened: Date()), at: 0)
        if projects.count > limit { projects = Array(projects.prefix(limit)) }
        persist()
    }

    func remove(_ project: RecentProject) {
        projects.removeAll { $0.id == project.id }
        persist()
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([RecentProject].self, from: data) else { return }
        // Drop entries whose folder no longer exists or is no longer a repo.
        projects = decoded.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(projects) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
