import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var dropTargeted = false

    private let actions: [(title: String, subtitle: String, symbol: String, tint: Color, mode: AppModel.PickMode)] = [
        ("Text", "Compare two text or code files", "text.alignleft", Theme.modified, .text),
        ("Image", "Spot pixel-level differences", "photo", Theme.added, .image),
        ("Folder", "Diff entire directory trees", "folder", Theme.brandAlt, .folder),
        ("3-Way Merge", "Resolve conflicts with a base", "arrow.triangle.merge", Theme.conflict, .merge),
        ("Repository", "Browse a git project's history", "point.3.connected.trianglepath.dotted", Theme.brand, .repository),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                GlassEffectContainer(spacing: 18) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 16)], spacing: 16) {
                        ForEach(actions, id: \.title) { action in
                            actionCard(action)
                        }
                    }
                }
                .frame(maxWidth: 760)
                dropHint
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Theme.brand, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .padding(16)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: dropTargeted)
    }

    private var header: some View {
        VStack(spacing: 14) {
            DiffMarkView(size: 78)
            Text("Differentialis")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Compare and merge text, images, and folders — beautifully.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
    }

    private func actionCard(_ action: (title: String, subtitle: String, symbol: String, tint: Color, mode: AppModel.PickMode)) -> some View {
        Button {
            model.chooseFiles(mode: action.mode)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: action.symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(action.tint)
                    .frame(height: 32)
                Text(action.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text(action.subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .padding(18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: 20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(action.tint.opacity(0.25), lineWidth: 1)
        )
    }

    private var dropHint: some View {
        Label("Drag files or folders anywhere to compare", systemImage: "arrow.down.doc")
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .glassCard(cornerRadius: 12)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var urls: [URL] = []
        for provider in providers.prefix(3) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let sorted = urls.sorted { $0.path < $1.path }
            guard sorted.count >= 2 else { return }
            if sorted.count >= 3 {
                self.model.open(Comparison.merge(base: .file(sorted[0]),
                                                 left: .file(sorted[1]),
                                                 right: .file(sorted[2])))
            } else {
                self.model.open(Comparison.make(a: .file(sorted[0]), b: .file(sorted[1])))
            }
        }
        return true
    }
}
