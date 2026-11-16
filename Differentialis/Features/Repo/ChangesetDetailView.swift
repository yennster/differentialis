import SwiftUI

/// A standalone open changeset (custom comparison result or saved comparison).
struct ChangesetDetailView: View {
    @Environment(AppModel.self) private var model
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
            .environment(\.changesetRevision, changeset.revision)
            .environment(\.changesetRefresh, { [model, id = changeset.id] in
                Task { await model.refreshChangeset(id) }
            })
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                let id = changeset.id
                Button { Task { await model.refreshChangeset(id) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh file list (⌘R)")
                .disabled(model.isRefreshingChangeset(id))
            }
        }
    }
}
