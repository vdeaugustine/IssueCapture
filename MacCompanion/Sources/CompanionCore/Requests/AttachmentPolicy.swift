import Foundation
import IssueCaptureSchema

/// User-tunable attachment behavior.
///
/// The default includes available visual evidence so an agent can see the
/// screenshot without the user first guessing whether it matters.
public struct AttachmentOptions: Codable, Sendable, Hashable {
    /// Attach the unannotated capture alongside the annotated one.
    ///
    /// The unannotated capture is always kept in the evidence bundle; this
    /// controls only whether it is also offered as an external attachment.
    public var includeUnannotatedWithAnnotated: Bool
    /// Attach rendered issue cards.
    ///
    /// Off by default because a card repeats the report text that already
    /// appears in `request.md`.
    public var includeIssueCards: Bool
    /// Count above which the request panel advises splitting.
    ///
    /// This is a local readability advisory, not a verified destination limit.
    public var advisoryAttachmentCount: Int

    /// Creates attachment options.
    public init(includeUnannotatedWithAnnotated: Bool = false,
                includeIssueCards: Bool = false,
                advisoryAttachmentCount: Int = 10) {
        self.includeUnannotatedWithAnnotated = includeUnannotatedWithAnnotated
        self.includeIssueCards = includeIssueCards
        self.advisoryAttachmentCount = advisoryAttachmentCount
    }

    /// Documented defaults.
    public static let standard = AttachmentOptions()
}

/// Whether one image kind is attached, and why.
public struct AttachmentDecision: Codable, Sendable, Hashable, Identifiable {
    /// Stable identity for list presentation.
    public var id: String { kind.rawValue }
    /// Image kind the decision is about.
    public let kind: IssueExportImageKind
    /// Whether the file is offered as an external attachment.
    public let isAttached: Bool
    /// Exact explanation, shown next to the preview.
    public let reason: String

    /// Creates a decision.
    public init(kind: IssueExportImageKind, isAttached: Bool, reason: String) {
        self.kind = kind
        self.isAttached = isAttached
        self.reason = reason
    }
}

/// Decides which received images become external attachments.
///
/// Every received file stays in the evidence bundle regardless of these
/// decisions. Nothing here modifies or recompresses evidence.
public enum AttachmentPolicy {
    /// Decisions for every image kind present in `revision`.
    public static func decisions(for revision: IssueRevision, overrides: BatchOverrides,
                                 options: AttachmentOptions = .standard) -> [AttachmentDecision] {
        let present = revision.presentKinds
        let hasAnnotation = present.contains(.annotation)
        var attachedHashes: Set<String> = []
        var result: [AttachmentDecision] = []

        func decide(_ kind: IssueExportImageKind, defaultAttached: Bool, reason: String,
                    deduplicatedReason: String? = nil) {
            guard let fact = revision.fact(for: kind) else { return }
            if overrides.excludes(key: revision.issueKey, revisionID: revision.id, kind: kind) {
                result.append(.init(kind: kind, isAttached: false,
                                    reason: "Excluded by an explicit decision. The file remains in the evidence bundle."))
                return
            }
            if defaultAttached, let deduplicatedReason, attachedHashes.contains(fact.sha256) {
                result.append(.init(kind: kind, isAttached: false, reason: deduplicatedReason))
                return
            }
            if defaultAttached { attachedHashes.insert(fact.sha256) }
            result.append(.init(kind: kind, isAttached: defaultAttached, reason: reason))
        }

        decide(.annotation, defaultAttached: true,
               reason: "Annotated image is the default visual evidence.")
        let attachScreenshot = !hasAnnotation || options.includeUnannotatedWithAnnotated
        let screenshotReason: String
        if !hasAnnotation {
            screenshotReason = "Captured screenshot is the default visual evidence; no annotated version exists."
        } else if options.includeUnannotatedWithAnnotated {
            screenshotReason = "Unannotated capture attached alongside the annotated image."
        } else {
            screenshotReason = "Annotated version is attached instead. The unannotated capture stays in the evidence bundle and can be attached explicitly."
        }
        decide(.screenshot, defaultAttached: attachScreenshot, reason: screenshotReason,
               deduplicatedReason: "Identical bytes to an image already attached for this issue.")
        decide(.attachment, defaultAttached: true,
               reason: "Manually attached image is separate evidence.",
               deduplicatedReason: "Identical bytes to an image already attached for this issue.")
        decide(.card, defaultAttached: options.includeIssueCards,
               reason: options.includeIssueCards
                   ? "Issue card attached by preference."
                   : "Issue cards repeat the report text already present in request.md.")
        return result.sorted { order($0.kind) < order($1.kind) }
    }

    private static func order(_ kind: IssueExportImageKind) -> Int {
        switch kind {
        case .annotation: return 0
        case .screenshot: return 1
        case .attachment: return 2
        case .card: return 3
        }
    }
}
