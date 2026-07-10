import Foundation
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
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey]
        // Show hidden files (dotfiles like .gitignore/.env are exactly what people diff); keep
        // package descendants opaque so an .app bundle isn't exploded into thousands of rows.
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]) else { return result }

        let prefix = root.standardizedFileURL.path + "/"
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey])
            // Prune the .git directory entirely — walking its object store would swamp the scan.
            if values?.isDirectory == true && url.lastPathComponent == ".git" {
                enumerator.skipDescendants()
                continue
            }
            let isRegular = values?.isRegularFile == true
            let isSymlink = values?.isSymbolicLink == true
            guard isRegular || isSymlink else { continue }
            let full = url.standardizedFileURL.path
            guard full.hasPrefix(prefix) else { continue }
            result[String(full.dropFirst(prefix.count))] = url
        }
        return result
    }

    private static func filesEqual(_ a: URL, _ b: URL) -> Bool {
        let aLink = (try? a.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
        let bLink = (try? b.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
        if aLink || bLink {
            // Compare link destinations rather than following the links.
            guard aLink == bLink else { return false }
            let aDest = try? FileManager.default.destinationOfSymbolicLink(atPath: a.path)
            let bDest = try? FileManager.default.destinationOfSymbolicLink(atPath: b.path)
            return aDest == bDest
        }
        return contentsEqual(a, b)
    }

    /// Streams both files in 1 MB chunks, bailing at the first mismatch — constant memory and an
    /// early exit, instead of loading each entire file into RAM to hash it.
    private static func contentsEqual(_ a: URL, _ b: URL) -> Bool {
        let aSize = (try? a.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        let bSize = (try? b.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        if let aSize, let bSize, aSize != bSize { return false }
        guard let fa = try? FileHandle(forReadingFrom: a),
              let fb = try? FileHandle(forReadingFrom: b) else { return false }
        defer { try? fa.close(); try? fb.close() }
        let chunk = 1 << 20
        while true {
            let da = (try? fa.read(upToCount: chunk)) ?? Data()
            let db = (try? fb.read(upToCount: chunk)) ?? Data()
            if da != db { return false }
            if da.isEmpty { return true }   // both reached EOF together with all chunks equal
        }
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
