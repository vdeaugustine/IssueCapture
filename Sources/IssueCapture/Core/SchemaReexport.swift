/// Shared, Foundation-only schema types are defined in `IssueCaptureSchema` so
/// that non-UIKit readers can decode exports without linking the capture UI.
/// Re-exporting keeps the public `import IssueCapture` API unchanged.
@_exported import IssueCaptureSchema
