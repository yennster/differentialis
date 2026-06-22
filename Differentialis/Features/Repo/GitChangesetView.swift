import SwiftUI

/// A git changed-files list beside the selected file's diff. Reused by the
/// repository commit view, custom comparisons, and saved comparisons.
struct GitChangesetView: View {
    let repo: GitRepository
    let files: [GitChangedFile]
    let a: GitSide
    let aLabel: String
    let b: GitSide
    let bLabel: String

    @State private var selection: GitChangedFile.ID?

    var body: some View {
        if files.isEmpty {
            ContentUnavailableView("No changes", systemImage: "checkmark.circle",
                                   description: Text("These two states are identical."))
        } else {
            HSplitView {
                fileList
                    .frame(minWidth: 220, idealWidth: 300, maxWidth: 440)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var fileList: some View {
        List(files, selection: $selection) { file in
            HStack(spacing: 8) {
                Text(file.status.letter)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(file.status.tint, in: RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 1) {
                    Text((file.path as NSString).lastPathComponent)
                        .font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                    Text((file.path as NSString).deletingLastPathComponent)
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
            }
            .tag(file.id)
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private var detail: some View {
        if let file = files.first(where: { $0.id == selection }) ?? files.first {
            ComparisonDetailView(comparison: repo.makeComparison(file: file, a: a, aLabel: aLabel, b: b, bLabel: bLabel))
                .id(file.id)
        } else {
            ContentUnavailableView("Select a file", systemImage: "sidebar.left")
        }
    }
}
