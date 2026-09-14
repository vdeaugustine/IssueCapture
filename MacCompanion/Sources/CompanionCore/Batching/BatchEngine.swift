import Foundation
import IssueCaptureSchema

/// Pure, deterministic grouping of issue revisions into candidate requests.
///
/// The engine proposes candidate requests. It does not claim the grouped issues
/// share a root cause, and it never merges by text similarity.
public enum BatchEngine {
    /// Version stored with every proposal so stale explanations stay traceable.
    public static let ruleVersion = "batch-rules-1"

    /// Input for one issue revision.
    public struct Input: Sendable {
        /// Issue identity.
        public let key: IssueKey
        /// Exact revision considered.
        public let revisionID: String
        /// Report as received.
        public let report: IssueReport

        /// Creates an engine input.
        public init(key: IssueKey, revisionID: String, report: IssueReport) {
            self.key = key
            self.revisionID = revisionID
            self.report = report
        }

        var member: BatchMember {
            BatchMember(key: key, revisionID: revisionID,
                        capturedAt: report.capturedAt, displayID: report.displayID)
        }

        var environmentKey: EnvironmentPartitionKey { .init(environment: report.environment) }

        /// Leaf registered screens. A screen that is the parent of another
        /// registered screen is not itself a capture candidate.
        var screenCandidates: [IssueScreenContext] {
            report.screens.filter { screen in !report.screens.contains { $0.parentID == screen.id } }
        }

        /// Exact screen grouping key, or nil when the screen is not usable.
        ///
        /// Mounted screen UUIDs identify instances rather than stable screens
        /// and are deliberately never used.
        var screenKey: String? {
            guard report.contextStatus == IssueContextStatus.accepted else { return nil }
            let candidates = screenCandidates
            guard candidates.count == 1, let screen = candidates.first else { return nil }
            if let stableID = screen.stableID, !stableID.isEmpty { return "stable:" + stableID }
            return "type:\(screen.typeName)|file:\(screen.file)"
        }

        var tags: [String] { report.tags ?? [] }

        func batchTags(prefix: String) -> [String] {
            tags.filter { $0.hasPrefix(prefix) }.sorted()
        }

        func ordinaryTags(prefix: String) -> [String] {
            tags.filter { !$0.hasPrefix(prefix) }.sorted()
        }

        var eventIDs: Set<UUID> { Set(report.events.map(\.id)) }
    }

    /// Produces candidate requests for `inputs`.
    ///
    /// - Parameters:
    ///   - overrides: explicit user decisions, applied before rules.
    ///   - preferences: cap and tag prefix.
    /// - Returns: proposals in deterministic order, plus reasons for manual
    ///   decisions that no longer apply to the current revisions.
    public static func propose(inputs: [Input],
                               overrides: BatchOverrides = .init(),
                               preferences: BatchingPreferences = .standard) -> BatchProposal {
        let sorted = inputs.sorted(by: order)
        let resolution = overrides.resolve(against: sorted)
        var batches: [CandidateBatch] = []
        batches += manualBatches(resolution: resolution, all: sorted, preferences: preferences)
        let remaining = sorted.filter { resolution.manualGroupID(for: $0) == nil }
        for partition in partitions(of: remaining) {
            batches += ruleBatches(partition: partition, all: sorted, preferences: preferences)
        }
        return BatchProposal(ruleVersion: ruleVersion,
                             batches: batches.sorted(by: batchOrder),
                             staleAssignments: resolution.stale)
    }

    // MARK: - Ordering

    /// Issues sort by capture timestamp, then full UUID. Short IDs are never
    /// used for ordering.
    private static func order(_ lhs: Input, _ rhs: Input) -> Bool {
        if lhs.report.capturedAt != rhs.report.capturedAt { return lhs.report.capturedAt < rhs.report.capturedAt }
        return lhs.key.issueID.uuidString < rhs.key.issueID.uuidString
    }

    private static func batchOrder(_ lhs: CandidateBatch, _ rhs: CandidateBatch) -> Bool {
        if lhs.origin != rhs.origin { return lhs.origin == .manual }
        if lhs.projectID != rhs.projectID { return lhs.projectID < rhs.projectID }
        if lhs.environmentKey != rhs.environmentKey { return lhs.environmentKey < rhs.environmentKey }
        let left = lhs.members.first
        let right = rhs.members.first
        if let left, let right, left.capturedAt != right.capturedAt { return left.capturedAt < right.capturedAt }
        if let left, let right, left.key.issueID != right.key.issueID {
            return left.key.issueID.uuidString < right.key.issueID.uuidString
        }
        return lhs.id < rhs.id
    }

    // MARK: - Partitioning

    private struct Partition {
        let projectID: String
        let environmentKey: EnvironmentPartitionKey
        let inputs: [Input]
    }

