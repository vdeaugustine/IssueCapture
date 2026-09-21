import Foundation
import IssueCaptureSchema

/// An explicit user decision to place one issue revision in a named group.
///
/// Decisions are pinned to a revision. When newer evidence arrives under the
/// same issue identity, the decision stops applying and is surfaced rather than
/// silently carried over to content the user never reviewed.
public struct ManualGroupAssignment: Codable, Sendable, Hashable, Identifiable {
    /// Stable identity for list presentation.
    public var id: String { "\(key.issueID.uuidString)|\(revisionID)" }
    /// Issue the decision applies to.
    public let key: IssueKey
    /// Exact revision the user reviewed when deciding.
    public let revisionID: String
    /// User-chosen group name.
    public let groupID: String
    /// When the decision was made.
    public let decidedAt: Date

    /// Creates an assignment.
    public init(key: IssueKey, revisionID: String, groupID: String, decidedAt: Date = Date()) {
        self.key = key
        self.revisionID = revisionID
        self.groupID = groupID
        self.decidedAt = decidedAt
    }
}

/// An image the user chose to leave out of a request's attachments.
///
/// Excluding an image changes what is attached. It never modifies or removes
/// captured evidence, which stays in the evidence bundle.
public struct ExcludedImage: Codable, Sendable, Hashable, Identifiable {
    /// Stable identity for list presentation.
    public var id: String { "\(key.issueID.uuidString)|\(revisionID)|\(kind.rawValue)" }
    /// Issue the exclusion applies to.
    public let key: IssueKey
    /// Exact revision the exclusion was decided against.
    public let revisionID: String
    /// Image kind excluded from attachments.
    public let kind: IssueExportImageKind

    /// Creates an exclusion.
    public init(key: IssueKey, revisionID: String, kind: IssueExportImageKind) {
        self.key = key
        self.revisionID = revisionID
        self.kind = kind
    }
}

/// Persistent manual adjustments layered over the deterministic rules.
public struct BatchOverrides: Codable, Sendable, Hashable {
    /// Split and merge decisions.
    public var assignments: [ManualGroupAssignment]
    /// Per-revision attachment exclusions.
    public var exclusions: [ExcludedImage]
    /// Extra request instructions per group, authored by the user.
    ///
    /// Instructions are companion-authored text kept separate from report
    /// content; they never rewrite captured evidence.
    public var instructions: [String: String]

    /// Creates an override set.
    public init(assignments: [ManualGroupAssignment] = [], exclusions: [ExcludedImage] = [],
                instructions: [String: String] = [:]) {
        self.assignments = assignments
        self.exclusions = exclusions
        self.instructions = instructions
    }

    /// Assignments matched against the revisions currently under consideration.
    public struct Resolution: Sendable {
        /// Group name to the inputs pinned to it.
        public let groups: [String: [BatchEngine.Input]]
        /// Decisions that no longer apply, with an explanation.
        public let stale: [BatchReason]
        private let assigned: [String: String]

        init(groups: [String: [BatchEngine.Input]], stale: [BatchReason], assigned: [String: String]) {
            self.groups = groups
            self.stale = stale
            self.assigned = assigned
        }

        /// Group the input was pinned to, if any.
        public func manualGroupID(for input: BatchEngine.Input) -> String? {
            assigned["\(input.key.issueID.uuidString)|\(input.revisionID)"]
        }
    }

    /// Matches assignments to `inputs`, reporting decisions that no longer apply.
    ///
    /// A manual group that would span more than one project is rejected: the
    /// companion never mixes projects, even under an explicit decision made
    /// before the second project's evidence arrived.
    public func resolve(against inputs: [BatchEngine.Input]) -> Resolution {
        let byIssue = Dictionary(grouping: inputs, by: { $0.key })
        var groups: [String: [BatchEngine.Input]] = [:]
        var assigned: [String: String] = [:]
        var stale: [BatchReason] = []

        for assignment in assignments.sorted(by: { $0.id < $1.id }) {
            let candidates = byIssue[assignment.key] ?? []
            guard let match = candidates.first(where: { $0.revisionID == assignment.revisionID }) else {
                let detail = candidates.isEmpty
                    ? "Decision for issue \(assignment.key.issueID) is kept but that issue is not present."
                    : "Decision for issue \(assignment.key.issueID) was made against revision \(assignment.revisionID.prefix(12)), which is no longer the current revision. Review the newer evidence and decide again."
                stale.append(.init(code: .staleManualAssignment, detail: detail))
                continue
            }
            groups[assignment.groupID, default: []].append(match)
            assigned["\(match.key.issueID.uuidString)|\(match.revisionID)"] = assignment.groupID
        }

        for (groupID, members) in groups {
            let projects = Set(members.map(\.key.projectID))
            guard projects.count > 1 else { continue }
            groups[groupID] = nil
            for member in members { assigned["\(member.key.issueID.uuidString)|\(member.revisionID)"] = nil }
            stale.append(.init(code: .staleManualAssignment,
                detail: "Group \"\(groupID)\" would span projects \(projects.sorted().joined(separator: ", ")). Projects are never mixed, so the decision was not applied."))
        }
        return Resolution(groups: groups, stale: stale.sorted { $0.id < $1.id }, assigned: assigned)
    }

    /// Whether the given image kind is excluded for a revision.
    public func excludes(key: IssueKey, revisionID: String, kind: IssueExportImageKind) -> Bool {
        exclusions.contains(ExcludedImage(key: key, revisionID: revisionID, kind: kind))
    }

    /// Records a manual assignment, replacing any previous decision for the
    /// same issue revision.
    public mutating func assign(key: IssueKey, revisionID: String, groupID: String, at date: Date = Date()) {
        assignments.removeAll { $0.key == key && $0.revisionID == revisionID }
        guard !groupID.isEmpty else { return }
        assignments.append(.init(key: key, revisionID: revisionID, groupID: groupID, decidedAt: date))
    }

    /// Removes a manual assignment, returning the issue revision to the rules.
    public mutating func unassign(key: IssueKey, revisionID: String) {
        assignments.removeAll { $0.key == key && $0.revisionID == revisionID }
    }

    /// Toggles whether an image kind is attached for a revision.
    public mutating func setExcluded(_ excluded: Bool, key: IssueKey, revisionID: String,
                                     kind: IssueExportImageKind) {
        let entry = ExcludedImage(key: key, revisionID: revisionID, kind: kind)
        if excluded { if !exclusions.contains(entry) { exclusions.append(entry) } }
        else { exclusions.removeAll { $0 == entry } }
    }

    /// Removes every assignment and exclusion recorded for an issue.
    public mutating func forget(key: IssueKey) {
        assignments.removeAll { $0.key == key }
        exclusions.removeAll { $0.key == key }
    }
}
