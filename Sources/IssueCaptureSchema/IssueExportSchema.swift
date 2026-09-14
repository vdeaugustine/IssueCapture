import Foundation

/// Image representations an export may contain.
///
/// Raw values are the keys used by `images.json`; readers must resolve that map
/// rather than assuming a file extension, because compressed copies use `.jpg`.
public enum IssueExportImageKind: String, CaseIterable, Codable, Sendable {
    case screenshot, attachment, annotation, card

    /// Human-readable label.
    public var title: String {
        switch self {
        case .screenshot: return "Screenshot"
        case .attachment: return "Attached image"
        case .annotation: return "Annotated image"
        case .card: return "Issue card"
        }
    }

    /// Filename stem used by the exporter before the encoded extension is added.
    public var basename: String {
        switch self {
        case .screenshot: return "screenshot-original"
        case .attachment: return "attachment"
        case .annotation: return "screenshot-annotated"
        case .card: return "issue-card"
        }
    }
}

/// Top-level description of an export folder or archive.
///
/// Dates use Foundation's default `Codable` encoding: seconds since the
/// 2001-01-01T00:00:00Z reference date.
public struct IssueExportManifest: Codable, Sendable {
    /// One entry per exported issue.
    public struct Item: Codable, Sendable {
        /// Authoritative pairing key; equals the report's own `id`.
        public let id: UUID
        /// Archive-relative path of the issue's JSON report.
        public let report: String

        /// Creates a manifest entry.
        public init(id: UUID, report: String) {
            self.id = id
            self.report = report
        }
    }

    /// Export format version; readers reject versions they do not implement.
    public let schemaVersion: Int
    /// Local preparation time. This does not establish delivery.
    public let exportedAt: Date
    /// Declared issues, in writer order.
    public let issues: [Item]

    /// Creates an export manifest.
    public init(schemaVersion: Int, exportedAt: Date, issues: [Item]) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.issues = issues
    }
}

/// Format versions this package writes and accepts.
public enum IssueExportSchema {
    /// Manifest version produced by the current exporter.
    public static let manifestVersion = 1
    /// Report version produced by the current capture build.
    public static let reportVersion = 1
    /// Manifest versions a reader may interpret.
    public static let supportedManifestVersions: Set<Int> = [1]
    /// Report versions a reader may interpret.
    public static let supportedReportVersions: Set<Int> = [1]

    /// Canonical encoder for schema payloads: stable key order, readable output.
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

/// Screen-context confidence strings written by the capture build.
///
/// These are exact recorded values, not inferred classifications. Only
/// ``accepted`` documents a single unambiguous registered candidate.
public enum IssueContextStatus {
    /// Exactly one registered leaf candidate was active at capture time.
    public static let accepted = "registered candidate; lifecycle visibility unverified"
    /// No screen registration covered the capture.
    public static let missing = "missing screen registration"
    /// More than one registered leaf candidate was active.
    public static let ambiguous = "ambiguous: multiple active candidates"
}