    /// Partitions by project, then by exact recorded app version and build.
    private static func partitions(of inputs: [Input]) -> [Partition] {
        var buckets: [String: [Input]] = [:]
        var keys: [String: (String, EnvironmentPartitionKey)] = [:]
        for input in inputs {
            let environment = input.environmentKey
            let token = "\(input.key.projectID)\u{1F}\(environment.token)"
            buckets[token, default: []].append(input)
            keys[token] = (input.key.projectID, environment)
        }
        return buckets.keys.sorted().compactMap { token in
            guard let (project, environment) = keys[token] else { return nil }
            return Partition(projectID: project, environmentKey: environment,
                             inputs: buckets[token] ?? [])
        }
    }

    // MARK: - Rules

    private static func ruleBatches(partition: Partition, all: [Input],
                                    preferences: BatchingPreferences) -> [CandidateBatch] {
        var groups: [(key: String, reason: BatchReason, members: [Input])] = []
        var individual: [(input: Input, reason: BatchReason)] = []
        var byBatchTag: [String: [Input]] = [:]
        var byScreen: [String: [Input]] = [:]

        for input in partition.inputs {
            let batchTags = input.batchTags(prefix: preferences.batchTagPrefix)
            if batchTags.count > 1 {
                individual.append((input, .init(code: .batchTagConflict,
                    detail: "Carries \(batchTags.count) batch tags (\(batchTags.joined(separator: ", "))). "
                          + "Conflicting explicit assignments are not resolved automatically.")))
                continue
            }
            if let tag = batchTags.first {
                byBatchTag[tag, default: []].append(input)
                continue
            }
            if let screenKey = input.screenKey {
                byScreen[screenKey, default: []].append(input)
                continue
            }
            individual.append((input, contextReason(for: input)))
        }

        for tag in byBatchTag.keys.sorted() {
            let members = byBatchTag[tag] ?? []
            groups.append((key: "tag:" + tag,
                           reason: .init(code: .explicitBatchTag,
                                         detail: "Explicit user-assigned tag \"\(tag)\" groups \(members.count) issue(s) in this build partition."),
                           members: members))
        }
        for screenKey in byScreen.keys.sorted() {
            let members = byScreen[screenKey] ?? []
            if members.count == 1, let only = members.first {
                individual.append((only, .init(code: .singleIssue,
                    detail: "Only issue in this build partition with screen key \(describe(screenKey)).")))
                continue
            }
            groups.append((key: "screen:" + screenKey,
                           reason: .init(code: .sharedScreen,
                                         detail: "\(members.count) issues recorded exactly one accepted screen candidate with the same key \(describe(screenKey))."),
                           members: members))
        }
        for entry in individual {
            groups.append((key: "single:" + entry.input.key.issueID.uuidString,
                           reason: entry.reason, members: [entry.input]))
        }

        return groups.flatMap { group -> [CandidateBatch] in
            split(group: group, partition: partition, all: all, preferences: preferences)
        }
    }

    private static func contextReason(for input: Input) -> BatchReason {
        switch input.report.contextStatus {
        case IssueContextStatus.ambiguous:
            return .init(code: .ambiguousScreen,
                         detail: "Recorded context status is ambiguous (\(input.screenCandidates.count) active candidates). Ambiguous screens stay individual.")
        case IssueContextStatus.missing:
            return .init(code: .unregisteredScreen,
                         detail: "No screen registration covered this capture. Unregistered screens stay individual.")
        case IssueContextStatus.accepted:
            return .init(code: .ambiguousScreen,
                         detail: "Context status is accepted but \(input.screenCandidates.count) leaf screen candidates were recorded, so no single screen key exists.")
        default:
            return .init(code: .unrecognizedContextStatus,
                         detail: "Recorded context status \"\(input.report.contextStatus)\" is not a documented accepted value, so the issue stays individual.")
        }
    }

    private static func describe(_ screenKey: String) -> String {
        screenKey.hasPrefix("stable:")
            ? "stableID \"\(screenKey.dropFirst("stable:".count))\""
            : "\"\(screenKey.dropFirst("type:".count))\""
    }

    /// Splits an oversized group in capture order, preserving determinism.
    private static func split(group: (key: String, reason: BatchReason, members: [Input]),
                              partition: Partition, all: [Input],
                              preferences: BatchingPreferences) -> [CandidateBatch] {
        let ordered = group.members.sorted(by: order)
        let cap = max(1, preferences.maximumIssuesPerRequest)
        let chunks = stride(from: 0, to: ordered.count, by: cap).map {
            Array(ordered[$0..<min($0 + cap, ordered.count)])
        }
        return chunks.enumerated().map { index, chunk in
            var reasons = [group.reason]
            if chunks.count > 1 {
                reasons.append(.init(code: .capSplit,
                    detail: "Group of \(ordered.count) exceeded the cap of \(cap); split by capture order into part \(index + 1) of \(chunks.count)."))
            }
            return CandidateBatch(
                id: identifier(ruleVersion: ruleVersion, projectID: partition.projectID,
                               environment: partition.environmentKey, groupKey: group.key, part: index),
                ruleVersion: ruleVersion, projectID: partition.projectID,
                environmentKey: partition.environmentKey, members: chunk.map(\.member),
                reasons: reasons,
                relatedNotes: relatedNotes(for: chunk, within: partition.inputs, preferences: preferences),
                origin: .rule,
                title: title(groupKey: group.key, chunk: chunk, part: index, total: chunks.count,
                             preferences: preferences))
        }
    }

