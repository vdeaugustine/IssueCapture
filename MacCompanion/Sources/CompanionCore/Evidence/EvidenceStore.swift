import Foundation
import IssueCaptureSchema

/// What one committed import changed.
public struct ImportResult: Sendable {
    /// Provenance recorded for this import.
    public let provenance: ImportProvenance
    /// Revisions created because content was new for their issue identity.
    public let newRevisions: [IssueRevision]
    /// Revisions whose content already existed; the import is still retained.
    public let unchangedRevisions: [IssueRevision]
    /// True when an archive with the same SHA-256 had already been imported and
    /// nothing was committed.
    public let wasExactRepeat: Bool

    /// Every issue-level warning carried by this import.
    public var warnings: [ImportWarning] {
        (newRevisions + unchangedRevisions).flatMap(\.warnings)
    }
}

/// Immutable, versioned storage for received evidence and import provenance.
///
/// Received JSON, Markdown and images are preserved byte-for-byte. Export
/// images may already be JPEG derivatives produced by the exporter; the store
/// never claims they reproduce the device's stored original.
public final class EvidenceStore {
    /// Root of the companion's storage.
    public let root: URL
    private let fileManager = FileManager.default
    private var index: StoreIndex

    private struct StoreIndex: Codable {
        var imports: [ImportProvenance] = []
        var revisions: [IssueRevision] = []
        /// Archive SHA-256 to the import that first carried it.
        var archives: [String: UUID] = [:]
    }

    /// Opens or creates a store rooted at `root`.
    public init(root: URL) throws {
        self.root = root
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("index.json")
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(StoreIndex.self, from: data) {
            index = decoded
        } else {
            index = StoreIndex()
        }
    }

    // MARK: - Reading

    /// Every import ever received, newest first.
    public var imports: [ImportProvenance] { index.imports.sorted { $0.receivedAt > $1.receivedAt } }

    /// Every retained revision.
    public var revisions: [IssueRevision] { index.revisions }

    /// All revisions for one issue, oldest first.
    public func revisions(for key: IssueKey) -> [IssueRevision] {
        index.revisions.filter { $0.issueKey == key }.sorted { $0.revisionIndex < $1.revisionIndex }
    }

    /// The newest revision of each issue, ordered by capture time then UUID.
    public func currentRevisions() -> [IssueRevision] {
        Dictionary(grouping: index.revisions, by: \.issueKey)
            .compactMap { $0.value.max { $0.revisionIndex < $1.revisionIndex } }
            .sorted {
                $0.report.capturedAt == $1.report.capturedAt
                    ? $0.issueKey.issueID.uuidString < $1.issueKey.issueID.uuidString
                    : $0.report.capturedAt < $1.report.capturedAt
            }
    }

    /// Newest revision for one issue.
    public func currentRevision(for key: IssueKey) -> IssueRevision? {
        revisions(for: key).last
    }

    /// Revision with the given identifier.
    public func revision(id: String) -> IssueRevision? { index.revisions.first { $0.id == id } }

    /// Absolute location of a preserved file inside a revision folder.
    public func url(in revision: IssueRevision, filename: String) -> URL {
        root.appendingPathComponent(revision.path).appendingPathComponent(filename)
    }

    /// Absolute location of a revision's image of the given kind, when present.
    public func url(in revision: IssueRevision, kind: IssueExportImageKind) -> URL? {
        guard let fact = revision.fact(for: kind) else { return nil }
        return url(in: revision, filename: fact.filename)
    }

    /// Import that first carried an archive with this checksum, if any.
    public func existingImport(archiveSHA256: String) -> ImportProvenance? {
        guard let id = index.archives[archiveSHA256] else { return nil }
        return index.imports.first { $0.id == id }
    }

    // MARK: - Committing

