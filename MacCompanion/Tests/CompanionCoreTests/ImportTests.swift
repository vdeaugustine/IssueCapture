import XCTest
import IssueCaptureSchema
@testable import CompanionCore

/// Acceptance scenarios for import, evidence preservation and revisioning.
final class ImportTests: XCTestCase {
    private var workspace: URL!
    private var store: EvidenceStore!
    private var service: ImportService!

    override func setUpWithError() throws {
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("companion-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        store = try EvidenceStore(root: workspace.appendingPathComponent("store"))
        service = ImportService(store: store)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workspace)
    }

    private func archiveURL(_ name: String = "export.zip") -> URL {
        workspace.appendingPathComponent(name)
    }

    // MARK: - Repeated archive import

    func testRepeatedArchiveImportIsIdempotent() throws {
        let spec = ExportFixture.IssueSpec()
        let url = try ExportFixture.writeArchive(issues: [spec], at: archiveURL(), workspace: workspace)

        let first = try service.importArchive(at: url)
        XCTAssertFalse(first.wasExactRepeat)
        XCTAssertEqual(first.newRevisions.count, 1)

        let second = try service.importArchive(at: url)
        XCTAssertTrue(second.wasExactRepeat)
        XCTAssertEqual(second.provenance.id, first.provenance.id)
        XCTAssertEqual(store.revisions.count, 1)
        XCTAssertEqual(store.imports.count, 1)
    }

    func testSameContentInADifferentArchiveRetainsProvenanceWithoutNewRevision() throws {
        let spec = ExportFixture.IssueSpec()
        let first = try ExportFixture.writeArchive(issues: [spec], at: archiveURL("a.zip"),
                                                   workspace: workspace,
                                                   exportedAt: Date(timeIntervalSinceReferenceDate: 1))
        let second = try ExportFixture.writeArchive(issues: [spec], at: archiveURL("b.zip"),
                                                    workspace: workspace,
                                                    exportedAt: Date(timeIntervalSinceReferenceDate: 2))
        _ = try service.importArchive(at: first)
        let result = try service.importArchive(at: second)

        XCTAssertFalse(result.wasExactRepeat)
        XCTAssertTrue(result.newRevisions.isEmpty)
        XCTAssertEqual(result.unchangedRevisions.count, 1)
        XCTAssertEqual(store.revisions.count, 1)
        XCTAssertEqual(store.imports.count, 2, "both receipts are retained")
        XCTAssertEqual(store.revisions[0].importIDs.count, 2)
    }

    func testChangedContentCreatesARevisionWithoutOverwritingTheOriginal() throws {
        var spec = ExportFixture.IssueSpec()
        let first = try ExportFixture.writeArchive(issues: [spec], at: archiveURL("a.zip"),
                                                   workspace: workspace)
        _ = try service.importArchive(at: first)

        spec.description = "Save button does nothing, still broken after relaunch"
        let second = try ExportFixture.writeArchive(issues: [spec], at: archiveURL("b.zip"),
                                                    workspace: workspace)
        let result = try service.importArchive(at: second)

        XCTAssertEqual(result.newRevisions.count, 1)
        let revisions = store.revisions(for: IssueKey(projectID: spec.projectID, issueID: spec.id))
        XCTAssertEqual(revisions.map(\.revisionIndex), [1, 2])
        XCTAssertEqual(revisions[0].report.description, "Save button does nothing")
        XCTAssertEqual(revisions[1].report.description, spec.description)
    }

    func testExportPreparedAtDoesNotCreateARevision() throws {
        var spec = ExportFixture.IssueSpec()
        let first = try ExportFixture.writeArchive(issues: [spec], at: archiveURL("a.zip"),
                                                   workspace: workspace)
        _ = try service.importArchive(at: first)

        var report = spec.report
        report.exportPreparedAt = [Date(timeIntervalSinceReferenceDate: 900_000)]
        spec.description = report.description
        let folder = workspace.appendingPathComponent("second-export")
        try ExportFixture.writeFolder(issues: [spec], at: folder)
        try IssueExportSchema.encoder().encode(report).write(
            to: folder.appendingPathComponent("issues/\(spec.id.uuidString)/issue.json"))
        try StoredZIP.archive(directory: folder, to: archiveURL("b.zip"))

        let result = try service.importArchive(at: archiveURL("b.zip"))
        XCTAssertTrue(result.newRevisions.isEmpty, "export preparation history is not issue content")
        XCTAssertEqual(result.unchangedRevisions.count, 1)
    }

