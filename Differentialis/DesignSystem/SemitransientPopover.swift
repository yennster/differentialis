import SwiftUI
import AppKit

/// Hosts SwiftUI content in an AppKit semi-transient popover.
///
/// SwiftUI's standard popover presentation is dismissed when the application resigns active.
/// AppKit's semi-transient behavior is a better fit for work-in-progress controls: switching to
/// another app leaves the popover in place, while interacting elsewhere in the positioning window
/// dismisses it normally.
struct SemitransientPopoverPresenter<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    var preferredEdge: NSRectEdge = .minY
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(
            isPresented: $isPresented,
            content: AnyView(content()),
            relativeTo: nsView,
            preferredEdge: preferredEdge)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.close()
    }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        private let popover = NSPopover()
        private let hostingController = NSHostingController(rootView: AnyView(EmptyView()))
        private var presentation: Binding<Bool>?

        override init() {
            super.init()
            popover.behavior = .semitransient
            popover.animates = true
            popover.delegate = self
            hostingController.sizingOptions = [.preferredContentSize]
            popover.contentViewController = hostingController
        }

        func update(isPresented: Binding<Bool>, content: AnyView,
                    relativeTo view: NSView, preferredEdge: NSRectEdge) {
            presentation = isPresented
            hostingController.rootView = content

            if isPresented.wrappedValue {
                guard !popover.isShown, view.window != nil else { return }
                popover.show(relativeTo: view.bounds, of: view, preferredEdge: preferredEdge)
            } else if popover.isShown {
                popover.close()
            }
        }

        func close() {
            if popover.isShown { popover.close() }
            presentation = nil
        }

        func popoverDidClose(_ notification: Notification) {
            guard presentation?.wrappedValue == true else { return }
            DispatchQueue.main.async { [weak self] in
                self?.presentation?.wrappedValue = false
            }
        }
    }
}
