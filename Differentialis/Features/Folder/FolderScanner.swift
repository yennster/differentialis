import Foundation
import UniformTypeIdentifiers

enum FolderStatus: Hashable, CaseIterable {
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
    var relativePath: String
    var status: FolderStatus
    var isImage: Bool
    var error: String? = nil

    var id: String { relativePath }

    var name: String { (relativePath as NSString).lastPathComponent }
    var directory: String { (relativePath as NSString).deletingLastPathComponent }
}

struct FolderScanResult {
    var entries: [FolderEntry]
    var issues: [String]
}

enum FolderScanner {
    static func scan(a: URL, b: URL) -> [FolderEntry] {
        scanDetailed(a: a, b: b).entries
    }

    static func scanDetailed(a: URL, b: URL) -> FolderScanResult {
        let aInventory = relativeFiles(root: a, side: "A")
        let bInventory = relativeFiles(root: b, side: "B")
        let allPaths = Set(aInventory.files.keys).union(bInventory.files.keys).sorted()

        let entries = allPaths.map { path in
            let inA = aInventory.files[path]
            let inB = bInventory.files[path]
            let status: FolderStatus
            var readError: String?
            switch (inA, inB) {
            case let (lhs?, rhs?):
                do {
                    status = try filesEqual(lhs, rhs) ? .identical : .modified
                } catch {
                    status = .modified
                    readError = "Couldn’t compare \(path): \(error.localizedDescription)"
                }
            case (_?, nil):
                status = .removed
            case (nil, _?):
                status = .added
            case (nil, nil):
                status = .identical
            }
            return FolderEntry(relativePath: path, status: status, isImage: isImage(path), error: readError)
        }
        return FolderScanResult(entries: entries,
                                issues: aInventory.issues + bInventory.issues
                                    + entries.compactMap(\.error))
    }

    private struct Inventory {
        var files: [String: URL] = [:]
        var issues: [String] = []
    }

    private static func relativeFiles(root: URL, side: String) -> Inventory {
        var result: [String: URL] = [:]
        var issues: [String] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey]
        // Show hidden files and package contents. Treating packages as opaque made two folders that
        // differed only inside an app/bundle package appear identical.
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys,
            options: [], errorHandler: { url, error in
                issues.append("Side \(side) · \(url.path): \(error.localizedDescription)")
                return true
            }) else {
            return Inventory(issues: ["Side \(side) couldn’t be read: \(root.path)"])
        }

        let prefix = root.standardizedFileURL.path + "/"
        for case let url as URL in enumerator {
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: Set(keys))
            } catch {
                issues.append("Side \(side) · \(url.path): \(error.localizedDescription)")
                continue
            }
            // Prune the .git directory entirely — walking its object store would swamp the scan.
            if values.isDirectory == true && url.lastPathComponent == ".git" {
                enumerator.skipDescendants()
                continue
            }
            let isRegular = values.isRegularFile == true
            let isSymlink = values.isSymbolicLink == true
            guard isRegular || isSymlink else { continue }
            let full = url.standardizedFileURL.path
            guard full.hasPrefix(prefix) else { continue }
            result[String(full.dropFirst(prefix.count))] = url
        }
        return Inventory(files: result, issues: issues)
    }

    private static func filesEqual(_ a: URL, _ b: URL) throws -> Bool {
        let aLink = try a.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true
        let bLink = try b.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true
        if aLink || bLink {
            // Compare link destinations rather than following the links.
            guard aLink == bLink else { return false }
            let aDest = try FileManager.default.destinationOfSymbolicLink(atPath: a.path)
            let bDest = try FileManager.default.destinationOfSymbolicLink(atPath: b.path)
            return aDest == bDest
        }
        return try contentsEqual(a, b)
    }

    /// Streams both files in 1 MB chunks, bailing at the first mismatch — constant memory and an
    /// early exit, instead of loading each entire file into RAM to hash it.
    private static func contentsEqual(_ a: URL, _ b: URL) throws -> Bool {
        let aSize = try a.resourceValues(forKeys: [.fileSizeKey]).fileSize
        let bSize = try b.resourceValues(forKeys: [.fileSizeKey]).fileSize
        if let aSize, let bSize, aSize != bSize { return false }
        let fa = try FileHandle(forReadingFrom: a)
        let fb = try FileHandle(forReadingFrom: b)
        defer { try? fa.close(); try? fb.close() }
        let chunk = 1 << 20
        while true {
            let da = try fa.read(upToCount: chunk) ?? Data()
            let db = try fb.read(upToCount: chunk) ?? Data()
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
