import SwiftUI
import AppKit

/// Font and colors for a diff editor, resolved from the active theme in a SwiftUI body (so a
/// theme or font-size change re-renders the editors).
struct DiffEditorStyle: Equatable {
    var font: NSFont
    var gutterFont: NSFont
    var fills: [DiffRow.Kind: NSColor]
    var accents: [DiffRow.Kind: NSColor]
    /// Changed characters inside a modified line.
    var highlight: NSColor
    /// Marks where the other side has lines this side lacks.
    var insertionMarker: NSColor
    var current: NSColor
    var currentMarker: NSColor

    @MainActor
    static func current(for side: PastedTextSide) -> DiffEditorStyle {
        let size = Theme.codeFontSize
        func codeFont(_ size: CGFloat) -> NSFont {
            ThemeManager.shared.codeFontName.flatMap {
                NSFontManager.shared.font(withFamily: $0, traits: [], weight: 5, size: size)
            } ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        }
        return DiffEditorStyle(
            font: codeFont(size),
            gutterFont: codeFont(max(8, size - 1.5)),
            fills: [.inserted: NSColor(Theme.addedFill), .deleted: NSColor(Theme.removedFill),
                    .modified: NSColor(Theme.modifiedFill)],
            accents: [.inserted: NSColor(Theme.added), .deleted: NSColor(Theme.removed),
                      .modified: NSColor(Theme.modified)],
            highlight: NSColor(side == .a ? Theme.removedHighlight : Theme.addedHighlight),
            insertionMarker: NSColor(side == .a ? Theme.added : Theme.removed),
            current: NSColor(Theme.brand.opacity(0.12)),
            currentMarker: NSColor(Theme.brand))
    }
}

/// A plain-text, TextKit 1 text view that paints a two-way diff behind its text: tinted changed
/// lines, highlighted changed characters, and markers where the other side has extra lines.
final class DiffTextView: NSTextView {
    /// A view assembled by hand doesn't own its text storage, so keep it alive here.
    private var ownedTextStorage: NSTextStorage?

    /// Builds the view on TextKit 1, whose temporary attributes and line-fragment geometry the
    /// diff painting relies on.
    static func make() -> DiffTextView {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        let view = DiffTextView(frame: .zero, textContainer: container)
        view.ownedTextStorage = storage
        storage.delegate = view
        return view
    }

    var decorations = EditorDecorations() {
        didSet {
            guard decorations != oldValue else { return }
            applyCharacterHighlights()
            refreshDecorations()
        }
    }
    var currentRange: NSRange? {
        didSet { if currentRange != oldValue { refreshDecorations() } }
    }
    var style: DiffEditorStyle? {
        didSet {
            guard let style, style != oldValue else { return }
            if style.font != oldValue?.font {
                font = style.font
                typingAttributes[.font] = style.font
            }
            applyCharacterHighlights()
            lineNumberRuler?.updateThickness()
            refreshDecorations()
        }
    }

    fileprivate var cachedLineStarts: [Int]?

    /// UTF-16 offset of each line's first character, with `LineDiff.split` line semantics.
    var lineStarts: [Int] {
        if let cachedLineStarts { return cachedLineStarts }
        let starts = TwoWayMerge.lineSpans(in: string).map(\.start)
        cachedLineStarts = starts
        return starts
    }

    var lineNumberRuler: LineNumberRulerView? {
        enclosingScrollView?.verticalRulerView as? LineNumberRulerView
    }

    private func refreshDecorations() {
        needsDisplay = true
        lineNumberRuler?.needsDisplay = true
    }