    // MARK: - Manual decisions

    private static func manualBatches(resolution: BatchOverrides.Resolution, all: [Input],
                                      preferences: BatchingPreferences) -> [CandidateBatch] {
        resolution.groups.keys.sorted().compactMap { groupID in
            let members = (resolution.groups[groupID] ?? []).sorted(by: order)
            guard let first = members.first else { return nil }
            var reasons: [BatchReason] = [
                .init(code: .manualAssignment,
                      detail: "Explicit user decision pinned \(members.count) issue revision(s) to group \"\(groupID)\".")
            ]
            if members.count > preferences.maximumIssuesPerRequest {
                reasons.append(.init(code: .capSplit,
                    detail: "This manual group holds \(members.count) issues, above the cap of \(preferences.maximumIssuesPerRequest). Explicit decisions are not split automatically."))
            }
            return CandidateBatch(id: "manual:" + groupID, ruleVersion: ruleVersion,
                                  projectID: first.key.projectID,
                                  environmentKey: first.environmentKey,
                                  members: members.map(\.member), reasons: reasons,
                                  relatedNotes: relatedNotes(for: members, within: all, preferences: preferences),
                                  origin: .manual, title: groupID)
        }
    }

    // MARK: - Related items

    /// Ordinary tags and exact shared event identifiers explain relationships
    /// without merging, and never chain through a third issue.
    private static func relatedNotes(for members: [Input], within scope: [Input],
                                     preferences: BatchingPreferences) -> [RelatedNote] {
        let memberIDs = Set(members.map(\.key.issueID))
        let tags = Set(members.flatMap { $0.ordinaryTags(prefix: preferences.batchTagPrefix) })
        let events = members.reduce(into: Set<UUID>()) { $0.formUnion($1.eventIDs) }
        var notes: Set<RelatedNote> = []
        for other in scope where !memberIDs.contains(other.key.issueID) {
            for tag in tags.intersection(other.ordinaryTags(prefix: preferences.batchTagPrefix)).sorted() {
                notes.insert(.init(kind: .sharedTag, issueID: other.key.issueID, value: tag))
            }
            for event in events.intersection(other.eventIDs).sorted(by: { $0.uuidString < $1.uuidString }) {
                notes.insert(.init(kind: .sharedEventID, issueID: other.key.issueID, value: event.uuidString))
            }
        }
        return notes.sorted { $0.id < $1.id }
    }

    // MARK: - Identity and labels

    private static func identifier(ruleVersion: String, projectID: String,
                                   environment: EnvironmentPartitionKey,
                                   groupKey: String, part: Int) -> String {
        let descriptor = [ruleVersion, projectID, environment.token, groupKey, String(part)]
            .joined(separator: "\u{1F}")
        return "rule:" + Digest.sha256(Data(descriptor.utf8)).prefix(16)
    }

    private static func title(groupKey: String, chunk: [Input], part: Int, total: Int,
                              preferences: BatchingPreferences) -> String {
        let suffix = total > 1 ? " · part \(part + 1)/\(total)" : ""
        if groupKey.hasPrefix("tag:") {
            let tag = String(groupKey.dropFirst("tag:".count))
            let name = tag.hasPrefix(preferences.batchTagPrefix)
                ? String(tag.dropFirst(preferences.batchTagPrefix.count)) : tag
            return (name.isEmpty ? tag : name) + suffix
        }
        if groupKey.hasPrefix("screen:") {
            let name = chunk.first?.screenCandidates.first?.name ?? "Shared screen"
            return name + suffix
        }
        return chunk.first?.report.displayID ?? "Issue"
    }
}

/// Result of one deterministic batching pass.
public struct BatchProposal: Sendable {
    /// Rule engine version that produced the proposals.
    public let ruleVersion: String
    /// Proposals in deterministic order.
    public let batches: [CandidateBatch]
    /// Manual decisions that referenced revisions no longer current.
    public let staleAssignments: [BatchReason]

    /// Creates a proposal result.
    public init(ruleVersion: String, batches: [CandidateBatch], staleAssignments: [BatchReason]) {
        self.ruleVersion = ruleVersion
        self.batches = batches
        self.staleAssignments = staleAssignments
    }
}
