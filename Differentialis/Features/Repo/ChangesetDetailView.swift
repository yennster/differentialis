import SwiftUI

/// A standalone open changeset (custom comparison result or saved comparison).
struct ChangesetDetailView: View {
    let changeset: OpenChangeset

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill").foregroundStyle(Theme.brandAlt)
                VStack(alignment: .leading, spacing: 1) {
                    Text(changeset.title).font(.system(size: 14, weight: .semibold))
                    Text("\(changeset.subtitle) · \(changeset.resolved.aLabel) ↔ \(changeset.resolved.bLabel)")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                StatChip(text: "\(changeset.resolved.files.count) file\(changeset.resolved.files.count == 1 ? "" : "s")",
                         color: .primary, systemImage: "doc.on.doc")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider().opacity(0.4)
            GitChangesetView(repo: changeset.repo,
                             files: changeset.resolved.files,
                             a: changeset.resolved.a, aLabel: changeset.resolved.aLabel,
                             b: changeset.resolved.b, bLabel: changeset.resolved.bLabel)
        }
    }
}
