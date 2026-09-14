import Foundation
import IssueCaptureSchema

/// Identity of an issue inside the companion.
///
/// The short display ID is convenient for humans but is not unique; pairing and
/// external tracking always use the full UUID scoped to its project.
public struct IssueKey: Hashable, Codable, Sendable, Comparable {
    /// Host application's project identifier, exactly as recorded.
    public let projectID: String
    /// Authoritative issue UUID.
    public let issueID: UUID

    /// Creates an issue identity.
    public init(projectID: String, issueID: UUID) {
        self.projectID = projectID
        self.issueID = issueID
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.projectID, lhs.issueID.uuidString) < (rhs.projectID, rhs.issueID.uuidString)
    }
}

/// A problem that does not invalidate an import but must remain visible.
///
/// Warnings are never resolved by guessing; incomplete evidence is reported as
/// incomplete rather than presented as complete.
public struct ImportWarning: Codable, Sendable, Hashable, Identifiable {
    /// Stable machine-readable warning code.
    public enum Code: String, Codable, Sendable {
        /// A file named by `images.json` is absent from the received payload.
        case missingDeclaredImage
        /// The issue folder contains no `images.json`.
        case missingImageMap
        /// `images.json` names a kind this reader does not model.
        case unknownImageKind
        /// The report declares an asset that `images.json` does not name.
        case declaredAssetNotExported
        /// Environment lacks the app version/build keys used for partitioning.
        case missingBuildMetadata
    }

    /// Stable identity for list presentation.
    public var id: String { "\(code.rawValue)|\(detail)" }
    /// Warning category.
    public let code: Code
    /// Exact, actionable description including the affected names.
    public let detail: String

    /// Creates a warning.
    public init(code: Code, detail: String) {
        self.code = code
        self.detail = detail
    }
}

/// A condition that rejects an import outright.
public struct ImportFailure: Error, Codable, Sendable, Hashable, LocalizedError {
    /// Stable machine-readable failure code.
    public enum Code: String, Codable, Sendable {
        case unreadableSource
        case notAnExport
        case unsupportedManifestVersion
        case unsupportedReportVersion
        case malformedManifest
        case malformedReport
        case identityMismatch
        case duplicateIssueIdentity
        case unsafeArchivePath
        case unsupportedCompression
        case archiveLimitExceeded
        case checksumMismatch
        case sourceStillChanging
        case storageFailure
    }

    /// Failure category.
    public let code: Code
    /// Exact description of what was rejected.
    public let detail: String
    /// Whether retrying the same source may succeed without user repair.
    public let isRetryable: Bool

    /// Creates a failure.
    public init(code: Code, detail: String, isRetryable: Bool = false) {
        self.code = code
        self.detail = detail
        self.isRetryable = isRetryable
    }

    public var errorDescription: String? { detail }
}

/// Recorded facts about one stored evidence file.
public struct EvidenceFileFact: Codable, Sendable, Hashable {
    /// Filename exactly as declared by `images.json`.
    public let filename: String
    /// SHA-256 of the received bytes, lowercase hex.
    public let sha256: String
    /// Received byte count.
    public let byteCount: Int

    /// Creates a file fact.
    public init(filename: String, sha256: String, byteCount: Int) {
        self.filename = filename
        self.sha256 = sha256
        self.byteCount = byteCount
    }
}

/// Where an import came from, retained even when its content duplicates an
/// earlier import.
public struct ImportProvenance: Codable, Sendable, Identifiable, Hashable {
    /// How the export reached the companion.
    public enum SourceKind: String, Codable, Sendable { case archive, folder }

