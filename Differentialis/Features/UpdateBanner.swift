import SwiftUI

/// A non-modal Liquid Glass banner shown when a newer release is available.
struct UpdateBanner: View {
    @Environment(AppModel.self) private var model
    let update: AvailableUpdate

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.brand)
            VStack(alignment: .leading, spacing: 2) {
                Text("Update available — \(update.version)")
                    .font(.system(size: 13, weight: .semibold))
                Text(firstLine(update.notes))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            Button("Notes") { model.updates.openReleaseNotes() }
                .buttonStyle(.borderless)
            Button("Skip") { withAnimation(.snappy) { model.updates.skipAvailable() } }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
            Button("Later") { withAnimation(.snappy) { model.updates.dismissAvailable() } }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
            Button("Download") { model.updates.downloadAvailable() }
                .buttonStyle(.glassProminent).tint(Theme.brand)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .glassCard(cornerRadius: 16)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.brand.opacity(0.35)))
        .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
        .frame(maxWidth: 640)
        .padding(.horizontal, 16).padding(.bottom, 16)
    }

    private func firstLine(_ notes: String) -> String {
        let line = notes.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return line.isEmpty ? "A new version is ready to download." : line
    }
}
