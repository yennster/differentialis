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

@Suite("Content kind sniffing")
struct ContentKindSniffTests {
    /// Writes `data` to a temp file with no extension, so `kind` has to sniff the bytes.
    private func kind(of data: Data) throws -> ComparisonSource.ContentKind {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DifferentialisSniff-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        return ComparisonSource.file(url).kind
    }

    @Test("a multi-byte character straddling the sniff limit is still text")
    func multiByteAcrossBoundary() throws {
        // 4095 ASCII bytes then a 3-byte character: the 4096-byte prefix ends after its lead byte.
        let cut1 = Data(String(repeating: "a", count: 4095).utf8) + Data("日本語のテキスト\n".utf8)
        #expect(try kind(of: cut1) == .text)
        // 4094 ASCII bytes: the prefix ends after the lead byte and one continuation byte.
        let cut2 = Data(String(repeating: "a", count: 4094).utf8) + Data("日本語のテキスト\n".utf8)
        #expect(try kind(of: cut2) == .text)
        // A 4-byte emoji cut after three of its bytes.
        let cut3 = Data(String(repeating: "a", count: 4093).utf8) + Data("🙂 done\n".utf8)
        #expect(try kind(of: cut3) == .text)
        // Japanese-only text well over the limit, whatever the alignment.
        let japanese = Data(String(repeating: "こんにちは世界。", count: 300).utf8)
        #expect(try kind(of: japanese) == .text)
    }

    @Test("UTF-16 with a BOM is text despite its NUL bytes")
    func utf16WithBOM() throws {
        let text = String(repeating: "hello world\n", count: 50)
        let le = Data([0xFF, 0xFE]) + text.data(using: .utf16LittleEndian)!
        let be = Data([0xFE, 0xFF]) + text.data(using: .utf16BigEndian)!
        #expect(try kind(of: le) == .text)
        #expect(try kind(of: be) == .text)
        #expect(try kind(of: Data([0xEF, 0xBB, 0xBF]) + Data("hi\n".utf8)) == .text)
    }

    @Test("Latin-1 text without NULs is text")
    func latin1() throws {
        let latin1 = "Café crème, naïve façade, señor.\n".data(using: .isoLatin1)!
        #expect(String(data: latin1, encoding: .utf8) == nil)
        #expect(try kind(of: latin1) == .text)
    }

    @Test("real binary data is still binary")
    func binary() throws {
        var withNUL = Data("PK".utf8)
        withNUL.append(contentsOf: [0x03, 0x04, 0x14, 0x00, 0x00, 0x00, 0x08, 0x00])
        withNUL.append(contentsOf: (0..<5000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        #expect(try kind(of: withNUL) == .binary)
        // No NULs, not UTF-8, and full of control bytes.
        let packed = Data((0..<4096).map { UInt8(1 + ($0 &* 37) % 255) })
        #expect(try kind(of: packed) == .binary)
    }

    @Test("an invalid sequence that isn't at the boundary is not trimmed away")
    func trimOnlyIncompleteTail() {
        let complete = Data("ab日".utf8)
        #expect(ComparisonSource.trimmingIncompleteUTF8Tail(complete) == complete)
        #expect(ComparisonSource.trimmingIncompleteUTF8Tail(complete.dropLast()) == Data("ab".utf8))
        #expect(ComparisonSource.trimmingIncompleteUTF8Tail(complete.dropLast(2)) == Data("ab".utf8))
        let ascii = Data("plain".utf8)
        #expect(ComparisonSource.trimmingIncompleteUTF8Tail(ascii) == ascii)
    }
}
