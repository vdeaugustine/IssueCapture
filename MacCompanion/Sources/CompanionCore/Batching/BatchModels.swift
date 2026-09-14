import Foundation
import IssueCaptureSchema

/// Exact recorded build metadata used to partition candidate requests.
///
/// Values are compared exactly. Absent values, and the literal `"unavailable"`
/// the capture build writes when Info.plist lookup fails, are treated as
/// missing and keep their issues in a partition of their own.
public struct EnvironmentPartitionKey: Codable, Hashable, Sendable, Comparable {
    /// Environment keys read from the capture implementation.
    public static let partitionKeys = ["appVersion", "build"]
    /// Sentinel the capture build writes when a value could not be read.
    public static let unavailableSentinel = "unavailable"

    /// Exact recorded marketing version, or nil when not recorded.
    public let appVersion: String?
    /// Exact recorded build number, or nil when not recorded.
    public let build: String?

    /// Creates a partition key.
    public init(appVersion: String?, build: String?) {
        self.appVersion = appVersion
        self.build = build
    }

    /// Derives the key from a report's frozen environment.
    public init(environment: [String: String]) {
        self.init(appVersion: Self.value(environment["appVersion"]),
                  build: Self.value(environment["build"]))
    }

    /// Normalizes a recorded environment value, mapping the sentinel to nil.
    public static func value(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, raw != unavailableSentinel else { return nil }
        return raw
    }

    /// Whether both version fields were recorded.
    public var isComplete: Bool { appVersion != nil && build != nil }

    /// Label suitable for lists; states plainly when metadata is missing.
    public var label: String {
        switch (appVersion, build) {
        case let (version?, build?): return "\(version) (\(build))"
        case let (version?, nil): return "\(version) (build not recorded)"
        case let (nil, build?): return "version not recorded (\(build))"
        default: return "build metadata not recorded"
        }
    }

    /// Deterministic sort/identity token.
    public var token: String { "\(appVersion ?? "-")|\(build ?? "-")" }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.token < rhs.token }
}

/// Why a candidate request contains what it contains.
///
/// Reasons explain a grouping rule. They never claim the issues share a root
/// cause.
public struct BatchReason: Codable, Sendable, Hashable, Identifiable {
    /// Stable rule identifiers.
    public enum Code: String, Codable, Sendable {
        /// Grouped by an explicit user-assigned `batch:` tag.
        case explicitBatchTag
        /// Grouped by an exact shared registered screen key.
        case sharedScreen
        /// Left alone because the issue is the only member of its group.
        case singleIssue
        /// Left alone because screen context is ambiguous.
        case ambiguousScreen
        /// Left alone because no screen registration covered the capture.
        case unregisteredScreen
        /// Left alone because the recorded context status is not a documented
        /// accepted value.
        case unrecognizedContextStatus
        /// Left alone because the issue carries conflicting `batch:` tags.
        case batchTagConflict
        /// The group exceeded the configured cap and was split.
        case capSplit
        /// Membership was set by an explicit user decision.
        case manualAssignment
        /// A manual decision no longer applies to the current revision.
        case staleManualAssignment
    }

    /// Stable identity for list presentation.
    public var id: String { "\(code.rawValue)|\(detail)" }
    /// Rule identifier.
    public let code: Code
    /// Exact explanation shown next to the grouping.
    public let detail: String

    /// Creates a reason.
    public init(code: Code, detail: String) {
        self.code = code
        self.detail = detail
    }
}

/// A non-merging hint that two issues may be related.
///
/// Ordinary tags and shared event identifiers can explain a relationship but
/// never merge candidate requests by themselves, and never chain transitively.
public struct RelatedNote: Codable, Sendable, Hashable, Identifiable {
    /// What the two issues have in common.
    public enum Kind: String, Codable, Sendable { case sharedTag, sharedEventID }

    /// Stable identity for list presentation.
    public var id: String { "\(kind.rawValue)|\(issueID.uuidString)|\(value)" }
    /// Relationship category.
    public let kind: Kind
    /// The other issue.
    public let issueID: UUID
    /// Exact shared value.
    public let value: String

    /// Creates a related-item note.
    public init(kind: Kind, issueID: UUID, value: String) {
        self.kind = kind
        self.issueID = issueID
        self.value = value
    }
}

/// One issue revision considered for batching.
public struct BatchMember: Codable, Sendable, Hashable, Identifiable {
    /// Issue identity plus revision pins the exact evidence considered.
    public var id: String { "\(key.issueID.uuidString)|\(revisionID)" }
    /// Issue identity.
    public let key: IssueKey
    /// Exact revision this membership refers to.
    public let revisionID: String
    /// Capture time used for ordering.
    public let capturedAt: Date
    /// Short human label; the UUID stays authoritative.
    public let displayID: String

    /// Creates a member reference.
    public init(key: IssueKey, revisionID: String, capturedAt: Date, displayID: String) {
        self.key = key
        self.revisionID = revisionID
        self.capturedAt = capturedAt
        self.displayID = displayID
    }
}

/// A proposed request. Proposing is not preparing and not sending.
public struct CandidateBatch: Codable, Sendable, Hashable, Identifiable {
    /// How the membership was decided.
    public enum Origin: String, Codable, Sendable { case rule, manual }

    /// Deterministic identity derived from the rule inputs.
    public let id: String
    /// Rule engine version that produced this proposal.
    public let ruleVersion: String
    /// Project partition; projects are never mixed automatically.
    public let projectID: String
    /// Build partition.
    public let environmentKey: EnvironmentPartitionKey
    /// Ordered membership.
    public let members: [BatchMember]
    /// Explanations for this grouping.
    public let reasons: [BatchReason]
    /// Non-merging relationship hints.
    public let relatedNotes: [RelatedNote]
    /// Rule-derived or user-decided.
    public let origin: Origin
    /// Human label for lists.
    public let title: String

    /// Creates a candidate batch.
    public init(id: String, ruleVersion: String, projectID: String,
                environmentKey: EnvironmentPartitionKey, members: [BatchMember],
                reasons: [BatchReason], relatedNotes: [RelatedNote], origin: Origin, title: String) {
        self.id = id
        self.ruleVersion = ruleVersion
        self.projectID = projectID
        self.environmentKey = environmentKey
        self.members = members
        self.reasons = reasons
        self.relatedNotes = relatedNotes
        self.origin = origin
        self.title = title
    }
}

/// User-tunable inputs to the rule engine. Preferences participate in
/// determinism: the same inputs, rule version and preferences always yield the
/// same memberships and ordering.
public struct BatchingPreferences: Codable, Sendable, Hashable {
    /// Maximum issues per rule-derived candidate request.
    public var maximumIssuesPerRequest: Int
    /// Tag prefix that marks an explicit user-assigned batch.
    public var batchTagPrefix: String

    /// Creates preferences.
    public init(maximumIssuesPerRequest: Int = 5, batchTagPrefix: String = "batch:") {
        self.maximumIssuesPerRequest = maximumIssuesPerRequest
        self.batchTagPrefix = batchTagPrefix
    }

    /// Documented defaults.
    public static let standard = BatchingPreferences()
}