    // MARK: - Identity

    func testEditedUUIDIsRejected() throws {
        let spec = ExportFixture.IssueSpec()
        let url = try ExportFixture.writeArchive(issues: [spec], at: archiveURL(), workspace: workspace,
                                                 manifestOverrides: [spec.id: UUID()])
        XCTAssertThrowsError(try service.importArchive(at: url)) { error in
            XCTAssertEqual((error as? ImportFailure)?.code, .identityMismatch)
        }
        XCTAssertTrue(store.revisions.isEmpty)
        XCTAssertTrue(store.imports.isEmpty)
    }

    func testSameShortIDWithDifferentUUIDsStaysDistinct() throws {
        // Two UUIDs whose first eight characters, and therefore whose display
        // IDs, are identical.
        let first = UUID(uuidString: "AAAAAAAA-1111-4111-8111-111111111111")!
        let second = UUID(uuidString: "AAAAAAAA-2222-4222-8222-222222222222")!
        var alpha = ExportFixture.IssueSpec(); alpha.id = first
        var beta = ExportFixture.IssueSpec(); beta.id = second
        beta.description = "Different issue, same short label"
        XCTAssertEqual(alpha.report.displayID, beta.report.displayID)

        let url = try ExportFixture.writeArchive(issues: [alpha, beta], at: archiveURL(),
                                                 workspace: workspace)
        let result = try service.importArchive(at: url)
        XCTAssertEqual(result.newRevisions.count, 2)
        XCTAssertEqual(Set(store.revisions.map(\.issueKey.issueID)), [first, second])
    }

    func testDuplicateManifestEntriesAreRejected() throws {
        let spec = ExportFixture.IssueSpec()
        let folder = workspace.appendingPathComponent("dupe")
        try ExportFixture.writeFolder(issues: [spec], at: folder, duplicateFirstEntry: true)
        XCTAssertThrowsError(try service.importFolder(at: folder)) { error in
            XCTAssertEqual((error as? ImportFailure)?.code, .duplicateIssueIdentity)
        }
    }

    func testUnsupportedManifestVersionIsRejected() throws {
        let spec = ExportFixture.IssueSpec()
        let url = try ExportFixture.writeArchive(issues: [spec], at: archiveURL(), workspace: workspace,
                                                 manifestSchemaVersion: 99)
        XCTAssertThrowsError(try service.importArchive(at: url)) { error in
            XCTAssertEqual((error as? ImportFailure)?.code, .unsupportedManifestVersion)
        }
    }

    // MARK: - Evidence pairing

    func testCompressedImageFilenamesResolveThroughTheImageMap() throws {
        var spec = ExportFixture.IssueSpec()
        spec.images = [
            "screenshot": ("screenshot-original.jpg", Data("jpeg-screenshot".utf8)),
            "annotation": ("screenshot-annotated.jpg", Data("jpeg-annotated".utf8))
        ]
        spec.annotations = [IssueAnnotation(kind: .arrow, points: [IssuePoint(x: 0.1, y: 0.2)])]
        let url = try ExportFixture.writeArchive(issues: [spec], at: archiveURL(), workspace: workspace)
        let result = try service.importArchive(at: url)

        let revision = try XCTUnwrap(result.newRevisions.first)
        XCTAssertEqual(revision.fact(for: .screenshot)?.filename, "screenshot-original.jpg")
        XCTAssertEqual(revision.fact(for: .annotation)?.filename, "screenshot-annotated.jpg")
        XCTAssertTrue(revision.warnings.isEmpty)
        let resolved = try XCTUnwrap(store.url(in: revision, kind: .annotation))
        XCTAssertEqual(try Data(contentsOf: resolved), Data("jpeg-annotated".utf8))
    }

