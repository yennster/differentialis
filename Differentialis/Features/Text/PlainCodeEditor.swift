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
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            // A change made outside the editor (Reset from Review, a new merge) is adopted wholesale.
            textView.string = text
            textView.font = font
        } else if textView.font != font {
            textView.font = font
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainCodeEditor

        init(_ parent: PlainCodeEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let string = textView.string
            if parent.text != string { parent.text = string }
        }
    }
}
