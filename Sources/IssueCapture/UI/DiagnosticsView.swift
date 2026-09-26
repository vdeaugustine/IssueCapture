import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var session: CaptureSession
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
            ToolbarItem(placement: .reporterSecondaryAction) {
                ReporterLabelButton("Capture IssueCapture screen", systemImage: "ladybug") {
                    session.captureReporter()
                }
            }
            ToolbarItem(placement: .confirmationAction) { Button("Done", action: onClose) }
        }
    }
}
