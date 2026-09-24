import Foundation

/// Reporter-selected work type.
public enum IssueKind: String, Codable, CaseIterable, Sendable {
    case bug
    case featureRequest

    /// Human-readable label.
    public var title: String { self == .bug ? "Bug" : "Feature request" }
}

/// Product the request concerns.
public enum IssueTarget: String, Codable, CaseIterable, Sendable {
    case hostApp
    case issueCapture

    /// Human-readable label.
    public var title: String { self == .hostApp ? "Host app" : "IssueCapture" }
}

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

    /// Creates a screen context. Callers supply identity explicitly; it is
    /// never inferred from UIKit internals.
    public init(id: UUID, stableID: String?, name: String, typeName: String,
                file: String, line: UInt, parentID: UUID?) {
        self.id = id
        self.stableID = stableID
        self.name = name
        self.typeName = typeName
        self.file = file
        self.line = line
        self.parentID = parentID
    }
}

/// A point expressed in screenshot-relative coordinates.
public struct IssuePoint: Codable, Sendable {
    /// Horizontal fraction in 0...1.
    public var x: Double
    /// Vertical fraction in 0...1.
    public var y: Double

    /// Creates a normalized point.
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
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

    /// Creates an annotation path.
    public init(id: UUID = UUID(), kind: Kind, points: [IssuePoint]) {
        self.id = id
        self.kind = kind
        self.points = points
    }
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
    /// Optional storage supports reports created before tags were introduced.
    public var tags: [String]? = nil
    /// Nil decodes legacy reports as bugs.
    public var kind: IssueKind? = nil
    /// Nil decodes legacy reports as host-app reports.
    public var target: IssueTarget? = nil
    /// Work type, with legacy default.
    public var effectiveKind: IssueKind { kind ?? .bug }
    /// Target product, with legacy default.
    public var effectiveTarget: IssueTarget { target ?? .hostApp }
    /// Short label for human-readable lists; UUID remains authoritative.
    public var displayID: String { "ISSUE-" + id.uuidString.prefix(8) }

    /// Creates a report. Parameter order matches the stored field order.
    public init(schemaVersion: Int = 1, id: UUID = UUID(), projectID: String,
                capturedAt: Date = Date(), updatedAt: Date = Date(), description: String = "",
                expectedBehavior: String = "", reproductionNotes: String = "",
                screens: [IssueScreenContext], contextStatus: String,
                environment: [String: String], events: [IssueEvent], captureStatus: String,
                annotations: [IssueAnnotation] = [], exportPreparedAt: [Date] = [],
                hasScreenshot: Bool, hasAttachment: Bool = false, tags: [String]? = nil,
                kind: IssueKind? = nil, target: IssueTarget? = nil) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.projectID = projectID
        self.capturedAt = capturedAt
        self.updatedAt = updatedAt
        self.description = description
        self.expectedBehavior = expectedBehavior
        self.reproductionNotes = reproductionNotes
        self.screens = screens
        self.contextStatus = contextStatus
        self.environment = environment
        self.events = events
        self.captureStatus = captureStatus
        self.annotations = annotations
        self.exportPreparedAt = exportPreparedAt
        self.hasScreenshot = hasScreenshot
        self.hasAttachment = hasAttachment
        self.tags = tags
        self.kind = kind
        self.target = target
    }
}
