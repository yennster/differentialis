import SwiftUI

enum ImageMode: Int, CaseIterable, Hashable {
    case twoUp = 1, oneUp, split, difference

    var title: String {
        switch self {
        case .twoUp: return "Two-Up"
        case .oneUp: return "One-Up"
        case .split: return "Split"
        case .difference: return "Difference"
        }
    }
    var symbol: String {
        switch self {
        case .twoUp: return "rectangle.split.2x1"
        case .oneUp: return "rectangle"
        case .split: return "rectangle.lefthalf.inset.filled"
        case .difference: return "circle.lefthalf.filled"
        }
    }
}

struct ImageComparisonView: View {
    let a: ComparisonSource
    let b: ComparisonSource

    @State private var aImage: NSImage?
    @State private var bImage: NSImage?
    @State private var diffImage: NSImage?
    @State private var mode: ImageMode = .twoUp
    @State private var horizontal = true
    @State private var showB = false
    @State private var blinking = false
    @State private var splitFraction: CGFloat = 0.5
    @State private var zoom = ZoomPanState()
    @State private var loadError: String?

    private let blinkTimer = Timer.publish(every: 0.55, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            PathBar(a: a, b: b) { toolbar }
            Divider().opacity(0.4)
            canvas
            infoBar
        }
        .focusedSceneValue(\.diffCommands, DiffCommandActions(
            setImageMode: { mode = ImageMode(rawValue: $0) ?? mode }))
        .onReceive(blinkTimer) { _ in if blinking { showB.toggle() } }
        .task(id: taskKey) { await load() }
    }

    private var taskKey: String { "\(a.subtitle)|\(b.subtitle)|\(a.displayName)|\(b.displayName)" }

    // MARK: - Canvas

    @ViewBuilder
    private var canvas: some View {
        if let aImage, let bImage {
            Group {
                switch mode {
                case .twoUp: twoUp(aImage, bImage)
                case .oneUp: oneUp(aImage, bImage)
                case .split: SplitImageView(a: aImage, b: bImage, fraction: $splitFraction, zoom: zoom)
                case .difference: difference
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            ContentUnavailableView("Couldn’t load images", systemImage: "photo.badge.exclamationmark",
                                   description: Text(loadError))
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func twoUp(_ a: NSImage, _ b: NSImage) -> some View {
        let layout = horizontal ? AnyLayout(HStackLayout(spacing: 1)) : AnyLayout(VStackLayout(spacing: 1))
        return layout {
            ZoomableImageView(image: a, zoom: zoom)
            Rectangle().fill(.white.opacity(0.12)).frame(width: horizontal ? 1 : nil, height: horizontal ? nil : 1)
            ZoomableImageView(image: b, zoom: zoom)
        }
    }

    private func oneUp(_ a: NSImage, _ b: NSImage) -> some View {
        ZStack(alignment: .top) {
            ZoomableImageView(image: showB ? b : a, zoom: zoom)
            HStack(spacing: 6) {
                sideBadge("A", active: !showB, color: Theme.removed)
                sideBadge("B", active: showB, color: Theme.modified)
            }
            .padding(.top, 10)
        }
    }

    @ViewBuilder
    private var difference: some View {
        if let diffImage {
            ZoomableImageView(image: diffImage, zoom: zoom)
        } else {
            ProgressView("Computing difference…").frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func sideBadge(_ text: String, active: Bool, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(active ? .white : .secondary)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(active ? color : Color.black.opacity(0.4), in: Capsule())
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        GlassSegmentedControl(
            selection: $mode,
            options: ImageMode.allCases.map { .init(value: $0, title: $0.title, systemImage: $0.symbol) },
            compact: true)
        .fixedSize()

        if mode == .twoUp {
            Button { horizontal.toggle() } label: {
                Image(systemName: horizontal ? "rectangle.split.2x1" : "rectangle.split.1x2")
            }
            .buttonStyle(.borderless)
            .help("Toggle split orientation")
        }
        if mode == .oneUp {
            Button { blinking.toggle() } label: {
                Image(systemName: blinking ? "pause.fill" : "play.fill")
                    .foregroundStyle(blinking ? Theme.brand : .secondary)
            }
            .buttonStyle(.borderless)
            .help("Auto-switch A/B (blink)")
            Button { showB.toggle() } label: { Text(showB ? "B" : "A").font(.system(size: 12, weight: .bold)) }
                .buttonStyle(.borderless)
        }
    }

    private var infoBar: some View {
        HStack(spacing: 14) {
            if let aImage { Label("A · \(aImage.pixelDescription)", systemImage: "a.square").foregroundStyle(Theme.removed) }
            if let bImage { Label("B · \(bImage.pixelDescription)", systemImage: "b.square").foregroundStyle(Theme.modified) }
            Spacer()
            Text("\(Int(zoom.scale * 100))%").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            Button("Reset") { zoom.reset() }.buttonStyle(.borderless).controlSize(.small)
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 16).padding(.vertical, 7)
        .background(.ultraThinMaterial)
    }

    // MARK: - Loading

    private func load() async {
        loadError = nil
        aImage = a.loadImage()
        bImage = b.loadImage()
        if aImage == nil && bImage == nil {
            loadError = "Neither side could be decoded as an image."
            return
        }
        if let aImage, let bImage {
            diffImage = ImageDiffRenderer.difference(aImage, bImage)
        }
    }
}

/// Split-reveal comparison with a draggable divider.
struct SplitImageView: View {
    let a: NSImage
    let b: NSImage
    @Binding var fraction: CGFloat
    let zoom: ZoomPanState

    var body: some View {
        GeometryReader { geo in
            let splitX = geo.size.width * fraction
            ZStack(alignment: .topLeading) {
                Image(nsImage: a).resizable().interpolation(.high).scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                Image(nsImage: b).resizable().interpolation(.high).scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: splitX)
                    }
                // divider handle
                ZStack {
                    Rectangle().fill(Theme.brand).frame(width: 2)
                    Circle().fill(Theme.brand)
                        .frame(width: 28, height: 28)
                        .overlay(Image(systemName: "arrow.left.and.right").font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
                        .shadow(radius: 4)
                }
                .position(x: splitX, y: geo.size.height / 2)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            fraction = min(1, max(0, value.location.x / geo.size.width))
                        }
                )
                HStack {
                    Text("A").padding(6).background(Theme.removed, in: Capsule()).foregroundStyle(.white)
                    Spacer()
                    Text("B").padding(6).background(Theme.modified, in: Capsule()).foregroundStyle(.white)
                }
                .font(.system(size: 10, weight: .bold))
                .padding(10)
            }
            .background(CheckerboardBackground())
            .clipped()
        }
    }
}
