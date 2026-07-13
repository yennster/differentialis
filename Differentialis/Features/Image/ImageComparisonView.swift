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

    @State private var loadedAImage: NSImage?
    @State private var loadedBImage: NSImage?
    @State private var diffImage: NSImage?
    @AppStorage("imageDiffMode") private var mode = ImageMode.twoUp
    @State private var horizontal = true
    @State private var showB = false
    @State private var blinking = false
    @State private var swapped = false
    @State private var splitFraction: CGFloat = 0.5
    @State private var zoom = ZoomPanState()
    @State private var loadError: String?
    @State private var loadToken: UUID?
    @State private var imageRevision: UUID?

    private let blinkTimer = Timer.publish(every: 0.55, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            PathBar(a: displayedA, b: displayedB) { toolbar }
            Divider().opacity(0.4)
            canvas
            infoBar
        }
        .focusedSceneValue(\.diffCommands, DiffCommandActions(
            setImageMode: { mode = ImageMode(rawValue: $0) ?? mode },
            swapAB: { swapped.toggle() },
            refresh: { Task { await load() } }))
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            guard mode == .oneUp else { return .ignored }
            showB.toggle()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard mode == .oneUp else { return .ignored }
            showB = false
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard mode == .oneUp else { return .ignored }
            showB = true
            return .handled
        }
        .onReceive(blinkTimer) { _ in if blinking { showB.toggle() } }
        .task(id: taskKey) { await load() }
        .task(id: differenceTaskKey) { await renderDifferenceIfNeeded() }
        .onChange(of: mode) { _, newMode in
            if newMode != .oneUp { blinking = false }
        }
    }

    private var taskKey: String { "\(a.subtitle)|\(b.subtitle)|\(a.displayName)|\(b.displayName)" }
    private var differenceTaskKey: String {
        "\(mode.rawValue)|\(imageRevision?.uuidString ?? "loading")"
    }
    private var displayedA: ComparisonSource { swapped ? b : a }
    private var displayedB: ComparisonSource { swapped ? a : b }
    private var aImage: NSImage? { swapped ? loadedBImage : loadedAImage }
    private var bImage: NSImage? { swapped ? loadedAImage : loadedBImage }

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
        } else if let single = aImage ?? bImage {
            // Only one side has an image — an added file (no A) or a deleted file (no B).
            // Show the side we have rather than spinning forever waiting for both.
            singleSided(single, presentIsA: aImage != nil)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            ContentUnavailableView("Couldn’t load images", systemImage: "photo.badge.exclamationmark",
                                   description: Text(loadError))
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Lay the one available image beside a placeholder describing why the other side is absent.
    private func singleSided(_ image: NSImage, presentIsA: Bool) -> some View {
        let layout = horizontal ? AnyLayout(HStackLayout(spacing: 1)) : AnyLayout(VStackLayout(spacing: 1))
        return layout {
            if presentIsA {
                ZoomableImageView(image: image, zoom: zoom)
                divider
                absentPanel(side: "B")
            } else {
                absentPanel(side: "A")
                divider
                ZoomableImageView(image: image, zoom: zoom)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.12))
            .frame(width: horizontal ? 1 : nil, height: horizontal ? nil : 1)
    }

    private func absentPanel(side: String) -> some View {
        let source = side == "A" ? displayedA : displayedB
        let isEmpty = { if case .empty = source { return true } else { return false } }()
        let title = isEmpty ? (side == "A" ? "Added" : "Removed") : "No image"
        let subtitle = isEmpty
            ? "This file doesn’t exist on side \(side)"
            : "Side \(side) couldn’t be decoded as an image"
        return VStack(spacing: 8) {
            Image(systemName: side == "A" ? "a.square" : "b.square")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(subtitle).font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckerboardBackground())
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
            .foregroundStyle(active ? Theme.badgeForeground : Color.secondary)
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
            GlassSegmentedControl(
                selection: $showB,
                options: [.init(value: false, title: "A"), .init(value: true, title: "B")],
                compact: true)
            .fixedSize()
            .help("Show A or B  ·  Space toggles, ← / → pick a side")
            Button { blinking.toggle() } label: {
                Image(systemName: blinking ? "pause.fill" : "play.fill")
                    .foregroundStyle(blinking ? Theme.brand : .secondary)
            }
            .buttonStyle(.borderless)
            .help("Auto-switch A/B (blink)")
        }

        FilePropertiesButton(a: displayedA, b: displayedB)
    }

    private var infoBar: some View {
        HStack(spacing: 14) {
            if let aImage { Label("A · \(aImage.pixelDescription)", systemImage: "a.square").foregroundStyle(Theme.removed) }
            if let bImage { Label("B · \(bImage.pixelDescription)", systemImage: "b.square").foregroundStyle(Theme.modified) }
            Spacer()
            HStack(spacing: 6) {
                Button { zoom.zoom(by: 0.8) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .disabled(zoom.scale <= ZoomPanState.minimumScale)
                .help("Zoom out")
                .accessibilityLabel("Zoom out")

                Text("\(Int(zoom.scale * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 42)
                    .accessibilityLabel("Zoom \(Int(zoom.scale * 100)) percent of fit")

                Button { zoom.zoom(by: 1.25) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .disabled(zoom.scale >= ZoomPanState.maximumScale)
                .help("Zoom in")
                .accessibilityLabel("Zoom in")

                Button("Fit") { zoom.reset() }
                    .disabled(zoom.scale == 1 && zoom.offset == .zero)
                    .help("Fit images in the available space")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 16).padding(.vertical, 7)
        .background(.ultraThinMaterial)
    }

    // MARK: - Loading

    private func load() async {
        // Clear stale content so the spinner shows instead of the previous pair while loading.
        let token = UUID()
        loadToken = token
        imageRevision = nil
        loadedAImage = nil
        loadedBImage = nil
        diffImage = nil
        loadError = nil
        zoom.reset()
        let a = a, b = b
        let key = taskKey
        // Read the bytes (possibly a git blob) off the main actor; NSImage decodes lazily on draw.
        let data = await offMain { (try? a.loadData(), try? b.loadData()) }
        guard !Task.isCancelled, token == loadToken, key == taskKey else { return }
        loadedAImage = data.0.flatMap(NSImage.init(data:))
        loadedBImage = data.1.flatMap(NSImage.init(data:))
        if loadedAImage == nil && loadedBImage == nil {
            loadError = "Neither side could be decoded as an image."
            return
        }
        // Publishing a new revision starts difference rendering only when Difference mode is active.
        imageRevision = UUID()
    }

    private func renderDifferenceIfNeeded() async {
        guard mode == .difference,
              diffImage == nil,
              let revision = imageRevision,
              let ai = loadedAImage,
              let bi = loadedBImage else { return }
        let key = taskKey
        let pair = Unchecked((ai, bi))
        let rendered = await offMain {
            Unchecked(ImageDiffRenderer.difference(pair.value.0, pair.value.1))
        }.value
        guard !Task.isCancelled,
              mode == .difference,
              revision == imageRevision,
              key == taskKey else { return }
        diffImage = rendered
    }
}

/// Split-reveal comparison with a draggable divider.
struct SplitImageView: View {
    let a: NSImage
    let b: NSImage
    @Binding var fraction: CGFloat
    let zoom: ZoomPanState

    @State private var dividerDragBase: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let splitX = geo.size.width * fraction
            ZStack(alignment: .topLeading) {
                // B fills the canvas; A is revealed from the leading edge so the labels and
                // conventional A-left / B-right reading order always agree.
                imageLayer(b, size: geo.size)
                imageLayer(a, size: geo.size)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: splitX)
                    }

                // A transparent interaction plane keeps pan/zoom out of the divider's hit area.
                Color.clear
                    .contentShape(Rectangle())
                    .zoomPanGestures(zoom)

                ZStack {
                    Rectangle().fill(Theme.brand).frame(width: 2).frame(maxHeight: .infinity)
                    Circle().fill(Theme.brand)
                        .frame(width: 28, height: 28)
                        .overlay(Image(systemName: "arrow.left.and.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.badgeForeground))
                        .shadow(radius: 4)
                }
                .frame(width: 32, height: geo.size.height)
                .contentShape(Rectangle())
                .position(x: splitX, y: geo.size.height / 2)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if dividerDragBase == nil { dividerDragBase = fraction }
                            let base = dividerDragBase ?? fraction
                            setFraction(base + value.translation.width / max(geo.size.width, 1))
                        }
                        .onEnded { _ in dividerDragBase = nil }
                )
                .focusable()
                .onKeyPress(.leftArrow) {
                    adjustFraction(by: -0.02)
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    adjustFraction(by: 0.02)
                    return .handled
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Image split position")
                .accessibilityValue("A \(Int(fraction * 100)) percent, B \(Int((1 - fraction) * 100)) percent")
                .accessibilityHint("Drag, or use the Left and Right Arrow keys to adjust")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: adjustFraction(by: 0.05)
                    case .decrement: adjustFraction(by: -0.05)
                    @unknown default: break
                    }
                }
                .help("Adjust split  ·  Drag or use ← / →")

                HStack {
                    Text("A").padding(6).background(Theme.removed, in: Capsule()).foregroundStyle(Theme.badgeForeground)
                    Spacer()
                    Text("B").padding(6).background(Theme.modified, in: Capsule()).foregroundStyle(Theme.badgeForeground)
                }
                .font(.system(size: 10, weight: .bold))
                .padding(10)
            }
            .background(CheckerboardBackground())
            .clipped()
        }
    }

    private func imageLayer(_ image: NSImage, size: CGSize) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .scaleEffect(zoom.scale)
            .offset(zoom.offset)
            .frame(width: size.width, height: size.height)
            .accessibilityHidden(true)
    }

    private func adjustFraction(by amount: CGFloat) {
        setFraction(fraction + amount)
    }

    private func setFraction(_ value: CGFloat) {
        fraction = min(1, max(0, value))
    }
}