    /// Companion-assigned import identity.
    public let id: UUID
    /// Local receipt time. Receipt is not delivery, review, or resolution.
    public let receivedAt: Date
    /// Source path as presented by the user. Diagnostic only.
    public let sourceDescription: String
    /// Archive or expanded folder.
    public let sourceKind: SourceKind
    /// SHA-256 of the received archive bytes; absent for folder imports.
    public let archiveSHA256: String?
    /// Manifest version accepted for this import.
    public let manifestSchemaVersion: Int
    /// Export preparation time recorded by the writer.
    public let manifestExportedAt: Date
    /// Store-relative path of the preserved payload.
    public let payloadPath: String
    /// Issue identities declared by the manifest.
    public let declaredIssues: [IssueKey]

    /// Creates an import provenance record.
    public init(id: UUID, receivedAt: Date, sourceDescription: String, sourceKind: SourceKind,
                archiveSHA256: String?, manifestSchemaVersion: Int, manifestExportedAt: Date,
                payloadPath: String, declaredIssues: [IssueKey]) {
        self.id = id
        self.receivedAt = receivedAt
        self.sourceDescription = sourceDescription
        self.sourceKind = sourceKind
        self.archiveSHA256 = archiveSHA256
        self.manifestSchemaVersion = manifestSchemaVersion
        self.manifestExportedAt = manifestExportedAt
        self.payloadPath = payloadPath
        self.declaredIssues = declaredIssues
    }
}

/// One immutable version of an issue's evidence.
///
/// A revision is created when canonical report content or image bytes change
/// under an existing issue identity. Existing revisions are never overwritten.
public struct IssueRevision: Codable, Sendable, Identifiable, Hashable {
    /// Content fingerprint; stable for identical evidence.
    public let id: String
    /// Owning issue identity.
    public let issueKey: IssueKey
    /// Monotonic position within the issue, starting at 1.
    public let revisionIndex: Int
    /// Import that first produced this content.
    public let firstImportID: UUID
    /// Every import that carried this exact content, oldest first.
    public var importIDs: [UUID]
    /// Decoded report as received.
    public let report: IssueReport
    /// `images.json` exactly as received.
    public let declaredImages: [String: String]
    /// Facts about the image files that were actually present.
    public let files: [String: EvidenceFileFact]
    /// Issue-level problems observed while importing this revision.
    public let warnings: [ImportWarning]
    /// Store-relative path of the preserved issue folder.
    public let path: String

    /// Creates a revision record.
    public init(id: String, issueKey: IssueKey, revisionIndex: Int, firstImportID: UUID,
                importIDs: [UUID], report: IssueReport, declaredImages: [String: String],
                files: [String: EvidenceFileFact], warnings: [ImportWarning], path: String) {
        self.id = id
        self.issueKey = issueKey
        self.revisionIndex = revisionIndex
        self.firstImportID = firstImportID
        self.importIDs = importIDs
        self.report = report
        self.declaredImages = declaredImages
        self.files = files
        self.warnings = warnings
        self.path = path
    }

    /// Revisions are equal when they describe the same content of the same
    /// issue. The identifier is a content fingerprint, so this is exact.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.issueKey == rhs.issueKey
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(issueKey)
    }

    /// File fact for a modeled image kind, when that file was received.
    public func fact(for kind: IssueExportImageKind) -> EvidenceFileFact? { files[kind.rawValue] }

    /// Image kinds actually present in this revision, in declaration order.
    public var presentKinds: [IssueExportImageKind] {
        IssueExportImageKind.allCases.filter { files[$0.rawValue] != nil }
    }
}

/// Local workflow state. None of these states claim delivery by a transport.
public enum IssueLocalState: String, Codable, Sendable, CaseIterable {
    /// Received and not yet included in a prepared request.
    case inbox
    /// Included in at least one prepared request folder.
    case prepared
    /// The user asserts they handed the request to a coding tool.
    case sent
    /// The user asserts the issue is resolved.
    case resolved

    /// Short label for lists.
    public var title: String {
        switch self {
        case .inbox: return "Inbox"
        case .prepared: return "Prepared"
        case .sent: return "Marked sent"
        case .resolved: return "Marked resolved"
        }
    }
}
