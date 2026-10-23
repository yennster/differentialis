import SwiftUI
import AppKit

/// An editable plain-text code view. SwiftUI's `TextEditor` follows the system text settings, so
/// on a default install it turns typed quotes into curly quotes and `--` into an em dash; this
/// view turns every substitution off, like the paste editors, so the text is saved as typed.
struct PlainCodeEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var accessibilityLabel: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollablePlainDocumentContentTextView()
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.configureForPlainCode()
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        textView.setAccessibilityLabel(accessibilityLabel)
        textView.string = text
        textView.font = font
        textView.delegate = context.coordinator
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Compare code units, not Strings: String equality treats precomposed and decomposed
        // characters as equal, but they save as different bytes.
        if !(textView.string as NSString).isEqual(to: text) {
            // A change made outside the editor (Reset from Review, a new merge) is adopted wholesale.
            // Its undo history was recorded against the old text, so drop it rather than let an
            // undo edit the wrong range of the new text.
            // Close any open typing action first, or the next keystroke would extend the one just
            // removed and undo would skip it.
            textView.breakUndoCoalescing()
            textView.string = text
            textView.font = font
            context.coordinator.textUndoManager.removeAllActions()
        } else if textView.font != font {
            textView.font = font
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainCodeEditor
        /// The editor's own undo stack, so no undo action outlives this text view on the window's
        /// shared undo manager.
        let textUndoManager = UndoManager()

        init(_ parent: PlainCodeEditor) { self.parent = parent }

        func undoManager(for view: NSTextView) -> UndoManager? { textUndoManager }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let string = textView.string
            if !(string as NSString).isEqual(to: parent.text) { parent.text = string }
        }
    }
}
