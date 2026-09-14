import Foundation
import IssueCaptureSchema

/// One attachment offered for drag-and-drop.
public struct PreparedAttachment: Codable, Sendable, Hashable, Identifiable {
    /// Request-relative path, which is also the identity.
    public var id: String { path }
    /// Request-folder-relative path of the file.
    public let path: String
    /// SHA-256 of the bytes, lowercase hex.
    public let sha256: String
    /// Byte count.
    public let byteCount: Int
    /// Kinds this file represents, one entry per linked issue.
    public let links: [Link]

    /// A single issue-to-image link retained even when bytes are deduplicated.
    public struct Link: Codable, Sendable, Hashable {
        /// Issue that declared this image.
        public let issueID: UUID
        /// Kind the issue declared it as.
        public let kind: IssueExportImageKind
        /// Filename exactly as the export declared it.
        public let declaredFilename: String

        /// Creates a link.
        public init(issueID: UUID, kind: IssueExportImageKind, declaredFilename: String) {
            self.issueID = issueID
            self.kind = kind
            self.declaredFilename = declaredFilename
        }
    }

    /// Creates an attachment record.
    public init(path: String, sha256: String, byteCount: Int, links: [Link]) {
        self.path = path
        self.sha256 = sha256
        self.byteCount = byteCount
        self.links = links
    }
}

/// One issue inside a prepared request, pinned to an exact revision.
public struct PreparedIssue: Codable, Sendable, Hashable, Identifiable {
    /// Full UUID; the authoritative identity.
    public var id: UUID { issueID }
    /// Full UUID.
    public let issueID: UUID
    /// Short human label. Not unique.
    public let displayID: String
    /// Exact revision whose evidence was snapshotted.
    public let revisionID: String
    /// Revision position within the issue.
    public let revisionIndex: Int
    /// Position within the request, starting at 1.
    public let order: Int
    /// Capture time.
    public let capturedAt: Date
    /// Request-relative folder holding this issue's received files.
    public let evidencePath: String
    /// Files copied into the evidence bundle, keyed by image kind.
    public let evidenceFiles: [String: EvidenceFileFact]
    /// Attachment decisions with their explanations.
    public let attachmentDecisions: [AttachmentDecision]
    /// Issue-level warnings carried forward from import.
    public let warnings: [ImportWarning]

    /// Creates a prepared issue record.
    public init(issueID: UUID, displayID: String, revisionID: String, revisionIndex: Int,
                order: Int, capturedAt: Date, evidencePath: String,
                evidenceFiles: [String: EvidenceFileFact],
                attachmentDecisions: [AttachmentDecision], warnings: [ImportWarning]) {
        self.issueID = issueID
        self.displayID = displayID
        self.revisionID = revisionID
        self.revisionIndex = revisionIndex
        self.order = order
        self.capturedAt = capturedAt
        self.evidencePath = evidencePath
        self.evidenceFiles = evidenceFiles
        self.attachmentDecisions = attachmentDecisions
        self.warnings = warnings
    }
}

/// The persistent, versioned record written as `request.json`.
///
/// Preparing a request is a local action. It does not deliver, fix or verify
/// anything.
public struct PreparedRequest: Codable, Sendable, Hashable, Identifiable {
    /// Version of the `request.md` template used.
    public static let templateVersion = "request-template-1"

    /// Request identity.
    public let id: UUID
    /// Project the issues belong to. Projects are never mixed automatically.
    public let projectID: String
    /// Build partition of the source batch.
    public let environmentKey: EnvironmentPartitionKey
    /// Local preparation time.
    public let preparedAt: Date
    /// Rule engine version that produced the source batch.
    public let ruleVersion: String
    /// Template version used to render `request.md`.
    public let templateVersion: String
    /// Source batch identity.
    public let batchID: String
    /// Human label of the source batch.
    public let title: String
    /// Why these issues were grouped.
    public let groupingReasons: [BatchReason]
    /// Non-merging relationship hints recorded at preparation time.
    public let relatedNotes: [RelatedNote]
    /// Ordered issues.
    public let issues: [PreparedIssue]
    /// Deduplicated external attachment set.
    public let attachments: [PreparedAttachment]
    /// Companion-authored instructions, kept separate from report content.
    public let instructions: String

    /// Number of distinct attachment files.
    public var attachmentCount: Int { attachments.count }
    /// Total attachment bytes.
    public var attachmentByteCount: Int { attachments.reduce(0) { $0 + $1.byteCount } }

    /// Creates a prepared request record.
    public init(id: UUID, projectID: String, environmentKey: EnvironmentPartitionKey,
                preparedAt: Date, ruleVersion: String, templateVersion: String, batchID: String,
                title: String, groupingReasons: [BatchReason], relatedNotes: [RelatedNote],
                issues: [PreparedIssue], attachments: [PreparedAttachment], instructions: String) {
        self.id = id
        self.projectID = projectID
        self.environmentKey = environmentKey
        self.preparedAt = preparedAt
        self.ruleVersion = ruleVersion
        self.templateVersion = templateVersion
        self.batchID = batchID
        self.title = title
        self.groupingReasons = groupingReasons
        self.relatedNotes = relatedNotes
        self.issues = issues
        self.attachments = attachments
        self.instructions = instructions
    }
}

/// A prepared request plus where it lives on disk.
public struct PreparedRequestHandle: Sendable, Identifiable, Hashable {
    /// Request identity.
    public var id: UUID { request.id }
    /// The persisted record.
    public let request: PreparedRequest
    /// Absolute folder containing `request.md`, `request.json` and `evidence/`.
    public let folder: URL

    /// Creates a handle.
    public init(request: PreparedRequest, folder: URL) {
        self.request = request
        self.folder = folder
    }

    /// Absolute URL of the request Markdown.
    public var markdownURL: URL { folder.appendingPathComponent("request.md") }

    /// Absolute URLs exposed by a drag: the request Markdown plus the chosen
    /// images. Markdown links alone do not attach images in chat tools.
    public var dragURLs: [URL] {
        [markdownURL] + request.attachments.map { folder.appendingPathComponent($0.path) }
    }
}

/// Local request status. None of these claim a transport delivered anything.
public enum RequestLocalState: String, Codable, Sendable, CaseIterable {
    /// The folder exists on disk.
    case prepared
    /// The user asserts they handed it to a coding tool.
    case sent
    /// The user asserts the work is resolved.
    case resolved

    /// Short label for lists.
    public var title: String {
        switch self {
        case .prepared: return "Prepared"
        case .sent: return "Marked sent"
        case .resolved: return "Marked resolved"
        }
    }
}