    func testMissingDeclaredImageIsAnIssueLevelWarningNotASilentOmission() throws {
        var spec = ExportFixture.IssueSpec()
        spec.images = [
            "screenshot": ("screenshot-original.png", Data("screenshot-bytes".utf8)),
            "attachment": ("attachment.png", Data("attached".utf8))
        ]
        spec.hasAttachment = true
        spec.omittedFiles = ["attachment.png"]
        let url = try ExportFixture.writeArchive(issues: [spec], at: archiveURL(), workspace: workspace)
        let result = try service.importArchive(at: url)

        let revision = try XCTUnwrap(result.newRevisions.first)
        XCTAssertNil(revision.fact(for: .attachment))
        XCTAssertTrue(revision.warnings.contains { $0.code == .missingDeclaredImage })
        XCTAssertTrue(revision.warnings.contains { $0.detail.contains("attachment.png") })
    }

    func testAnnotatedManualAttachmentRetainsBothImages() throws {
        var spec = ExportFixture.IssueSpec()
        spec.hasScreenshot = false
        spec.hasAttachment = true
        spec.images = [
            "attachment": ("attachment.png", Data("manual-photo".utf8)),
            "annotation": ("screenshot-annotated.png", Data("manual-photo-with-arrow".utf8))
        ]
        spec.annotations = [IssueAnnotation(kind: .arrow, points: [IssuePoint(x: 0.5, y: 0.5)])]
        let url = try ExportFixture.writeArchive(issues: [spec], at: archiveURL(), workspace: workspace)
        let revision = try XCTUnwrap(try service.importArchive(at: url).newRevisions.first)

        XCTAssertNotNil(revision.fact(for: .attachment))
        XCTAssertNotNil(revision.fact(for: .annotation))
        let decisions = AttachmentPolicy.decisions(for: revision, overrides: .init())
        let attached = Set(decisions.filter(\.isAttached).map(\.kind))
        XCTAssertEqual(attached, [.annotation, .attachment])
    }

