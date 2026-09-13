import SwiftUI
import IssueCapture

@main
struct IssueCaptureDemoApp: App {
    private var configuration: IssueCaptureConfiguration {
        #if DEBUG || INTERNAL_QA
        .init(isEnabled: true, projectID: "IssueCaptureDemo")
        #else
        .init()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            DemoHomeScreen()
                .issueCaptureHost(configuration: configuration)
        }
    }
}
