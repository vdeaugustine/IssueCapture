import SwiftUI

struct ReporterRoot: View {
    @Bindable var session: CaptureSession
    let destination: CaptureOverlayController.Destination

    var body: some View {
        NavigationStack {
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

struct DiagnosticsView: View {
    let session: CaptureSession
    let onClose: () -> Void

    var body: some View {
        List {
            Section("Registered screen candidates") {
                if session.screens.isEmpty { Text("No registered screen. Add issueCaptureScreen to a destination.") }
                ForEach(session.screens) { screen in
                    VStack(alignment: .leading) {
                        Text(screen.name).font(.headline)
                        Text(screen.typeName).font(.caption)
                        Text("\(screen.file):\(screen.line)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Recent events — frozen while reporter is open") {
                ForEach(session.recorder.snapshot().reversed()) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.name).font(.headline)
                        Text("\(event.category) · \(event.screen?.name ?? "⚠ Unscoped event")").font(.caption)
                        Text(event.timestamp, style: .time).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Diagnostics")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button("Capture IssueCapture screen", systemImage: "ladybug") {
                    session.captureReporter()
                }
            }
            ToolbarItem(placement: .confirmationAction) { Button("Done", action: onClose) }
        }
    }
}
