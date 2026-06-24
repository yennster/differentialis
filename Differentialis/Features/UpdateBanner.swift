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
                Text(summary(update.notes))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            Button("Notes") { model.updater.openReleaseNotes() }
                .buttonStyle(.borderless)
            Button("Skip") { withAnimation(.snappy) { model.updater.skipAvailable() } }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
            Button("Later") { withAnimation(.snappy) { model.updater.dismissAvailable() } }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
            Button("Update") { model.updater.installAvailable() }
                .buttonStyle(.glassProminent).tint(Theme.brand)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .glassCard(cornerRadius: 16)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.brand.opacity(0.35)))
        .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
        .frame(maxWidth: 640)
        .padding(.horizontal, 16).padding(.bottom, 16)
    }

    /// First meaningful line of the release notes, skipping markdown headers/rules
    /// and stripping list markers and emphasis.
    private func summary(_ notes: String) -> String {
        for raw in notes.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("---") { continue }
            if line.hasPrefix("- ") || line.hasPrefix("* ") { line.removeFirst(2) }
            line = line.replacingOccurrences(of: "**", with: "")
                       .replacingOccurrences(of: "`", with: "")
            if !line.isEmpty { return line }
        }
        return "A new version is ready to install."
    }
}
