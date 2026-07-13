import SwiftUI
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

struct FileProperty: Identifiable {
    let id = UUID()
    let label: String
    let a: String
    let b: String
    var differs: Bool { a != b }
}

enum FilePropertiesBuilder {
    static let order = ["Name", "Size", "Type", "Modified", "Created",
                        "Permissions", "Dimensions", "Format", "Color Space"]

    static func rows(a: ComparisonSource, b: ComparisonSource) -> [FileProperty] {
        let pa = properties(for: a)
        let pb = properties(for: b)
        return order.compactMap { key in
            let va = pa[key] ?? ""
            let vb = pb[key] ?? ""
            guard !(va.isEmpty && vb.isEmpty) else { return nil }
            return FileProperty(label: key, a: va, b: vb)
        }
    }

    static func properties(for source: ComparisonSource) -> [String: String] {
        var p: [String: String] = [:]

        switch source {
        case .file(let url): p["Name"] = url.lastPathComponent
        case .workingCopy(_, let path), .gitBlob(_, _, let path, _): p["Name"] = (path as NSString).lastPathComponent
        case .text(_, let name), .empty(let name): p["Name"] = name
        }

        let fileURL: URL? = {
            switch source {
            case .file(let url): return url
            case .workingCopy(let repo, let path): return repo.appendingPathComponent(path)
            default: return nil
            }
        }()

        if let ext = source.fileExtension, !ext.isEmpty, let type = UTType(filenameExtension: ext) {
            p["Type"] = type.localizedDescription ?? ext.uppercased()
        }

        if let fileURL, let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path) {
            if let size = attrs[.size] as? NSNumber {
                p["Size"] = formattedSize(size.int64Value)
            }
            let df = DateFormatter()
            df.dateStyle = .short; df.timeStyle = .medium
            if let m = attrs[.modificationDate] as? Date { p["Modified"] = df.string(from: m) }
            if let c = attrs[.creationDate] as? Date { p["Created"] = df.string(from: c) }
            if let mode = attrs[.posixPermissions] as? Int { p["Permissions"] = permissionString(mode) }

            // ImageIO reads image headers from the URL without first materializing a potentially
            // multi-gigabyte file in Data merely to report dimensions and color metadata.
            if let image = imageProperties(url: fileURL) {
                add(image: image, to: &p)
            }
        } else {
            addInMemoryProperties(for: source, to: &p)
        }
        return p
    }

    private static func addInMemoryProperties(for source: ComparisonSource,
                                              to properties: inout [String: String]) {
        // `.empty` represents an absent side of an added/deleted comparison, not a real zero-byte
        // file. Keep its metadata blank so it cannot be mistaken for an existing empty file.
        if case .empty = source { return }

        // Git can report a committed blob's size without transferring the blob into this process.
        if case let .gitBlob(repo, ref, path, _) = source,
           let raw = try? GitRepository(url: repo).run([
               "cat-file", "-s",
               ComparisonSource.isIndexReference(ref) ? ":\(path)" : "\(ref):\(path)",
           ]),
           let size = Int64(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            properties["Size"] = formattedSize(size)
            // Metadata still needs the bytes, but cap that optional work. The comparison itself
            // remains available for large images; the properties popover stays memory-safe.
            if size <= 64 * 1_024 * 1_024,
               let data = try? source.loadData(),
               let image = imageProperties(data: data) {
                add(image: image, to: &properties)
            }
            return
        }

        guard let data = try? source.loadData() else { return }
        properties["Size"] = formattedSize(Int64(data.count))
        if let image = imageProperties(data: data) {
            add(image: image, to: &properties)
        }
    }

    private static func formattedSize(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: count)) (\(count.formatted()) bytes)"
    }

    private static func add(image: (dimensions: String, format: String, colorSpace: String),
                            to properties: inout [String: String]) {
        properties["Dimensions"] = image.dimensions
        properties["Format"] = image.format
        properties["Color Space"] = image.colorSpace
    }

    private static func permissionString(_ mode: Int) -> String {
        let bits: [(Int, String)] = [(0o400, "r"), (0o200, "w"), (0o100, "x"),
                                     (0o040, "r"), (0o020, "w"), (0o010, "x"),
                                     (0o004, "r"), (0o002, "w"), (0o001, "x")]
        return "-" + bits.map { (mode & $0.0) != 0 ? $0.1 : "-" }.joined()
    }

    private static func imageProperties(data: Data) -> (dimensions: String, format: String, colorSpace: String)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return imageProperties(source: source)
    }

    private static func imageProperties(url: URL) -> (dimensions: String, format: String, colorSpace: String)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return imageProperties(source: source)
    }

    private static func imageProperties(source: CGImageSource) -> (dimensions: String, format: String, colorSpace: String)? {
        guard
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let depth = props[kCGImagePropertyDepth] as? Int ?? 8
        let model = props[kCGImagePropertyColorModel] as? String ?? "RGB"
        let hasAlpha = props[kCGImagePropertyHasAlpha] as? Bool ?? false
        let profile = props[kCGImagePropertyProfileName] as? String
        return ("\(w.formatted()) × \(h.formatted()) pixels",
                "\(model)\(hasAlpha ? "A" : "") \(depth)-bit",
                profile ?? "—")
    }
}

/// A two-column comparison of file metadata, shown in a popover. Differing
/// values are highlighted.
struct FilePropertiesView: View {
    let a: ComparisonSource
    let b: ComparisonSource
    @State private var rows: [FileProperty] = []
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            if loaded {
                VStack(spacing: 0) {
                    ForEach(rows) { propertyRow($0) }
                }
                .padding(.vertical, 4)
            } else {
                ProgressView().frame(maxWidth: .infinity).frame(height: 140)
            }
        }
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.canvas)
        .task {
            rows = await Task.detached { FilePropertiesBuilder.rows(a: a, b: b) }.value
            loaded = true
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text("File Properties").font(.system(size: 14, weight: .semibold))
            HStack(spacing: 0) {
                Color.clear.frame(width: 124)
                badge("A", Theme.brand).frame(maxWidth: .infinity, alignment: .leading)
                badge("B", Theme.modified).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 14).padding(.bottom, 12)
        .background(LinearGradient(colors: [Theme.brand.opacity(0.30), .clear],
                                   startPoint: .top, endPoint: .bottom))
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.badgeForeground)
            .frame(width: 22, height: 22)
            .background(color, in: RoundedRectangle(cornerRadius: 5))
    }

    private func propertyRow(_ row: FileProperty) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(row.label).font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(width: 124, alignment: .trailing).padding(.trailing, 14)
            value(row.a, differs: row.differs).frame(maxWidth: .infinity, alignment: .leading)
            value(row.b, differs: row.differs).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 7).padding(.horizontal, 16)
        .overlay(Rectangle().fill(.white.opacity(0.06)).frame(height: 1), alignment: .bottom)
    }

    private func value(_ string: String, differs: Bool) -> some View {
        Text(string.isEmpty ? "—" : string)
            .font(.system(size: 12.5, weight: differs ? .semibold : .regular))
            .foregroundStyle(differs ? Theme.brandAlt : .primary)
            .textSelection(.enabled)
    }
}

/// Toolbar button that reveals the File Properties popover for a comparison.
struct FilePropertiesButton: View {
    let a: ComparisonSource
    let b: ComparisonSource
    @State private var show = false

    var body: some View {
        Button { show.toggle() } label: { Image(systemName: "info.circle") }
            .buttonStyle(.borderless)
            .help("File Properties")
            .popover(isPresented: $show, arrowEdge: .bottom) {
                FilePropertiesView(a: a, b: b)
            }
    }
}
