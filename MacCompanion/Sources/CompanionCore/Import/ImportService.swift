import Foundation
import IssueCaptureSchema

/// Stages, validates and commits exports. Source files are never moved or
/// modified; everything the companion keeps is a copy.
public final class ImportService {
    private let store: EvidenceStore
    private let limits: ZIPArchiveReader.Limits
    private let fileManager = FileManager.default

    /// Creates an import service writing into `store`.
    public init(store: EvidenceStore, limits: ZIPArchiveReader.Limits = .standard) {
        self.store = store
        self.limits = limits
    }

    /// Imports either an export ZIP or an already expanded export folder.
    ///
    /// - Throws: ``ImportFailure`` with an actionable message. Failures leave
    ///   the store untouched, so retrying the same source is safe.
    @discardableResult
    public func `import`(contentsOf url: URL, receivedAt: Date = Date()) throws -> ImportResult {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ImportFailure(code: .unreadableSource,
                                detail: "\(url.lastPathComponent) does not exist.", isRetryable: true)
        }
        return isDirectory.boolValue
            ? try importFolder(at: url, receivedAt: receivedAt)
            : try importArchive(at: url, receivedAt: receivedAt)
    }

    /// Imports a stored ZIP32 export archive.
    @discardableResult
    public func importArchive(at url: URL, receivedAt: Date = Date()) throws -> ImportResult {
        let checksum: String
        do { checksum = try Digest.sha256(fileAt: url) } catch {
            throw ImportFailure(code: .unreadableSource,
                                detail: "Could not read \(url.lastPathComponent): \(error.localizedDescription)",
                                isRetryable: true)
        }
        if let existing = store.existingImport(archiveSHA256: checksum) {
            return ImportResult(provenance: existing, newRevisions: [], unchangedRevisions: [],
                                wasExactRepeat: true)
        }
        let staging = try makeStagingFolder()
        defer { try? fileManager.removeItem(at: staging) }
        try ZIPArchiveReader.expand(archive: url, into: staging, limits: limits)
        let export = try ExportValidator.validate(root: staging)
        return try store.commit(export: export, sourceDescription: url.path, sourceKind: .archive,
                                archiveSHA256: checksum, receivedAt: receivedAt)
    }

    /// Imports an already expanded export folder.
    ///
    /// Folder imports have no archive checksum, so repeat imports of the same
    /// folder are recorded as separate receipts even when every issue is
    /// unchanged.
    @discardableResult
    public func importFolder(at url: URL, receivedAt: Date = Date()) throws -> ImportResult {
        let staging = try makeStagingFolder()
        defer { try? fileManager.removeItem(at: staging) }
        let staged = staging.appendingPathComponent(url.lastPathComponent.isEmpty ? "export" : url.lastPathComponent)
        do {
            try fileManager.copyItem(at: url, to: staged)
        } catch {
            throw ImportFailure(code: .unreadableSource,
                                detail: "Could not stage \(url.lastPathComponent): \(error.localizedDescription)",
                                isRetryable: true)
        }
        try rejectUnsafeEntries(in: staged)
        let export = try ExportValidator.validate(root: staged)
        return try store.commit(export: export, sourceDescription: url.path, sourceKind: .folder,
                                archiveSHA256: nil, receivedAt: receivedAt)
    }

    /// Rejects symbolic links and aliases inside a staged folder so an expanded
    /// export cannot reference evidence outside itself.
    private func rejectUnsafeEntries(in root: URL) throws {
        guard let enumerator = fileManager.enumerator(
            at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey],
            options: []) else { return }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey])
            if values.isSymbolicLink == true {
                throw ImportFailure(code: .unsafeArchivePath,
                                    detail: "\(url.lastPathComponent) is a symbolic link, which is not imported.")
            }
            if values.isRegularFile != true && values.isDirectory != true {
                throw ImportFailure(code: .unsafeArchivePath,
                                    detail: "\(url.lastPathComponent) is not a regular file or folder.")
            }
        }
    }

    private func makeStagingFolder() throws -> URL {
        let url = store.root.appendingPathComponent("staging").appendingPathComponent(UUID().uuidString)
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw ImportFailure(code: .storageFailure,
                                detail: "Could not create a staging folder: \(error.localizedDescription)",
                                isRetryable: true)
        }
        return url
    }
}