    private func applyCharacterHighlights() {
        guard let layoutManager, let style else { return }
        let whole = NSRange(location: 0, length: textStorage?.length ?? 0)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: whole)
        for range in decorations.characterHighlights {
            let clamped = NSIntersectionRange(range, whole)
            guard clamped.length > 0 else { continue }
            layoutManager.addTemporaryAttribute(.backgroundColor, value: style.highlight,
                                                forCharacterRange: clamped)
        }
    }

    // MARK: Drawing

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let style else { return }
        let visible = visibleCharacterRange(in: rect)
        for fill in decorations.lineFills where rangesTouch(fill.range, visible) {
            guard let color = style.fills[fill.kind] else { continue }
            color.setFill()
            for lineRect in lineRects(for: fill.range) where lineRect.intersects(rect) {
                lineRect.fill(using: .sourceOver)
            }
        }
        if let currentRange, currentRange.length > 0 {
            style.current.setFill()
            for lineRect in lineRects(for: currentRange) { lineRect.fill(using: .sourceOver) }
        }
        for range in decorations.hunkRanges where range.length == 0 {
            let isCurrent = range == currentRange
            (isCurrent ? style.currentMarker : style.insertionMarker).setFill()
            let y = insertionY(at: range.location)
            let thickness: CGFloat = isCurrent ? 3 : 2
            NSRect(x: 0, y: y - thickness / 2, width: bounds.width, height: thickness)
                .fill(using: .sourceOver)
        }
    }

    /// Full-width rects (text view coordinates) of every line fragment in `range`.
    func lineRects(for range: NSRange) -> [NSRect] {
        guard let layoutManager, let textContainer else { return [] }
        let length = textStorage?.length ?? 0
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: length))
        var rects: [NSRect] = []
        if clamped.length > 0 {
            let glyphs = layoutManager.glyphRange(forCharacterRange: clamped, actualCharacterRange: nil)
            layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
                rects.append(rect)
            }
        } else if range.location >= length {
            layoutManager.ensureLayout(for: textContainer)
            let extra = layoutManager.extraLineFragmentRect
            if !extra.isEmpty { rects.append(extra) }
        } else {
            let glyph = layoutManager.glyphIndexForCharacter(at: range.location)
            rects.append(layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil))
        }
        let origin = textContainerOrigin
        return rects.map { NSRect(x: 0, y: $0.minY + origin.y, width: bounds.width, height: $0.height) }
    }

    /// The y (text view coordinates) of the boundary just above the line starting at `location`.
    func insertionY(at location: Int) -> CGFloat {
        guard let layoutManager, let textContainer else { return 0 }
        let length = textStorage?.length ?? 0
        let origin = textContainerOrigin.y
        if location < length {
            let glyph = layoutManager.glyphIndexForCharacter(at: location)
            return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY + origin
        }
        layoutManager.ensureLayout(for: textContainer)
        let extra = layoutManager.extraLineFragmentRect
        if !extra.isEmpty { return extra.minY + origin }
        guard length > 0 else { return origin }
        let last = layoutManager.glyphIndexForCharacter(at: length - 1)
        return layoutManager.lineFragmentRect(forGlyphAt: last, effectiveRange: nil).maxY + origin
    }

    /// Characters laid out within `rect` (text view coordinates), plus the boundary after them.
    func visibleCharacterRange(in rect: NSRect) -> NSRange {
        guard let layoutManager, let textContainer else { return NSRange(location: 0, length: 0) }
        var containerRect = rect
        containerRect.origin.y -= textContainerOrigin.y
        let glyphs = layoutManager.glyphRange(forBoundingRect: containerRect, in: textContainer)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        // Include the boundary so the insertion marker / extra line fragment at the very end draws.
        return NSRange(location: characters.location, length: characters.length + 1)
    }

    func rangesTouch(_ range: NSRange, _ visible: NSRange) -> Bool {
        range.location <= NSMaxRange(visible) && NSMaxRange(range) >= visible.location
    }

    // MARK: Line geometry (scroll sync and reveal)

    /// The index of the line containing `location`.
    func lineIndex(containing location: Int) -> Int {
        let starts = lineStarts
        var low = 0, high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= location { low = mid } else { high = mid - 1 }
        }
        return max(0, low)
    }

    func lineIndex(atY y: CGFloat) -> Int {
        guard let layoutManager, let textContainer, (textStorage?.length ?? 0) > 0 else { return 0 }
        let point = NSPoint(x: 0, y: max(0, y - textContainerOrigin.y))
        let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
        return lineIndex(containing: layoutManager.characterIndexForGlyph(at: glyph))
    }

    /// The full range of line `index`, terminator included.
    func lineRange(_ index: Int) -> NSRange {
        let starts = lineStarts
        let length = textStorage?.length ?? 0
        guard index < starts.count else { return NSRange(location: length, length: 0) }
        let end = index + 1 < starts.count ? starts[index + 1] : length
        return NSRange(location: starts[index], length: end - starts[index])
    }

    /// The top of line `index`; an index past the last line is the bottom of the text.
    func lineTop(_ index: Int) -> CGFloat {
        guard index < lineStarts.count else {
            guard let layoutManager, let textContainer else { return 0 }
            layoutManager.ensureLayout(for: textContainer)
            return layoutManager.usedRect(for: textContainer).maxY + textContainerOrigin.y
        }
        return lineRects(for: lineRange(index)).first?.minY ?? 0
    }

    func lineHeight(_ index: Int) -> CGFloat {
        let rects = lineRects(for: lineRange(index))
        guard let first = rects.first, let last = rects.last else { return 0 }
        return last.maxY - first.minY
    }

    /// The vertical extent of a hunk's span on this side (a thin band for an insertion point).
    func verticalExtent(of range: NSRange) -> ClosedRange<CGFloat> {
        if range.length == 0 {
            let y = insertionY(at: range.location)
            return y...y
        }
        let rects = lineRects(for: range)
        guard let first = rects.first, let last = rects.last else { return 0...0 }
        return first.minY...last.maxY
    }

    func scrollToY(_ y: CGFloat) {
        guard let scrollView = enclosingScrollView else { return }
        let clip = scrollView.contentView
        let maxY = max(0, frame.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: min(max(0, y), maxY)))
        scrollView.reflectScrolledClipView(clip)
    }
}

