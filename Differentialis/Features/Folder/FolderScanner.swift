import Foundation
import CryptoKit
import UniformTypeIdentifiers

enum FolderStatus: Hashable {
    case identical, modified, added, removed

    var label: String {
        switch self {
        case .identical: return "Identical"
        case .modified: return "Modified"
        case .added: return "Added"
        case .removed: return "Removed"
        }
    }
    var isChange: Bool { self != .identical }
}

struct FolderEntry: Identifiable, Hashable {
    let id = UUID()
    var relativePath: String
    var status: FolderStatus
    var isImage: Bool

    var name: String { (relativePath as NSString).lastPathComponent }
    var directory: String { (relativePath as NSString).deletingLastPathComponent }
}

enum FolderScanner {
    static func scan(a: URL, b: URL) -> [FolderEntry] {
        let aFiles = relativeFiles(root: a)
        let bFiles = relativeFiles(root: b)
        let allPaths = Set(aFiles.keys).union(bFiles.keys).sorted()

        return allPaths.map { path in
            let inA = aFiles[path]
            let inB = bFiles[path]
            let status: FolderStatus
            switch (inA, inB) {
            case let (lhs?, rhs?):
                status = filesEqual(lhs, rhs) ? .identical : .modified
            case (_?, nil):
                status = .removed
            case (nil, _?):
                status = .added
            case (nil, nil):
                status = .identical
            }
            return FolderEntry(relativePath: path, status: status, isImage: isImage(path))
        }
    }

    private static func relativeFiles(root: URL) -> [String: URL] {
        var result: [String: URL] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return result }

        let prefix = root.standardizedFileURL.path + "/"
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let full = url.standardizedFileURL.path
            guard full.hasPrefix(prefix) else { continue }
            result[String(full.dropFirst(prefix.count))] = url
        }
        return result
    }

    private static func filesEqual(_ a: URL, _ b: URL) -> Bool {
        let aSize = (try? a.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        let bSize = (try? b.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        if let aSize, let bSize, aSize != bSize { return false }
        guard let aData = try? Data(contentsOf: a), let bData = try? Data(contentsOf: b) else { return false }
        return SHA256.hash(data: aData) == SHA256.hash(data: bData)
    }

    private static func isImage(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return UTType(filenameExtension: ext)?.conforms(to: .image) ?? false
    }
}

extension FolderStatus {
    var letter: String {
        switch self {
        case .identical: return "="
        case .modified: return "M"
        case .added: return "A"
        case .removed: return "D"
        }
    }
}
