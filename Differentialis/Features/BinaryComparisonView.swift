import SwiftUI
import CryptoKit

/// Shown when at least one side isn't text or an image. Rather than line-diffing binary bytes into
/// garbage, it reports each side's size and SHA-256 and a simple equal/different verdict.
struct BinaryComparisonView: View {
    let a: ComparisonSource
    let b: ComparisonSource

    private struct SideInfo: Equatable {
        var size: Int
        var sha: String
        var readable: Bool
    }
    private struct Result: Equatable {
        var a: SideInfo
        var b: SideInfo
        var identical: Bool
    }

    @State private var result: Result?

    var body: some View {
        VStack(spacing: 0) {
            PathBar(a: a, b: b) {
                if let result {
                    StatChip(text: result.identical ? "Identical" : "Different",
                             color: result.identical ? Theme.added : Theme.modified,
                             systemImage: result.identical ? "checkmark.seal.fill" : "not.equal")
                }
            }
            Divider().opacity(0.4)
            content
        }
        .task(id: "\(a.displayName)|\(a.subtitle)|\(b.displayName)|\(b.subtitle)") { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let result {
            VStack(spacing: 18) {
                Image(systemName: result.identical ? "checkmark.seal.fill" : "doc.on.doc")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(result.identical ? Theme.added : Theme.modified)
                Text(result.identical ? "These binary files are identical." : "These binary files differ.")
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
            Text(label).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(accent, in: RoundedRectangle(cornerRadius: 5))
            if info.readable {
                Text(ByteCountFormatter.string(fromByteCount: Int64(info.size), countStyle: .file))
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
        let a = a, b = b
        result = await offMain {
            func info(_ source: ComparisonSource) -> SideInfo {
                guard let data = try? source.loadData() else { return SideInfo(size: 0, sha: "", readable: false) }
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                return SideInfo(size: data.count, sha: digest, readable: true)
            }
            let ai = info(a)
            let bi = info(b)
            return Result(a: ai, b: bi, identical: ai.readable && bi.readable && ai.sha == bi.sha)
        }
    }
}
