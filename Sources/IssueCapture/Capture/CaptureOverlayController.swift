import SwiftUI

@MainActor
final class CaptureOverlayController: UIViewController {
    enum Destination { case editor, inbox, diagnostics }
    private weak var session: CaptureSession?
    private let scene: UIWindowScene
    private var overlayWindow: PassthroughWindow?
    private weak var reporterController: UIHostingController<ReporterRoot>?
    private var destination: Destination = .editor
    private weak var previousKeyWindow: UIWindow?
    private var previousAccessibilityHidden: Bool?
    private let button = UIButton(type: .system)
    private var position = CGPoint(x: 1, y: 0.5)
    private var positionKey: String { "IssueCapture.tab." + scene.session.persistentIdentifier }
    private let reporterScreenID = UUID()

    init(session: CaptureSession, scene: UIWindowScene) {
        self.session = session
        self.scene = scene
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(session:scene:)") }

    func attach() {
        let window = PassthroughWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = self
        window.backgroundColor = .clear
        window.isHidden = false
        overlayWindow = window
    }

    func detach() {
        dismiss(animated: false)
        overlayWindow?.isHidden = true
        overlayWindow?.rootViewController = nil
        overlayWindow = nil
        reporterController = nil
        previousKeyWindow?.makeKey()
        restoreAccessibility()
        session?.recorder.setSuspended(false)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let stored = UserDefaults.standard.dictionary(forKey: positionKey)
        position = CGPoint(x: stored?["x"] as? Double ?? 1, y: stored?["y"] as? Double ?? 0.5)
        button.configuration = .filled()
        button.configuration?.image = UIImage(systemName: "ladybug.fill")
        button.configuration?.baseBackgroundColor = .systemIndigo
        button.configuration?.cornerStyle = .capsule
        button.accessibilityLabel = "Record issue"
        button.accessibilityHint = "Double tap to capture. Touch and hold for inbox and diagnostics."
        button.addAction(UIAction { [weak self] _ in self?.session?.capture() }, for: .touchUpInside)
        button.menu = UIMenu(children: [
            UIAction(title: "Issue inbox", image: UIImage(systemName: "tray.full")) { [weak self] _ in self?.present(.inbox) },
            UIAction(title: "Diagnostics", image: UIImage(systemName: "waveform.path")) { [weak self] _ in self?.present(.diagnostics) }
        ])
        button.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(drag(_:))))
        button.isHidden = session?.configuration.showsCaptureTab == false
        view.addSubview(button)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.bounds.inset(by: view.safeAreaInsets).insetBy(dx: 6, dy: 6)
        button.frame = CGRect(x: position.x < 0.5 ? safe.minX : max(safe.minX, safe.maxX - 48),
                              y: safe.minY + max(0, safe.height - 48) * position.y, width: 48, height: 48)
    }

    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: view)
        let safe = view.bounds.inset(by: view.safeAreaInsets).insetBy(dx: 6, dy: 6)
        position.x = point.x < view.bounds.midX ? 0 : 1
        position.y = min(1, max(0, (point.y - safe.minY - 24) / max(1, safe.height - 48)))
        view.setNeedsLayout()
        if gesture.state == .ended {
            UserDefaults.standard.set(["x": position.x, "y": position.y], forKey: positionKey)
        }
    }

    func present(_ destination: Destination) {
        guard presentedViewController == nil, let session else { return }
        self.destination = destination
        session.isPresenting = true
        session.recorder.setSuspended(true)
        previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        previousAccessibilityHidden = session.hostWindow?.accessibilityElementsHidden ?? false
        session.hostWindow?.accessibilityElementsHidden = true
        overlayWindow?.isModal = true
        overlayWindow?.makeKey()
        let controller = UIHostingController(rootView: ReporterRoot(session: session, destination: destination))
        reporterController = controller
        controller.modalPresentationStyle = .fullScreen
        controller.view.accessibilityViewIsModal = true
        present(controller, animated: true)
    }

    func captureReporter() {
        guard let session, let overlayWindow else { return }
        session.prepareReporterDraft(window: overlayWindow, screen: reporterScreenContext)
    }

    func showEditor() {
        guard let session, let reporterController else { return }
        destination = .editor
        reporterController.rootView = ReporterRoot(session: session, destination: .editor)
    }

    private var reporterScreenContext: IssueScreenContext {
        let screenName: String
        let typeName: String
        switch destination {
        case .editor:
            screenName = "IssueCapture editor"
            typeName = "IssueCapture.IssueEditor"
        case .inbox:
            screenName = "IssueCapture inbox"
            typeName = "IssueCapture.IssueInbox"
        case .diagnostics:
            screenName = "IssueCapture diagnostics"
            typeName = "IssueCapture.DiagnosticsView"
        }
        return IssueScreenContext(id: reporterScreenID, stableID: "issue-capture.\(screenName)",
                                  name: screenName, typeName: typeName,
                                  file: "IssueCapture", line: 0, parentID: nil)
    }

    private func restoreAccessibility() {
        guard let previousAccessibilityHidden else { return }
        session?.hostWindow?.accessibilityElementsHidden = previousAccessibilityHidden
        self.previousAccessibilityHidden = nil
    }

    func close() {
        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.overlayWindow?.isModal = false
            self.previousKeyWindow?.makeKey()
            self.restoreAccessibility()
            self.session?.isPresenting = false
            self.session?.recorder.setSuspended(false)
            self.session?.draft = nil
            self.session?.draftImage = nil
            self.session?.draftAttachment = nil
            self.reporterController = nil
        }
    }
}

private final class PassthroughWindow: UIWindow {
    var isModal = false
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if !isModal && hit === rootViewController?.view { return nil }
        return hit
    }
}
