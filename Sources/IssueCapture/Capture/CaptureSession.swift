import SwiftUI
import Combine

@MainActor
final class CaptureSession: ObservableObject {
    let identity = UUID()
    let configuration: IssueCaptureConfiguration
    @Published var buttonAppearance: CaptureButtonAppearance
    let recorder: IssueRecorder
    @Published var screens: [IssueScreenContext] = []
    @Published var reports: [IssueReport] = []
    @Published var errorMessage: String?
    @Published var draft: IssueReport?
    @Published var draftImage: UIImage?
    @Published var draftAttachment: UIImage?
    @Published var isBusy = false
    @Published var isPresenting = false
    weak var hostWindow: UIWindow?
    var overlay: CaptureOverlayController?
    private var externalCapturePending = false

    init(configuration: IssueCaptureConfiguration) {
        self.configuration = configuration
        buttonAppearance = configuration.captureButtonAppearance
        recorder = IssueRecorder(configuration: configuration)
    }

    func register(_ context: IssueScreenContext) {
        guard !screens.contains(where: { $0.id == context.id }) else { return }
        screens.append(context)
        recorder.record(.init(category: "screen.enter", name: context.name), screen: context,
                        file: context.file, line: context.line)
    }

    func unregister(_ id: UUID) {
        guard let context = screens.first(where: { $0.id == id }) else { return }
        screens.removeAll { $0.id == id }
        recorder.record(.init(category: "screen.exit", name: context.name), screen: context,
                        file: context.file, line: context.line)
    }

    private var activeContextStatus: String {
        let candidates = screens.filter { screen in !screens.contains { $0.parentID == screen.id } }
        return candidates.count == 1 ? IssueContextStatus.accepted
            : candidates.isEmpty ? IssueContextStatus.missing : IssueContextStatus.ambiguous
    }

    func capture() {
        guard !isPresenting, !isBusy else { return }
        let events = recorder.snapshot()
        prepareDraft(window: hostWindow, screens: screens, contextStatus: activeContextStatus,
                     events: events, captureSurface: "host-app")
        overlay?.present(.editor)
    }

    func beginExternalCapture() -> Bool {
        guard !isPresenting, !isBusy, overlay != nil else { return false }
        prepareDraft(window: hostWindow, screens: screens, contextStatus: activeContextStatus,
                     events: recorder.snapshot(), captureSurface: "unity-frame",
                     suppliedSnapshot: (nil, "pending Unity end-of-frame capture"))
        externalCapturePending = true
        isBusy = true
        return true
    }

    func finishExternalCapture(image: UIImage?, status: String) {
        guard externalCapturePending else { return }
        externalCapturePending = false
        isBusy = false
        draftImage = image
        draft?.hasScreenshot = image != nil
        draft?.captureStatus = status
        overlay?.present(.editor)
    }

    func cancelExternalCapture() {
        guard externalCapturePending else { return }
        externalCapturePending = false
        isBusy = false
        draft = nil
        draftImage = nil
        recorder.setSuspended(false)
    }

    /// Captures the currently visible IssueCapture reporter instead of the host app.
    func captureReporter() {
        guard isPresenting, !isBusy else { return }
        overlay?.captureReporter()
    }

    func prepareReporterDraft(window: UIWindow, screen: IssueScreenContext) {
        guard isPresenting, !isBusy else { return }
        prepareDraft(window: window, screens: [screen], contextStatus: IssueContextStatus.accepted,
                     events: recorder.snapshot(), captureSurface: "issue-capture-reporter")
        overlay?.showEditor()
    }

    private func prepareDraft(window: UIWindow?, screens: [IssueScreenContext],
                              contextStatus: String, events: [IssueEvent],
                              captureSurface: String, suppliedSnapshot: (UIImage?, String)? = nil) {
        let capturedAt = Date()
        recorder.setSuspended(true)
        let snapshot = suppliedSnapshot ?? ScreenshotService.capture(window: window)
        var environment = ScreenshotService.environment(window: window, configuration: configuration)
        environment["captureSurface"] = captureSurface
        draft = IssueReport(projectID: configuration.projectID, capturedAt: capturedAt,
            screens: screens, contextStatus: contextStatus, environment: environment,
            events: events, captureStatus: snapshot.1, hasScreenshot: snapshot.0 != nil,
            kind: .bug, target: captureSurface == "issue-capture-reporter" ? .issueCapture : .hostApp)
        draftImage = snapshot.0
        draftAttachment = nil
    }

    func refresh() async {
        do { reports = try await ReportStore.shared.list(projectID: configuration.projectID) }
        catch { errorMessage = error.localizedDescription }
    }

    func edit(_ report: IssueReport) async {
        do {
            draftImage = try await ReportStore.shared.image(report).flatMap(UIImage.init(data:))
            draftAttachment = try await ReportStore.shared.image(report, attachment: true).flatMap(UIImage.init(data:))
            draft = report
        } catch { errorMessage = error.localizedDescription }
    }

    func save(_ report: IssueReport, attachment: UIImage?) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        var report = report
        report.updatedAt = Date()
        report.hasAttachment = attachment != nil
        do {
            let screenshot = report.hasScreenshot ? draftImage?.pngData() : nil
            let attachmentData = attachment?.pngData()
            try await ReportStore.shared.save(report, screenshot: screenshot, attachment: attachmentData)
            await refresh()
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
}