    func testEvidenceIsPreservedByteForByte() throws {
        var spec = ExportFixture.IssueSpec()
        let bytes = Data((0..<512).map { UInt8($0 % 251) })
        spec.images = ["screenshot": ("screenshot-original.png", bytes)]
        let url = try ExportFixture.writeArchive(issues: [spec], at: archiveURL(), workspace: workspace)
        let revision = try XCTUnwrap(try service.importArchive(at: url).newRevisions.first)

        let stored = try XCTUnwrap(store.url(in: revision, kind: .screenshot))
        XCTAssertEqual(try Data(contentsOf: stored), bytes)
        let reportBytes = try Data(contentsOf: store.url(in: revision, filename: "issue.json"))
        XCTAssertEqual(try JSONDecoder().decode(IssueReport.self, from: reportBytes).id, spec.id)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: store.url(in: revision, filename: "issue.md").path), "received Markdown is kept")
    }

    // MARK: - Archive safety

    func testTraversalPathIsRejected() throws {
        let url = archiveURL("evil.zip")
        try StoredZIP.write(members: [
            .init(path: "manifest.json", bytes: Data("{}".utf8)),
            .init(path: "../escape.txt", bytes: Data("nope".utf8))
        ], to: url)
        XCTAssertThrowsError(try service.importArchive(at: url)) { error in
            XCTAssertEqual((error as? ImportFailure)?.code, .unsafeArchivePath)
        }
    }

    func testAbsolutePathIsRejected() throws {
        let url = archiveURL("absolute.zip")
        try StoredZIP.write(members: [.init(path: "/etc/passwd", bytes: Data("nope".utf8))], to: url)
        XCTAssertThrowsError(try service.importArchive(at: url)) { error in
            XCTAssertEqual((error as? ImportFailure)?.code, .unsafeArchivePath)
        }
    }

    func testSymbolicLinkEntryIsRejected() throws {
        let url = archiveURL("symlink.zip")
        try StoredZIP.write(members: [
            .init(path: "link.png", bytes: Data("/etc/passwd".utf8), unixMode: 0xA1FF)
        ], to: url)
        XCTAssertThrowsError(try service.importArchive(at: url)) { error in
            XCTAssertEqual((error as? ImportFailure)?.code, .unsafeArchivePath)
        }
    }

    func testDuplicateArchiveEntryPathIsRejected() throws {
        let url = archiveURL("dupe-entry.zip")
        try StoredZIP.write(members: [
            .init(path: "issues/a.json", bytes: Data("one".utf8)),
            .init(path: "issues/a.json", bytes: Data("two".utf8))
        ], to: url)
        XCTAssertThrowsError(try service.importArchive(at: url)) { error in
            XCTAssertEqual((error as? ImportFailure)?.code, .unsafeArchivePath)
        }
    }

    func testCompressedEntryIsReportedRatherThanPartiallyImported() throws {
        let url = archiveURL("deflated.zip")
        try StoredZIP.write(members: [
            .init(path: "manifest.json", bytes: Data("{}".utf8), method: 8)
        ], to: url)
        XCTAssertThrowsError(try service.importArchive(at: url)) { error in
            let failure = error as? ImportFailure
            XCTAssertEqual(failure?.code, .unsupportedCompression)
            XCTAssertTrue(failure?.detail.contains("stored") == true)
        }
        XCTAssertTrue(store.imports.isEmpty)
    }

    func testEntryCountLimitIsEnforced() throws {
        let url = archiveURL("many.zip")
        try StoredZIP.write(members: (0..<20).map {
            .init(path: "file-\($0).txt", bytes: Data("x".utf8))
        }, to: url)
        let limited = ImportService(store: store, limits: .init(maximumEntries: 5))
        XCTAssertThrowsError(try limited.importArchive(at: url)) { error in
            XCTAssertEqual((error as? ImportFailure)?.code, .archiveLimitExceeded)
        }
    }

    func testChecksumMismatchIsRejected() throws {
        let spec = ExportFixture.IssueSpec()
        let url = try ExportFixture.writeArchive(issues: [spec], at: archiveURL(), workspace: workspace)
        var bytes = try Data(contentsOf: url)
        // Corrupt a payload byte without touching any header signature.
        let index = bytes.count / 2
        bytes[index] = bytes[index] &+ 1
        try bytes.write(to: url)
        XCTAssertThrowsError(try service.importArchive(at: url)) { error in
            let code = (error as? ImportFailure)?.code
            XCTAssertTrue(code == .checksumMismatch || code == .notAnExport, "got \(String(describing: code))")
        }
    }

    func testNonExportArchiveIsRejectedWithAnActionableMessage() throws {
        let url = archiveURL("random.zip")
        try StoredZIP.write(members: [.init(path: "notes.txt", bytes: Data("hello".utf8))], to: url)
        XCTAssertThrowsError(try service.importArchive(at: url)) { error in
            let failure = error as? ImportFailure
            XCTAssertEqual(failure?.code, .notAnExport)
            XCTAssertTrue(failure?.detail.contains("manifest.json") == true)
        }
    }

    func testFolderImportAcceptsAnExpandedExport() throws {
        let spec = ExportFixture.IssueSpec()
        let folder = workspace.appendingPathComponent("expanded")
        try ExportFixture.writeFolder(issues: [spec], at: folder)
        let result = try service.importFolder(at: folder)
        XCTAssertEqual(result.newRevisions.count, 1)
        XCTAssertEqual(result.provenance.sourceKind, .folder)
        XCTAssertNil(result.provenance.archiveSHA256)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("manifest.json").path),
                      "source files are never moved")
    }

    func testFolderImportAcceptsAWrapperFolderAroundTheExport() throws {
        let spec = ExportFixture.IssueSpec()
        let wrapper = workspace.appendingPathComponent("wrapper")
        try FileManager.default.createDirectory(at: wrapper, withIntermediateDirectories: true)
        try ExportFixture.writeFolder(issues: [spec], at: wrapper.appendingPathComponent("IssueCapture-export"))
        XCTAssertEqual(try service.importFolder(at: wrapper).newRevisions.count, 1)
    }
}
