import Foundation
import IssueCaptureSchema

/// One issue read out of a staged export, with its evidence facts.
public struct ValidatedIssue: Sendable {
    /// Issue identity taken from the report, cross-checked against the manifest.
    public let key: IssueKey
    /// Decoded report.
    public let report: IssueReport
    /// Byte-for-byte `issue.json` as received.
    public let reportBytes: Data
    /// `images.json` exactly as received; empty when absent.
    public let declaredImages: [String: String]
    /// Facts for the image files that were actually present.
    public let files: [String: EvidenceFileFact]
    /// Staged folder holding this issue's received files.
    public let folder: URL
    /// Issue-level problems that do not reject the import.
    public let warnings: [ImportWarning]
}

/// A staged export that passed structural validation.
public struct ValidatedExport: Sendable {
    /// Manifest as declared by the writer.
    public let manifest: IssueExportManifest
    /// Issues in manifest order.
    public let issues: [ValidatedIssue]
    /// Root of the staged payload.
    public let root: URL
}

/// Validates an expanded export folder before anything is committed.
///
/// Identity comes from `manifest.json` and the referenced issue JSON, paired by
/// full UUID and declared paths. Filenames, short IDs and Markdown are never
/// used for pairing.
public enum ExportValidator {
    /// Reads and validates the export rooted at `root`.
    ///
    /// - Throws: ``ImportFailure`` when the export must be rejected outright.
    public static func validate(root: URL) throws -> ValidatedExport {
        let base = try exportRoot(root)
        let manifestURL = base.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ImportFailure(code: .notAnExport,
                                detail: "No manifest.json was found. Select an IssueCapture export folder or ZIP.")
        }
        let manifest = try decodeManifest(at: manifestURL)
        guard IssueExportSchema.supportedManifestVersions.contains(manifest.schemaVersion) else {
            let supported = IssueExportSchema.supportedManifestVersions.sorted().map(String.init).joined(separator: ", ")
            throw ImportFailure(code: .unsupportedManifestVersion,
                                detail: "Manifest schema version \(manifest.schemaVersion) is not supported by this companion build. "
                                      + "Supported versions: \(supported).")
        }
        var seen = Set<UUID>()
        var issues: [ValidatedIssue] = []
        for item in manifest.issues {
            guard seen.insert(item.id).inserted else {
                throw ImportFailure(code: .duplicateIssueIdentity,
                                    detail: "manifest.json lists issue \(item.id) more than once.")
            }
            issues.append(try validateIssue(item: item, base: base))
        }
        return ValidatedExport(manifest: manifest, issues: issues, root: base)
    }

    /// Accepts either the export root itself or a folder containing exactly one
    /// export folder, which is what expanding a ZIP in Finder produces.
    private static func exportRoot(_ root: URL) throws -> URL {
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path) { return root }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        let directories = contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        let candidates = directories.filter {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("manifest.json").path)
        }
        guard candidates.count == 1 else { return root }
        return candidates[0]
    }

    private static func decodeManifest(at url: URL) throws -> IssueExportManifest {
        do {
            return try JSONDecoder().decode(IssueExportManifest.self, from: Data(contentsOf: url))
        } catch {
            throw ImportFailure(code: .malformedManifest,
                                detail: "manifest.json could not be decoded: \(error.localizedDescription)")
        }
    }

    private static func validateIssue(item: IssueExportManifest.Item, base: URL) throws -> ValidatedIssue {
        let reportURL = try resolve(relativePath: item.report, in: base, describing: "manifest entry for \(item.id)")
        guard FileManager.default.fileExists(atPath: reportURL.path) else {
            throw ImportFailure(code: .malformedManifest,
                                detail: "manifest.json points at \"\(item.report)\", which is missing from the export.")
        }
        let reportBytes: Data
        let report: IssueReport
        do {
            reportBytes = try Data(contentsOf: reportURL)
            report = try JSONDecoder().decode(IssueReport.self, from: reportBytes)
        } catch let failure as ImportFailure {
            throw failure
        } catch {
            throw ImportFailure(code: .malformedReport,
                                detail: "\(item.report) could not be decoded: \(error.localizedDescription)")
        }
        guard IssueExportSchema.supportedReportVersions.contains(report.schemaVersion) else {
            throw ImportFailure(code: .unsupportedReportVersion,
                                detail: "Issue \(item.id) declares report schema version \(report.schemaVersion), which this companion build does not read.")
        }
        guard report.id == item.id else {
            throw ImportFailure(code: .identityMismatch,
                                detail: "manifest.json declares issue \(item.id) but \(item.report) contains \(report.id). "
                                      + "Identity must match exactly; the export is not trustworthy.")
        }
        let folder = reportURL.deletingLastPathComponent()
        let (declared, mapWarnings) = readImageMap(in: folder)
        var warnings = mapWarnings
        var files: [String: EvidenceFileFact] = [:]
        for kind in declared.keys.sorted() {
            guard let name = declared[kind] else { continue }
            guard IssueExportImageKind(rawValue: kind) != nil else {
                warnings.append(.init(code: .unknownImageKind,
                                      detail: "images.json declares unknown kind \"\(kind)\" (\(name)); it is preserved but not previewed."))
                continue
            }
            let fileURL = try resolve(relativePath: name, in: folder, describing: "images.json entry \"\(kind)\"")
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                warnings.append(.init(code: .missingDeclaredImage,
                                      detail: "images.json declares \(kind) as \"\(name)\" but that file is missing. Evidence for this issue is incomplete."))
                continue
            }
            let bytes = try readBytes(at: fileURL, label: name)
            files[kind] = EvidenceFileFact(filename: name, sha256: Digest.sha256(bytes), byteCount: bytes.count)
        }
        warnings += declarationWarnings(report: report, files: files)
        warnings += environmentWarnings(report: report)
        return ValidatedIssue(key: IssueKey(projectID: report.projectID, issueID: report.id),
                              report: report, reportBytes: reportBytes, declaredImages: declared,
                              files: files, folder: folder, warnings: warnings)
    }

    private static func readImageMap(in folder: URL) -> ([String: String], [ImportWarning]) {
        let url = folder.appendingPathComponent("images.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ([:], [.init(code: .missingImageMap,
                                detail: "images.json is absent, so declared image filenames cannot be resolved.")])
        }
        guard let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else {
            return ([:], [.init(code: .missingImageMap,
                                detail: "images.json could not be decoded, so declared image filenames cannot be resolved.")])
        }
        return (map, [])
    }

    /// Flags assets the report claims exist but the export did not name.
    private static func declarationWarnings(report: IssueReport, files: [String: EvidenceFileFact]) -> [ImportWarning] {
        var warnings: [ImportWarning] = []
        if report.hasScreenshot && files[IssueExportImageKind.screenshot.rawValue] == nil {
            warnings.append(.init(code: .declaredAssetNotExported,
                                  detail: "The report records a captured screenshot, but no screenshot file was included."))
        }
        if report.hasAttachment && files[IssueExportImageKind.attachment.rawValue] == nil {
            warnings.append(.init(code: .declaredAssetNotExported,
                                  detail: "The report records a manually attached image, but no attachment file was included."))
        }
        if !report.annotations.isEmpty && files[IssueExportImageKind.annotation.rawValue] == nil {
            warnings.append(.init(code: .declaredAssetNotExported,
                                  detail: "The report contains \(report.annotations.count) annotation path(s), but no annotated image was included."))
        }
        return warnings
    }

    private static func environmentWarnings(report: IssueReport) -> [ImportWarning] {
        let missing = EnvironmentPartitionKey.partitionKeys.filter {
            EnvironmentPartitionKey.value(report.environment[$0]) == nil
        }
        guard !missing.isEmpty else { return [] }
        return [.init(code: .missingBuildMetadata,
                      detail: "Environment does not record \(missing.joined(separator: " and ")). "
                            + "This issue stays in its own build partition.")]
    }

    private static func readBytes(at url: URL, label: String) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw ImportFailure(code: .unreadableSource,
                                detail: "Could not read \(label): \(error.localizedDescription)", isRetryable: true)
        }
    }

    /// Resolves a declared relative path, rejecting anything that escapes `base`.
    static func resolve(relativePath: String, in base: URL, describing context: String) throws -> URL {
        guard !relativePath.isEmpty else {
            throw ImportFailure(code: .unsafeArchivePath, detail: "\(context) declares an empty path.")
        }
        guard !relativePath.hasPrefix("/"), !relativePath.contains("\0"), !relativePath.contains("\\") else {
            throw ImportFailure(code: .unsafeArchivePath,
                                detail: "\(context) declares unsafe path \"\(relativePath)\".")
        }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        for component in components where component.isEmpty || component == "." || component == ".." {
            throw ImportFailure(code: .unsafeArchivePath,
                                detail: "\(context) declares unsafe path \"\(relativePath)\".")
        }
        let root = base.standardizedFileURL
        let resolved = root.appendingPathComponent(relativePath).standardizedFileURL
        guard resolved.path.hasPrefix(root.path + "/") else {
            throw ImportFailure(code: .unsafeArchivePath,
                                detail: "\(context) declares \"\(relativePath)\", which resolves outside the export.")
        }
        return resolved
    }
}
