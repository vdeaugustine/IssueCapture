import Foundation

/// Explicit host opt-in. Disabled configurations install no recording or storage services.
public struct IssueCaptureConfiguration {
    /// Whether this host build permits issue capture.
    public var isEnabled: Bool
    /// Stable identifier used to group reports from this application.
    public var projectID: String
    /// Maximum recent events retained per host scene.
    public var eventLimit: Int
    /// Maximum encoded event bytes retained per host scene.
    public var eventByteLimit: Int
    /// Whether the package displays its edge tab. Custom host controls remain available.
    public var showsCaptureTab: Bool
    /// Initial appearance of the floating capture control.
    public var captureButtonAppearance: CaptureButtonAppearance
    /// Optional build revision supplied by the application.
    public var sourceRevision: String?

    /// Creates a configuration; capture is off unless explicitly enabled by the host.
    public init(isEnabled: Bool = false, projectID: String = Bundle.main.bundleIdentifier ?? "app",
                eventLimit: Int = 50, eventByteLimit: Int = 262_144, sourceRevision: String? = nil,
                showsCaptureTab: Bool = true,
                captureButtonAppearance: CaptureButtonAppearance = .init()) {
        self.captureButtonAppearance = captureButtonAppearance
        self.isEnabled = isEnabled
        self.projectID = projectID
        self.eventLimit = max(1, min(eventLimit, 1_000))
        self.eventByteLimit = max(1_024, min(eventByteLimit, 1_048_576))
        self.sourceRevision = sourceRevision
        self.showsCaptureTab = showsCaptureTab
    }
}
