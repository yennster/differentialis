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

    /// Best-effort content classification. This is called from `Comparison.mode(for:)` inside
    /// SwiftUI view bodies, so it MUST stay cheap and MUST NOT shell out to git: a synchronous
    /// `Process.waitUntilExit` re-enters the SwiftUI update loop and crashes (see GitChangeset).
    /// It therefore decides from the extension first, and only sniffs a bounded prefix of on-disk
    /// sources — never the whole file, never an NSImage decode, never a git subprocess.
    var kind: ContentKind {
        if isDirectory { return .folder }
        if let ext = fileExtension, let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .text) || type.conforms(to: .sourceCode) || type.conforms(to: .plainText) {
                return .text
            }
        }
        // Cheap byte sniff for on-disk sources only (git blobs would require a subprocess, so they
        // default to text). Reads at most 4 KB, so it can't beachball on a huge file.
        if let sample = sniffPrefix() {
            if sample.isEmpty { return .text }
            if sample.contains(0) { return .binary }              // NUL byte ⇒ binary
            return String(data: sample, encoding: .utf8) != nil ? .text : .binary
        }
        return .text
    }

    /// The on-disk URL backing this source, if any (nil for git blobs, in-memory text, empty).
    private var onDiskURL: URL? {
        switch self {
        case .file(let url): return url
        case .workingCopy(let repo, let path): return repo.appendingPathComponent(path)
        default: return nil
        }
    }

    /// Reads a bounded prefix for text/binary sniffing without loading the whole file.
    private func sniffPrefix(_ limit: Int = 4096) -> Data? {
        guard let url = onDiskURL, let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: limit)) ?? Data()
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
        Self.decodeText(try loadData())
    }

    /// Decodes text with BOM/UTF-16 detection so UTF-16 and BOM-prefixed files don't render as
    /// mojibake. Latin-1 is the last resort because it round-trips any byte (never fails), which is
    /// why it must come after the real candidates rather than swallowing them.
    static func decodeText(_ data: Data) -> String {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {              // UTF-8 BOM
            return String(decoding: data.dropFirst(3), as: UTF8.self)
        }
        if data.starts(with: [0xFF, 0xFE]),                     // UTF-16 LE BOM
           let s = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) { return s }
        if data.starts(with: [0xFE, 0xFF]),                     // UTF-16 BE BOM
           let s = String(data: data.dropFirst(2), encoding: .utf16BigEndian) { return s }
        if let s = String(data: data, encoding: .utf8) { return s }
        // No BOM but lots of NULs ⇒ likely UTF-16 without a BOM.
        let sample = data.prefix(4096)
        let nulCount = sample.reduce(0) { $0 + ($1 == 0 ? 1 : 0) }
        if nulCount > sample.count / 4 {
            if let s = String(data: data, encoding: .utf16LittleEndian) { return s }
            if let s = String(data: data, encoding: .utf16BigEndian) { return s }
        }
        return String(data: data, encoding: .isoLatin1) ?? String(decoding: data, as: UTF8.self)
    }

    func loadImage() -> NSImage? {
        guard let data = try? loadData() else { return nil }
        return NSImage(data: data)
    }
}
