import SwiftUI
import CryptoKit

/// Shown when at least one side isn't text or an image. Rather than line-diffing binary bytes into
/// garbage, it reports each side's size and SHA-256 and a simple equal/different verdict.
struct BinaryComparisonView: View {
    let a: ComparisonSource
    let b: ComparisonSource

    private struct SideInfo: Equatable {
        var size: Int64
        var sha: String
        var readable: Bool
    }
    private struct Result: Equatable {
        var a: SideInfo
        var b: SideInfo
        var identical: Bool
        var comparable: Bool { a.readable && b.readable }
    }

    @State private var result: Result?
    @State private var loadRequest: UUID?

    private var taskKey: String {
        "\(a.displayName)|\(a.subtitle)|\(b.displayName)|\(b.subtitle)"
    }

    var body: some View {
        VStack(spacing: 0) {
            PathBar(a: a, b: b) {
                if let result {
                    StatChip(text: result.comparable ? (result.identical ? "Identical" : "Different") : "Unavailable",
                             color: result.comparable ? (result.identical ? Theme.added : Theme.modified) : Theme.conflict,
                             systemImage: result.comparable
                                ? (result.identical ? "checkmark.seal.fill" : "not.equal")
                                : "exclamationmark.triangle.fill")
                }
            }
            Divider().opacity(0.4)
            content
        }
        .task(id: taskKey) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let result {
            VStack(spacing: 18) {
                Image(systemName: !result.comparable ? "exclamationmark.triangle" : (result.identical ? "checkmark.seal.fill" : "doc.on.doc"))
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(!result.comparable ? Theme.conflict : (result.identical ? Theme.added : Theme.modified))
                Text(!result.comparable
                     ? "One or both binary files couldn’t be read."
                     : (result.identical ? "These binary files are identical." : "These binary files differ."))
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: 0) {
                    sideCard("A", result.a, accent: Theme.removed)
                    sideCard("B", result.b, accent: Theme.modified)
                }
                .frame(maxWidth: 620)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func sideCard(_ label: String, _ info: SideInfo, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.badgeForeground)
                .frame(width: 22, height: 22)
                .background(accent, in: RoundedRectangle(cornerRadius: 5))
            if info.readable {
                Text(ByteCountFormatter.string(fromByteCount: info.size, countStyle: .file))
                    .font(.system(size: 13, weight: .semibold))
                Text(info.sha)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
            } else {
                Text("Couldn’t read").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 14)
        .padding(8)
    }

    private func load() async {
        let request = UUID()
        loadRequest = request
        result = nil
        let a = a, b = b
        let key = taskKey
        let loaded = await offMain {
            func info(_ source: ComparisonSource) -> SideInfo {
                do {
                    if let url = localURL(for: source) {
                        let handle = try FileHandle(forReadingFrom: url)
                        defer { try? handle.close() }
                        var hasher = SHA256()
                        var size: Int64 = 0
                        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                            hasher.update(data: chunk)
                            size += Int64(chunk.count)
                        }
                        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
                        return SideInfo(size: size, sha: digest, readable: true)
                    }

                    let data = try source.loadData()
                    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                    return SideInfo(size: Int64(data.count), sha: digest, readable: true)
                } catch {
                    return SideInfo(size: 0, sha: "", readable: false)
                }
            }

            func localURL(for source: ComparisonSource) -> URL? {
                switch source {
                case .file(let url): return url
                case .workingCopy(let repo, let path): return repo.appendingPathComponent(path)
                default: return nil
                }
            }
            let ai = info(a)
            let bi = info(b)
            return Result(a: ai, b: bi, identical: ai.readable && bi.readable && ai.sha == bi.sha)
        }
        guard !Task.isCancelled, request == loadRequest, key == taskKey else { return }
        result = loaded
    }
}