    /// Commits a validated export.
    ///
    /// Exact repeats of an archive are idempotent: nothing is written and the
    /// existing provenance is returned. Content that matches an existing
    /// revision creates no new revision, but the import itself is still
    /// retained so receipt history stays complete.
    public func commit(export: ValidatedExport, sourceDescription: String,
                       sourceKind: ImportProvenance.SourceKind, archiveSHA256: String?,
                       receivedAt: Date = Date()) throws -> ImportResult {
        if let archiveSHA256, let existing = existingImport(archiveSHA256: archiveSHA256) {
            return ImportResult(provenance: existing, newRevisions: [], unchangedRevisions: [],
                                wasExactRepeat: true)
        }
        let importID = UUID()
        let payloadRelative = "imports/\(importID.uuidString)/payload"
        let payloadURL = root.appendingPathComponent(payloadRelative)
        try copyTree(from: export.root, to: payloadURL)

        var created: [IssueRevision] = []
        var unchanged: [IssueRevision] = []
        for issue in export.issues {
            let hashes = issue.files.mapValues(\.sha256)
            let revisionID = try ContentFingerprint.revisionID(report: issue.report, imageHashes: hashes)
            if let existing = index.revisions.firstIndex(where: {
                $0.issueKey == issue.key && $0.id == revisionID
            }) {
                if !index.revisions[existing].importIDs.contains(importID) {
                    index.revisions[existing].importIDs.append(importID)
                }
                unchanged.append(index.revisions[existing])
                continue
            }
            created.append(try store(issue: issue, revisionID: revisionID, importID: importID))
        }

        let provenance = ImportProvenance(
            id: importID, receivedAt: receivedAt, sourceDescription: sourceDescription,
            sourceKind: sourceKind, archiveSHA256: archiveSHA256,
            manifestSchemaVersion: export.manifest.schemaVersion,
            manifestExportedAt: export.manifest.exportedAt, payloadPath: payloadRelative,
            declaredIssues: export.issues.map(\.key))
        index.imports.append(provenance)
        if let archiveSHA256 { index.archives[archiveSHA256] = importID }
        try save()
        return ImportResult(provenance: provenance, newRevisions: created,
                            unchangedRevisions: unchanged, wasExactRepeat: false)
    }

    private func store(issue: ValidatedIssue, revisionID: String, importID: UUID) throws -> IssueRevision {
        let nextIndex = (revisions(for: issue.key).last?.revisionIndex ?? 0) + 1
        let relative = "issues/\(Self.slug(issue.key.projectID))/\(issue.key.issueID.uuidString)/\(revisionID)"
        let folder = root.appendingPathComponent(relative)
        if fileManager.fileExists(atPath: folder.path) { try fileManager.removeItem(at: folder) }
        try copyTree(from: issue.folder, to: folder)
        let revision = IssueRevision(id: revisionID, issueKey: issue.key, revisionIndex: nextIndex,
                                     firstImportID: importID, importIDs: [importID],
                                     report: issue.report, declaredImages: issue.declaredImages,
                                     files: issue.files, warnings: issue.warnings, path: relative)
        index.revisions.append(revision)
        return revision
    }

    /// Copies a directory tree verbatim. Regular files only; nothing that is
    /// not a regular file or directory is reproduced.
    private func copyTree(from source: URL, to destination: URL) throws {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        guard let enumerator = fileManager.enumerator(
            at: source, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]) else {
            throw ImportFailure(code: .unreadableSource,
                                detail: "Could not enumerate \(source.lastPathComponent).", isRetryable: true)
        }
        let base = source.standardizedFileURL.path
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            let relative = String(url.standardizedFileURL.path.dropFirst(base.count + 1))
            let target = destination.appendingPathComponent(relative)
            if values.isDirectory == true {
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            } else if values.isRegularFile == true {
                try fileManager.createDirectory(at: target.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
                try fileManager.copyItem(at: url, to: target)
            }
        }
    }

    private func save() throws {
        do {
            let data = try IssueExportSchema.encoder().encode(index)
            try data.write(to: root.appendingPathComponent("index.json"), options: .atomic)
        } catch {
            throw ImportFailure(code: .storageFailure,
                                detail: "Could not update the evidence index: \(error.localizedDescription)",
                                isRetryable: true)
        }
    }

    /// Filesystem-safe folder name for a project identifier of any shape.
    static func slug(_ projectID: String) -> String {
        let allowed = projectID.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" ? Character($0) : "-"
        }
        let prefix = String(String(allowed).prefix(40))
        return prefix + "-" + Digest.sha256(Data(projectID.utf8)).prefix(12)
    }
}
