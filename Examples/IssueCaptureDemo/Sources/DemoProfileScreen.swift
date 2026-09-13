import SwiftUI
import IssueCapture

struct DemoProfileScreen: IssueReportableScreen {
    var body: some View {
        DemoProfileContent().issueCaptureScreen(Self.self)
    }
}

private struct DemoProfileContent: View {
    @Environment(\.issueReporter) private var reporter
    @State private var name = "Taylor"
    @State private var biography = "Building something useful."
    @State private var saveFailed = false

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Name", text: $name)
                TextField("Biography", text: $biography, axis: .vertical)
            }
            Section {
                Button("Save profile") {
                    reporter.record(.tap("profile.save"))
                    saveFailed = true
                    reporter.record(.outcome("profile.save_failed", metadata: ["reason": "demo_failure"]))
                }
                if saveFailed {
                    Label("Could not save profile. This is the demo issue.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Edit profile")
    }
}
