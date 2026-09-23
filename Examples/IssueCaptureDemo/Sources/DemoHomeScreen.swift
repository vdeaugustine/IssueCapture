import SwiftUI
import IssueCapture

struct DemoHomeScreen: IssueReportableScreen {
    var body: some View {
        DemoHomeContent().issueCaptureScreen(Self.self)
    }
}

private struct DemoHomeContent: View {
    @Environment(\.issueReporter) private var reporter
    @Environment(\.issueCapture) private var capture
    @State private var presentation: Presentation?
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Label("IssueCapture", systemImage: "ladybug.fill").font(.largeTitle.bold())
                    Text("Capture a problem while it is visible. Keep its screenshot, notes, and recent actions together.")
                        .foregroundStyle(.secondary)
                }
                Section("Try the reporting flow") {
                    Button("Open profile editor") {
                        reporter.record(.navigation("profile.open"))
                        path.append("profile")
                    }
                    Button("Present profile as sheet") {
                        reporter.record(.tap("profile.present_sheet"))
                        presentation = .profile
                    }
                    Button("Capture this screen") { capture.capture() }
                    Button("Open issue inbox") { capture.openInbox() }
                    Button("Inspect diagnostics") { capture.openDiagnostics() }
                }
                Section("Capture tab") {
                    Text("Tap the capture button to report an issue. Drag it to either edge. Hold for saved issues, button appearance, and diagnostics.")
                    Text("The example intentionally shows a failed Save operation. Capture it and export the report.")
                }
            }
            .navigationTitle("QA playground")
            .navigationDestination(for: String.self) { _ in DemoProfileScreen() }
            .sheet(item: $presentation) { _ in NavigationStack { DemoProfileScreen() } }
        }
    }

    private enum Presentation: String, Identifiable {
        case profile
        var id: String { rawValue }
    }
}
