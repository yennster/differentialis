import SwiftUI

/// Shared filename, type, and status filtering for repository and standalone changesets.
struct GitFileFilter: Equatable {
    var query = ""
    var status: GitFileStatus?
    var fileExtension: String?

    var isActive: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || status != nil
            || fileExtension != nil
    }

    func apply(to files: [GitChangedFile]) -> [GitChangedFile] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedLowercase
        return files.filter { file in
            if let status, file.status != status { return false }
            if let fileExtension {
                let ext = (file.path as NSString).pathExtension.localizedLowercase
                if ext != fileExtension { return false }
            }
            return needle.isEmpty || file.path.localizedLowercase.contains(needle)
        }
    }

    mutating func reset() {
        query = ""
        status = nil
        fileExtension = nil
    }
}

struct GitFileFilterBar: View {
    @Binding var filter: GitFileFilter
    let files: [GitChangedFile]
    let resultCount: Int

    private let statusOrder: [GitFileStatus] = [
        .conflicted, .modified, .added, .deleted, .renamed, .copied, .typeChanged, .untracked,
    ]

    private var statuses: [GitFileStatus] {
        let present = Set(files.map(\.status))
        return statusOrder.filter(present.contains)
    }

    private var fileExtensions: [String] {
        Set(files.map { ($0.path as NSString).pathExtension.localizedLowercase })
            .sorted { lhs, rhs in
                if lhs.isEmpty { return true }
                if rhs.isEmpty { return false }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Filter files", text: $filter.query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .accessibilityLabel("Filter files by name or path")

            statusMenu
            typeMenu

            if filter.isActive {
                Button {
                    filter.reset()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Clear filters")
                .accessibilityLabel("Clear file filters")
            }

            Text(filter.isActive ? "\(resultCount)/\(files.count)" : "\(files.count)")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(resultCount) of \(files.count) files shown")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
    }

    private var statusMenu: some View {
        Menu {
            Button("All Statuses") { filter.status = nil }
            if !statuses.isEmpty { Divider() }
            ForEach(statuses, id: \.self) { status in
                Button {
                    filter.status = status
                } label: {
                    Label(status.label, systemImage: filter.status == status ? "checkmark" : statusSymbol(status))
                }
            }
        } label: {
            Image(systemName: filter.status.map(statusSymbol) ?? "line.3.horizontal.decrease.circle")
                .foregroundStyle(filter.status?.tint ?? Color.gray)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(filter.status.map { "Status: \($0.label)" } ?? "Filter by status")
        .accessibilityLabel("Filter by change status")
    }

    private var typeMenu: some View {
        Menu {
            Button("All File Types") { filter.fileExtension = nil }
            if !fileExtensions.isEmpty { Divider() }
            ForEach(fileExtensions, id: \.self) { ext in
                Button {
                    filter.fileExtension = ext
                } label: {
                    let label = ext.isEmpty ? "No Extension" : ".\(ext)"
                    if filter.fileExtension == ext {
                        Label(label, systemImage: "checkmark")
                    } else {
                        Text(label)
                    }
                }
            }
        } label: {
            Image(systemName: "doc.badge.ellipsis")
                .foregroundStyle(filter.fileExtension == nil ? .secondary : Theme.brandAlt)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(filter.fileExtension.map { $0.isEmpty ? "Type: no extension" : "Type: .\($0)" }
              ?? "Filter by file type")
        .accessibilityLabel("Filter by file type")
    }

    private func statusSymbol(_ status: GitFileStatus) -> String {
        switch status {
        case .added, .untracked: return "plus.circle"
        case .modified, .typeChanged: return "pencil.circle"
        case .deleted: return "minus.circle"
        case .renamed: return "arrow.right.circle"
        case .copied: return "doc.on.doc"
        case .conflicted: return "exclamationmark.triangle"
        }
    }
}
