import AppKit
import SwiftUI

/// A drag source that exposes several real file URLs at once.
///
/// SwiftUI's single-item drag cannot carry a request's Markdown plus its
/// images together, and Markdown links alone do not attach images in chat
/// tools, so the drag must expose actual file URLs.
struct FileDragView: NSViewRepresentable {
    /// Files exposed by the drag, in order.
    var urls: [URL]
    /// What the user sees and grabs.
    var label: AnyView

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        view.urls = urls
        view.embed(label)
        return view
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {
        nsView.urls = urls
        nsView.embed(label)
    }

    /// Hosts the label and begins a multi-file dragging session.
    final class DragSourceView: NSView, NSDraggingSource {
        var urls: [URL] = []
        private var hosting: NSHostingView<AnyView>?

        func embed(_ label: AnyView) {
            if let hosting {
                hosting.rootView = label
                return
            }
            let hosting = NSHostingView(rootView: label)
            hosting.translatesAutoresizingMaskIntoConstraints = false
            addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
                hosting.topAnchor.constraint(equalTo: topAnchor),
                hosting.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            self.hosting = hosting
        }

        override func mouseDown(with event: NSEvent) {
            guard !urls.isEmpty else { return }
            let items: [NSDraggingItem] = urls.enumerated().compactMap { index, url in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let image = NSWorkspace.shared.icon(forFile: url.path)
                let origin = NSPoint(x: bounds.midX - 16 + CGFloat(index) * 6,
                                     y: bounds.midY - 16 - CGFloat(index) * 6)
                item.setDraggingFrame(NSRect(origin: origin, size: NSSize(width: 32, height: 32)),
                                      contents: image)
                return item
            }
            beginDraggingSession(with: items, event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            [.copy]
        }
    }
}
