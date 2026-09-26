import UIKit

/// Explicit UIKit host for game engines and applications without SwiftUI roots.
/// Keep one instance alive per app window. All lifecycle operations use the main actor.
@MainActor
public final class IssueCaptureNativeHost {
    private var session: CaptureSession?

    /// Installs into the supplied window. Disabled configurations allocate no session or overlay.
    /// Supports both scene-based and legacy UIApplication windows; retry after the window becomes visible.
    public init?(window: UIWindow, configuration: IssueCaptureConfiguration) {
        guard configuration.isEnabled else { session = nil; return }
        guard window.rootViewController != nil, !window.isHidden else { return nil }
        let scene = window.windowScene
        let session = CaptureSession(configuration: configuration)
        self.session = session
        session.hostWindow = window
        session.recorder.setSceneID(scene?.session.persistentIdentifier ?? "native-app-window")
        let overlay = CaptureOverlayController(session: session, scene: scene)
        session.overlay = overlay
        overlay.attach()
    }

    /// Whether the reporter currently owns presentation, including pending engine frame capture.
    public var isPresenting: Bool { session.map { $0.isPresenting || $0.isBusy } ?? false }

    /// Adds an explicitly active surface; repeated registration of an instance is idempotent.
    public func activate(_ context: IssueScreenContext) { session?.register(context) }

    /// Removes an active instance; reporters already obtained retain their original scope.
    public func deactivate(_ id: UUID) { session?.unregister(id) }

    /// Returns a scoped, thread-safe event sink without making the screen active.
    public func reporter(for context: IssueScreenContext) -> IssueReporter {
        IssueReporter(recorder: session?.recorder, screen: context)
    }

    /// Captures UIKit content. Engines should use beginFrameCapture/finishFrameCapture for GPU content.
    public func capture() { session?.capture() }

    /// Freezes screen/event context before an engine renders its next complete frame.
    /// Returns false if disabled or already reporting. Pair success with finish or cancel.
    public func beginFrameCapture() -> Bool { session?.beginExternalCapture() ?? false }

    /// Opens the same editor as SwiftUI hosts, using an engine-supplied image and honest fidelity status.
    public func finishFrameCapture(image: UIImage?, status: String) {
        session?.finishExternalCapture(image: image, status: status)
    }

    /// Abandons an unfinished frame request and resumes recording.
    public func cancelFrameCapture() { session?.cancelExternalCapture() }

    /// Presents saved reports and the standard text/PDF/ZIP export controls.
    public func openInbox() {
        guard let session, !isPresenting else { return }
        session.overlay?.present(.inbox)
    }

    /// Presents explicit screen candidates and bounded semantic events.
    public func openDiagnostics() {
        guard let session, !isPresenting else { return }
        session.overlay?.present(.diagnostics)
    }

    /// Detaches UI and permanently suspends retained reporters. Call before releasing this host.
    public func shutdown() {
        session?.cancelExternalCapture()
        session?.overlay?.detach()
        session?.overlay = nil
        session?.recorder.invalidate()
        session = nil
    }
}