/// Line numbers for a `DiffTextView`, with the same change bar and tint as the diff rows.
final class LineNumberRulerView: NSRulerView {
    private weak var diffTextView: DiffTextView?

    init(textView: DiffTextView, scrollView: NSScrollView) {
        diffTextView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 40
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    func updateThickness() {
        guard let textView = diffTextView, let font = textView.style?.gutterFont else { return }
        let digits = max(3, String(textView.lineStarts.count).count)
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: font]).width
        let thickness = (CGFloat(digits) * digitWidth + 18).rounded(.up)
        if abs(ruleThickness - thickness) > 0.5 { ruleThickness = thickness }
    }

    override func draw(_ dirtyRect: NSRect) {
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = diffTextView, let style = textView.style else { return }

        let characters = textView.visibleCharacterRange(in: textView.visibleRect)

        // Change tint and bar, matching DiffRowView's gutter.
        for fill in textView.decorations.lineFills where textView.rangesTouch(fill.range, characters) {
            for lineRect in textView.lineRects(for: fill.range) {
                let local = convert(lineRect, from: textView)
                guard local.intersects(rect) else { continue }
                style.fills[fill.kind]?.setFill()
                NSRect(x: 0, y: local.minY, width: bounds.width, height: local.height).fill(using: .sourceOver)
                style.accents[fill.kind]?.setFill()
                NSRect(x: 0, y: local.minY, width: 2.5, height: local.height).fill(using: .sourceOver)
            }
        }

        let starts = textView.lineStarts
        let attributes: [NSAttributedString.Key: Any] = [
            .font: style.gutterFont,
            .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.7),
        ]
        var line = textView.lineIndex(containing: characters.location)
        while line < starts.count, starts[line] <= NSMaxRange(characters) {
            guard let first = textView.lineRects(for: NSRange(location: starts[line], length: 0)).first
            else { break }
            let local = convert(first, from: textView)
            let label = "\(line + 1)" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: bounds.width - 7 - size.width,
                                   y: local.minY + (local.height - size.height) / 2),
                       withAttributes: attributes)
            line += 1
        }
    }
}

/// Owns the two editors of a pasted-text comparison: routes programmatic edits (paste, merge,
/// swap) through the text system so they are undoable, and keeps the panes scrolled together.
@MainActor
final class PastedTextEditorController {
    /// Shared by both editors, so undo spans them (a merge into B undoes even while A has focus),
    /// and discarded with this controller, so no undo action outlives its text views.
    let undoManager = UndoManager()
    var aToB: [LineLink] = []
    var bToA: [LineLink] = []
    /// True while a programmatic edit is in flight, so selection callbacks don't treat it as a click.
    private(set) var isEditingProgrammatically = false
    private weak var aView: DiffTextView?
    private weak var bView: DiffTextView?
    private var isSyncingScroll = false

    func attach(_ view: DiffTextView, side: PastedTextSide) {
        if side == .a { aView = view } else { bView = view }
    }

    func view(for side: PastedTextSide) -> DiffTextView? {
        side == .a ? aView : bView
    }

    /// Replaces a side's text through its editor, touching only the range that changed so the
    /// caret and scroll position stay put. Returns false when that editor isn't on screen.
    @discardableResult
    func replaceText(on side: PastedTextSide, with newText: String, actionName: String) -> Bool {
        guard let view = view(for: side), let storage = view.textStorage else { return false }
        let old = storage.string as NSString
        let new = newText as NSString
        guard !old.isEqual(to: newText) else { return true }

        // Shrink to the changed middle, never splitting a surrogate pair.
        var prefix = 0
        let shorter = min(old.length, new.length)
        while prefix < shorter, old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
        if prefix > 0, CFStringIsSurrogateHighCharacter(old.character(at: prefix - 1)) { prefix -= 1 }
        var suffix = 0
        while suffix < shorter - prefix,
              old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) {
            suffix += 1
        }
        if suffix > 0, CFStringIsSurrogateLowCharacter(old.character(at: old.length - suffix)) { suffix -= 1 }

        let range = NSRange(location: prefix, length: old.length - prefix - suffix)
        let replacement = new.substring(with: NSRange(location: prefix, length: new.length - prefix - suffix))

