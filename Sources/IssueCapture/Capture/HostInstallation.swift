import SwiftUI

public extension View {
    /// Installs a scene-local capture host only when explicitly enabled.
    func issueCaptureHost(configuration: IssueCaptureConfiguration = .init()) -> some View {
        modifier(CaptureHostModifier(configuration: configuration))
    }
}

private struct CaptureHostModifier: ViewModifier {
    let configuration: IssueCaptureConfiguration

    @ViewBuilder func body(content: Content) -> some View {
        if configuration.isEnabled {
            EnabledCaptureHost(configuration: configuration) { content }
        } else {
            content
        }
    }
}

private struct EnabledCaptureHost<Content: View>: View {
    @StateObject private var session: CaptureSession
    let content: Content

    init(configuration: IssueCaptureConfiguration, @ViewBuilder content: () -> Content) {
        _session = StateObject(wrappedValue: CaptureSession(configuration: configuration))
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.captureSession, session)
            .environment(\.issueReporter, IssueReporter(recorder: session.recorder, screen: nil))
            .background(WindowAttachment(session: session).frame(width: 0, height: 0))
    }
}

private struct WindowAttachment: UIViewRepresentable {
    let session: CaptureSession

    func makeUIView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.session = session
        return view
    }
    func updateUIView(_ uiView: AttachmentView, context: Context) {}
    static func dismantleUIView(_ uiView: AttachmentView, coordinator: ()) {
        uiView.session?.overlay?.detach()
        uiView.session?.overlay = nil
    }
}

private final class AttachmentView: UIView {
    weak var session: CaptureSession?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let window, let scene = window.windowScene, let session else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard self?.window === window, let window else { return }
            if session.overlay != nil { return }
            session.hostWindow = window
            session.recorder.setSceneID(scene.session.persistentIdentifier)
            let overlay = CaptureOverlayController(session: session, scene: scene)
            session.overlay = overlay
            overlay.attach()
        }
    }
}
