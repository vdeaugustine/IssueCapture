import SwiftUI

/// Scene-scoped commands for hosts that use their own reporting controls.
public struct IssueCaptureControl {
    let session: CaptureSession?

    /// Captures the current scene before opening the issue editor.
    @MainActor public func capture() { session?.capture() }

    /// Opens the local report inbox.
    @MainActor public func openInbox() { session?.overlay?.present(.inbox) }

    /// Opens screen and event coverage diagnostics.
    @MainActor public func openDiagnostics() { session?.overlay?.present(.diagnostics) }
}

public extension EnvironmentValues {
    /// Commands inherited from the nearest enabled capture host; disabled hosts are no-ops.
    var issueCapture: IssueCaptureControl { IssueCaptureControl(session: captureSession) }
}