        isEditingProgrammatically = true
        defer { isEditingProgrammatically = false }
        view.breakUndoCoalescing()
        guard view.shouldChangeText(in: range, replacementString: replacement) else { return true }
        var attributes = view.typingAttributes
        if let font = view.style?.font { attributes[.font] = font }
        storage.replaceCharacters(in: range, with: NSAttributedString(string: replacement, attributes: attributes))
        view.didChangeText()
        undoManager.setActionName(actionName)
        return true
    }

    /// Scrolls both editors to a hunk. With `onlyIfNeeded`, an editor that already shows the
    /// hunk is left alone.
    func reveal(a: NSRange?, b: NSRange?, onlyIfNeeded: Bool) {
        isSyncingScroll = true
        defer { isSyncingScroll = false }
        for (view, range) in [(aView, a), (bView, b)] {
            guard let view, let range else { continue }
            let extent = view.verticalExtent(of: range)
            let visible = view.visibleRect
            if onlyIfNeeded, extent.lowerBound >= visible.minY, extent.upperBound <= visible.maxY { continue }
            let height = extent.upperBound - extent.lowerBound
            let y = height > visible.height * 0.8
                ? extent.lowerBound - 24
                : (extent.lowerBound + extent.upperBound) / 2 - visible.height / 2
            view.scrollToY(y)
        }
    }

    /// Keeps the other editor aligned to the line at the top of the one that scrolled. Matched
    /// lines track exactly; while scrolling through lines the other side lacks, it waits at the
    /// insertion point.
    func didScroll(_ side: PastedTextSide) {
        guard !isSyncingScroll, let source = view(for: side), let target = view(for: side.other) else { return }
        let links = side == .a ? aToB : bToA
        let top = source.visibleRect.minY
        let line = source.lineIndex(atY: top)
        guard line < links.count else { return }
        let link = links[line]
        var y = target.lineTop(link.line)
        if link.matched {
            y += min(top - source.lineTop(line), target.lineHeight(link.line))
        }
        isSyncingScroll = true
        defer { isSyncingScroll = false }
        target.scrollToY(y)
    }
}

/// One editable side of a pasted-text comparison.
struct DiffTextEditor: NSViewRepresentable {
    let side: PastedTextSide
    @Binding var text: String
    var decorations: EditorDecorations
    var currentRange: NSRange?
    var style: DiffEditorStyle
    let controller: PastedTextEditorController
    var onCaretMove: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false

        let textView = DiffTextView.make()
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        textView.setAccessibilityLabel(side == .a ? "Original text (A)" : "Modified text (B)")
        textView.style = style
        textView.string = text
        textView.font = style.font
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)

        let ruler = LineNumberRulerView(textView: textView, scrollView: scrollView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        ruler.updateThickness()

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(context.coordinator,
                                               selector: #selector(Coordinator.boundsDidChange(_:)),
                                               name: NSView.boundsDidChangeNotification,
                                               object: scrollView.contentView)

        controller.attach(textView, side: side)
        textView.decorations = decorations
        textView.currentRange = currentRange
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? DiffTextView else { return }
        controller.attach(textView, side: side)
        textView.style = style
        if textView.string != text {
            // Edits made through the controller are already in the view; anything else (a change
            // made while this editor was off screen) is adopted wholesale.
            context.coordinator.isAdoptingText = true
            defer { context.coordinator.isAdoptingText = false }
            textView.string = text
            textView.font = style.font
            textView.lineNumberRuler?.updateThickness()
        }
        textView.decorations = decorations
        textView.currentRange = currentRange
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DiffTextEditor
        /// Set while SwiftUI pushes text into the view, when callbacks must not write state back.
        var isAdoptingText = false

        init(_ parent: DiffTextEditor) { self.parent = parent }

        func undoManager(for view: NSTextView) -> UndoManager? {
            parent.controller.undoManager
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? DiffTextView else { return }
            let string = textView.string
            if parent.text != string { parent.text = string }
            textView.lineNumberRuler?.updateThickness()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !parent.controller.isEditingProgrammatically, !isAdoptingText,
                  let textView = notification.object as? NSTextView,
                  textView.window?.firstResponder === textView else { return }
            parent.onCaretMove(textView.selectedRange().location)
        }

        @objc func boundsDidChange(_ notification: Notification) {
            parent.controller.view(for: parent.side)?.lineNumberRuler?.needsDisplay = true
            parent.controller.didScroll(parent.side)
        }
    }
}

extension DiffTextView: @preconcurrency NSTextStorageDelegate {
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        cachedLineStarts = nil
        lineNumberRuler?.needsDisplay = true
    }
}
