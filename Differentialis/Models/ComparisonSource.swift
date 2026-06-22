import Foundation
import AppKit
import UniformTypeIdentifiers

/// Where one side of a comparison gets its bytes from.
enum ComparisonSource: Hashable {
    case file(URL)
    case text(content: String, name: String)
    case gitBlob(repo: URL, ref: String, path: String, label: String)
    case workingCopy(repo: URL, path: String)
    case empty(name: String)

    enum ContentKind { case text, image, folder, binary }

    var displayName: String {
        switch self {
        case .file(let url): return url.lastPathComponent
        case .text(_, let name): return name
        case .gitBlob(_, _, let path, let label): return "\((path as NSString).lastPathComponent) — \(label)"
        case .workingCopy(_, let path): return "\((path as NSString).lastPathComponent) — Working Copy"
        case .empty(let name): return name
        }
    }

    /// A short subtitle for path bars / shelves.
    var subtitle: String {
        switch self {
        case .file(let url): return url.deletingLastPathComponent().path
        case .text: return "In-memory text"
        case .gitBlob(_, let ref, let path, _): return "\(ref):\(path)"
        case .workingCopy(_, let path): return path
        case .empty: return ""
        }
    }

    var fileExtension: String? {
        switch self {
        case .file(let url): return url.pathExtension.lowercased()
        case .gitBlob(_, _, let path, _), .workingCopy(_, let path):
            return (path as NSString).pathExtension.lowercased()
        case .text, .empty: return nil
        }
    }

    var isDirectory: Bool {
        if case .file(let url) = self {
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
        return false
    }

    var kind: ContentKind {
        if isDirectory { return .folder }
        if let ext = fileExtension, let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .text) || type.conforms(to: .sourceCode) || type.conforms(to: .plainText) {
                return .text
            }
        }
        // Fall back to sniffing bytes.
        if let data = try? loadData() {
            if NSImage(data: data) != nil, fileExtension != nil { return .image }
            if looksLikeText(data) { return .text }
            return .binary
        }
        return .text
    }

    func loadData() throws -> Data {
        switch self {
        case .file(let url): return try Data(contentsOf: url)
        case .text(let content, _): return Data(content.utf8)
        case .gitBlob(let repo, let ref, let path, _):
            return try GitRepository(url: repo).blobData(ref: ref, path: path)
        case .workingCopy(let repo, let path):
            return try Data(contentsOf: repo.appendingPathComponent(path))
        case .empty: return Data()
        }
    }

    func loadText() throws -> String {
        let data = try loadData()
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(decoding: data, as: UTF8.self)
    }

    func loadImage() -> NSImage? {
        guard let data = try? loadData() else { return nil }
        return NSImage(data: data)
    }

    private func looksLikeText(_ data: Data) -> Bool {
        guard !data.isEmpty else { return true }
        let sample = data.prefix(4096)
        if sample.contains(0) { return false }
        return String(data: sample, encoding: .utf8) != nil
    }
}
