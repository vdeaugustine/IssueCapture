import Foundation

/// Identity of one mounted, explicitly registered screen.
public struct IssueScreenContext: Codable, Identifiable, Sendable, Equatable {
    /// Mounted instance identity.
    public let id: UUID
    /// Optional identity stable across source renames.
    public let stableID: String?
    /// Display label supplied by the screen protocol.
    public let name: String
    /// Qualified Swift type name.
    public let typeName: String
    /// Registration source file.
    public let file: String
    /// Registration source line.
    public let line: UInt
    /// Enclosing registered screen, if available.
    public let parentID: UUID?
}

/// A point expressed in screenshot-relative coordinates.
public struct IssuePoint: Codable, Sendable {
    /// Horizontal fraction in 0...1.
    public var x: Double
    /// Vertical fraction in 0...1.
    public var y: Double
}

/// Editable drawing saved independently of original evidence.
public struct IssueAnnotation: Codable, Identifiable, Sendable {
    /// Supported markup primitives.
    public enum Kind: String, Codable, CaseIterable, Sendable { case arrow, rectangle, pen }
    /// Stable annotation identity.
    public var id = UUID()
    /// Drawing tool.
    public var kind: Kind
    /// Normalized path coordinates.
    public var points: [IssuePoint]
}

/// Durable issue record. Image bytes live alongside this metadata.
public struct IssueReport: Codable, Identifiable, Sendable {
    /// Serialization format version.
    public var schemaVersion = 1
    /// Globally unique pairing key for report assets.
    public var id = UUID()
    /// Host application's project identifier.
    public var projectID: String
    /// Original capture time.
    public var capturedAt = Date()
    /// Last saved modification time.
    public var updatedAt = Date()
    /// User-authored problem description.
    public var description = ""
    /// Optional user-authored expected result.
    public var expectedBehavior = ""
    /// Optional user-authored reproduction notes.
    public var reproductionNotes = ""
    /// Registered capture candidates, preserving ambiguity.
    public var screens: [IssueScreenContext]
    /// Explicit context confidence, never inferred from screenshot pixels.
    public var contextStatus: String
    /// Frozen metadata collected before opening the editor.
    public var environment: [String: String]
    /// Frozen recent event history.
    public var events: [IssueEvent]
    /// Capture fidelity description; successful rendering is not verified fidelity.
    public var captureStatus: String
    /// Editable annotation paths.
    public var annotations: [IssueAnnotation] = []
    /// Times an export was prepared; this does not establish delivery.
    public var exportPreparedAt: [Date] = []
    /// Whether an original app snapshot exists.
    public var hasScreenshot: Bool
    /// Whether a separately attached image exists.
    public var hasAttachment = false
    /// Short label for human-readable lists; UUID remains authoritative.
    public var displayID: String { "ISSUE-" + id.uuidString.prefix(8) }
}
