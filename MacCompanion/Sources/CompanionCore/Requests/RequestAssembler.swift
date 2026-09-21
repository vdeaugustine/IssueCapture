import Foundation
import IssueCaptureSchema

/// Builds persistent, versioned request folders from a candidate batch.
///
/// Assembly is lossless: every received file for each selected revision is
/// copied into the request's evidence bundle unchanged. Nothing is truncated,
/// rewritten or recompressed.
public final class RequestAssembler {
    private let store: EvidenceStore
    private let fileManager = FileManager.default

    /// Creates an assembler reading evidence from `store`.
    public init(store: EvidenceStore) {
        self.store = store
    }

    /// Folder holding every prepared request.
    public var requestsRoot: URL { store.root.appendingPathComponent("requests") }

    /// Prepares a request folder for `batch`.
    ///
    /// - Throws: ``ImportFailure`` when evidence for a member is missing from
    ///   the store, which must not be silently skipped.
    public func prepare(batch: CandidateBatch, overrides: BatchOverrides,
                        options: AttachmentOptions = .standard,
                        preparedAt: Date = Date()) throws -> PreparedRequestHandle {
        let requestID = UUID()
        let folder = requestsRoot.appendingPathComponent(requestID.uuidString)
        do {
            try fileManager.createDirectory(at: folder.appendingPathComponent("evidence"),
                                            withIntermediateDirectories: true)
        } catch {
            throw ImportFailure(code: .storageFailure,
                                detail: "Could not create the request folder: \(error.localizedDescription)",
                                isRetryable: true)
        }

        var issues: [PreparedIssue] = []
        var attachmentsByHash: [String: PreparedAttachment] = [:]
        var attachmentOrder: [String] = []
        var reports: [UUID: IssueReport] = [:]

        for (offset, member) in batch.members.enumerated() {
            guard let revision = store.revision(id: member.revisionID) else {
                throw ImportFailure(code: .storageFailure,
                                    detail: "Evidence for issue \(member.key.issueID) revision \(member.revisionID) is not in the store.")
            }
            let evidencePath = "evidence/\(revision.issueKey.issueID.uuidString)"
            try copyEvidence(revision: revision, into: folder.appendingPathComponent(evidencePath))
            let decisions = AttachmentPolicy.decisions(for: revision, overrides: overrides, options: options)
            for decision in decisions where decision.isAttached {
                guard let fact = revision.fact(for: decision.kind) else { continue }
                let path = "\(evidencePath)/\(fact.filename)"
                let link = PreparedAttachment.Link(issueID: revision.issueKey.issueID,
                                                   kind: decision.kind, declaredFilename: fact.filename)
                if let existing = attachmentsByHash[fact.sha256] {
                    attachmentsByHash[fact.sha256] = PreparedAttachment(
                        path: existing.path, sha256: existing.sha256, byteCount: existing.byteCount,
                        links: existing.links + [link])
                } else {
                    attachmentsByHash[fact.sha256] = PreparedAttachment(
                        path: path, sha256: fact.sha256, byteCount: fact.byteCount, links: [link])
                    attachmentOrder.append(fact.sha256)
                }
            }
            reports[revision.issueKey.issueID] = revision.report
            issues.append(PreparedIssue(
                issueID: revision.issueKey.issueID, displayID: revision.report.displayID,
                revisionID: revision.id, revisionIndex: revision.revisionIndex, order: offset + 1,
                capturedAt: revision.report.capturedAt, evidencePath: evidencePath,
                evidenceFiles: revision.files, attachmentDecisions: decisions,
                warnings: revision.warnings))
        }

        let request = PreparedRequest(
            id: requestID, projectID: batch.projectID, environmentKey: batch.environmentKey,
            preparedAt: preparedAt, ruleVersion: batch.ruleVersion,
            templateVersion: PreparedRequest.templateVersion, batchID: batch.id, title: batch.title,
            groupingReasons: batch.reasons, relatedNotes: batch.relatedNotes, issues: issues,
            attachments: attachmentOrder.compactMap { attachmentsByHash[$0] },
            instructions: overrides.instructions[batch.id] ?? "")

        do {
            try IssueExportSchema.encoder().encode(request)
                .write(to: folder.appendingPathComponent("request.json"), options: .atomic)
            try RequestMarkdown.render(request: request, reports: reports)
                .write(to: folder.appendingPathComponent("request.md"), atomically: true, encoding: .utf8)
        } catch {
            try? fileManager.removeItem(at: folder)
            throw ImportFailure(code: .storageFailure,
                                detail: "Could not write the request: \(error.localizedDescription)",
                                isRetryable: true)
        }
        return PreparedRequestHandle(request: request, folder: folder)
    }

    /// Prompt text placed on the clipboard by Copy.
    ///
    /// The clipboard carries text only. Images must travel as file URLs.
    public func promptText(for handle: PreparedRequestHandle) -> String {
        (try? String(contentsOf: handle.markdownURL, encoding: .utf8)) ?? ""
    }

    /// Every request folder currently on disk, newest first.
    public func storedRequests() -> [PreparedRequestHandle] {
        let folders = (try? fileManager.contentsOfDirectory(
            at: requestsRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return folders.compactMap { folder -> PreparedRequestHandle? in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("request.json")),
                  let request = try? JSONDecoder().decode(PreparedRequest.self, from: data) else { return nil }
            return PreparedRequestHandle(request: request, folder: folder)
        }.sorted { $0.request.preparedAt > $1.request.preparedAt }
    }

    /// Deletes a prepared request folder from disk.
    public func delete(_ handle: PreparedRequestHandle) {
        try? fileManager.removeItem(at: handle.folder)
    }

    private func copyEvidence(revision: IssueRevision, into destination: URL) throws {
        let source = store.root.appendingPathComponent(revision.path)
        if fileManager.fileExists(atPath: destination.path) { return }
        do {
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            throw ImportFailure(code: .storageFailure,
                                detail: "Could not copy evidence for issue \(revision.issueKey.issueID): \(error.localizedDescription)",
                                isRetryable: true)
        }
    }
}
