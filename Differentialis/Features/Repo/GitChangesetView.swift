import SwiftUI
import AppKit

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
    @State private var listCollapsed = false

    var body: some View {
        if files.isEmpty {
            ContentUnavailableView("No changes", systemImage: "checkmark.circle",
                                   description: Text("These two states are identical."))
        } else {
            HSplitView {
                if listCollapsed {
                    CollapsedRail(title: "Files") { withAnimation(.panel) { listCollapsed = false } }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Files")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary.opacity(0.7))
                            Spacer()
                            Text("\(files.count) file\(files.count == 1 ? "" : "s")")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            Button { withAnimation(.panel) { listCollapsed = true } } label: {
                                Image(systemName: "sidebar.left")
                                    .frame(width: 24, height: 22)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless).help("Hide files")
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        Divider().opacity(0.4)
                        fileList
                    }
                    .frame(minWidth: 180, idealWidth: 280, maxWidth: 360)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
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
            .contextMenu { fileMenu(for: file) }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func fileMenu(for file: GitChangedFile) -> some View {
        let name = (file.path as NSString).lastPathComponent
        let fullPath = repo.url.appendingPathComponent(file.path).path
        Button("Copy Name") { copyToPasteboard(name) }
        Button("Copy Path") { copyToPasteboard(file.path) }
        Button("Copy Full Path") { copyToPasteboard(fullPath) }
    }

    private func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    @ViewBuilder
    private var detail: some View {
        if let file = files.first(where: { $0.id == selection }) ?? files.first {
            ComparisonDetailView(comparison: repo.makeComparison(file: file, a: a, aLabel: aLabel, b: b, bLabel: bLabel))
                .id(file.id)
        } else {
            ContentUnavailableView("Select a file", systemImage: "sidebar.left")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
