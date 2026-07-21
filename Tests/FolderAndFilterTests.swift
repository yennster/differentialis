import Testing
import Foundation
@testable import Differentialis

@Suite("Folder scanning")
struct FolderScannerTests {
    @Test("package descendants participate in comparisons")
    func packageContentsAreCompared() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DifferentialisFolderTests-\(UUID().uuidString)")
        let a = root.appendingPathComponent("A")
        let b = root.appendingPathComponent("B")
        defer { try? FileManager.default.removeItem(at: root) }

        let relative = "Example.app/Contents/config.txt"
        try FileManager.default.createDirectory(
            at: a.appendingPathComponent(relative).deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: b.appendingPathComponent(relative).deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data("left".utf8).write(to: a.appendingPathComponent(relative))
        try Data("right".utf8).write(to: b.appendingPathComponent(relative))

        let result = FolderScanner.scanDetailed(a: a, b: b)
        #expect(result.issues.isEmpty)
        #expect(result.entries.count == 1)
        #expect(result.entries.first?.relativePath == relative)
        #expect(result.entries.first?.status == .modified)
    }

    @Test("an unreadable root is reported instead of appearing identical")
    func missingRootIsAnIssue() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DifferentialisFolderTests-\(UUID().uuidString)")
        let missing = root.appendingPathComponent("missing")
        let present = root.appendingPathComponent("present")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: present, withIntermediateDirectories: true)

        let result = FolderScanner.scanDetailed(a: missing, b: present)
        #expect(result.entries.isEmpty)
        #expect(!result.issues.isEmpty)
    }

    @Test("entry identity remains stable across refreshes")
    func stableIdentity() {
        let first = FolderEntry(relativePath: "Sources/App.swift", status: .modified, isImage: false)
        let second = FolderEntry(relativePath: "Sources/App.swift", status: .modified, isImage: false)
        #expect(first.id == second.id)
    }
}

@Suite("Changeset filtering")
struct GitFileFilterTests {
    private let files = [
        GitChangedFile(path: "Sources/App.swift", oldPath: nil, status: .modified),
        GitChangedFile(path: "Resources/Icon.png", oldPath: nil, status: .added),
        GitChangedFile(path: "README", oldPath: nil, status: .deleted),
    ]

    @Test("filters compose across path, type, and status")
    func combinedFilters() {
        var filter = GitFileFilter(query: "sources", status: .modified, fileExtension: "swift")
        #expect(filter.apply(to: files).map(\.path) == ["Sources/App.swift"])

        filter.query = ""
        filter.status = nil
        filter.fileExtension = ""
        #expect(filter.apply(to: files).map(\.path) == ["README"])
    }

    @Test("reset restores the complete list")
    func reset() {
        var filter = GitFileFilter(query: "icon", status: .added, fileExtension: "png")
        filter.reset()
        #expect(!filter.isActive)
        #expect(filter.apply(to: files) == files)
    }
}

@Suite("File properties")
struct FilePropertiesTests {
    @Test("zero-byte files still report their size")
    func emptyFileSize() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DifferentialisEmpty-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data().write(to: url)

        let properties = FilePropertiesBuilder.properties(for: .file(url))
        #expect(properties["Size"]?.contains("0 bytes") == true)
    }

    @Test("an absent comparison side is not reported as a zero-byte file")
    func absentSideHasNoSize() {
        let properties = FilePropertiesBuilder.properties(for: .empty(name: "missing.txt"))
        #expect(properties["Size"] == nil)
    }
}
