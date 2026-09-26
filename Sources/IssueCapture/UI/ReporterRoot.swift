import SwiftUI

struct ReporterRoot: View {
    @ObservedObject var session: CaptureSession
    let destination: CaptureOverlayController.Destination

    var body: some View {
        ReporterNavigation {
            switch destination {
            case .editor:
                if let draft = session.draft {
                    IssueEditor(session: session, onFinish: close, report: draft, attachment: session.draftAttachment)
                }
            case .inbox:
                IssueInbox(session: session, onClose: close)
            case .appearance:
                CaptureButtonSettings(session: session, onClose: close)
            case .diagnostics:
                DiagnosticsView(session: session, onClose: close)
            }
        }
        .tint(.accentColor)
        .alert("IssueCapture", isPresented: Binding(get: { session.errorMessage != nil },
                                                    set: { if !$0 { session.errorMessage = nil } })) {
            Button("OK") { session.errorMessage = nil }
        } message: { Text(session.errorMessage ?? "") }
    }

    private func close() { session.overlay?.close() }
}
