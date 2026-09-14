import XCTest
import IssueCaptureSchema
@testable import CompanionCore

/// Acceptance scenarios for lossless request assembly and attachment policy.
final class RequestTests: XCTestCase {
    private var workspace: URL!
    private var store: EvidenceStore!
    private var service: ImportService!
    private var assembler: RequestAssembler!

    override func setUpWithError() throws {
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("companion-request-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        store = try EvidenceStore(root: workspace.appendingPathComponent("store"))
        service = ImportService(store: store)
        assembler = RequestAssembler(store: store)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workspace)
    }

    @discardableResult
    private func importSpecs(_ specs: [ExportFixture.IssueSpec], name: String = "export.zip") throws -> ImportResult {
        let url = try ExportFixture.writeArchive(issues: specs,
                                                 at: workspace.appendingPathComponent(name),
                                                 workspace: workspace,
                                                 exportedAt: Date(timeIntervalSinceReferenceDate: Double(name.count)))
        return try service.importArchive(at: url)
    }

    private func currentBatches(overrides: BatchOverrides = .init()) -> [CandidateBatch] {
        let inputs = store.currentRevisions().map {
            BatchEngine.Input(key: $0.issueKey, revisionID: $0.id, report: $0.report)
        }
        return BatchEngine.propose(inputs: inputs, overrides: overrides).batches
    }

    private func spec(_ index: Int, mutate: (inout ExportFixture.IssueSpec) -> Void = { _ in })
        -> ExportFixture.IssueSpec {
        var spec = ExportFixture.IssueSpec()
        spec.id = UUID(uuidString: String(format: "%08X-0000-4000-8000-000000000000", index))!
        spec.capturedAt = Date(timeIntervalSinceReferenceDate: 700_000 + Double(index))
        spec.images = ["screenshot": ("screenshot-original.png", Data("shot-\(index)".utf8))]
        mutate(&spec)
        return spec
    }

    // MARK: - Folder contract

    func testPreparedRequestFolderHoldsMarkdownJSONAndEvidence() throws {
        try importSpecs([spec(1), spec(2)].map { specValue in
            var copy = specValue
            copy.screens = [ExportFixture.screen(name: "Profile", stableID: "profile")]
            return copy
        })
        let batch = try XCTUnwrap(currentBatches().first)
        let handle = try assembler.prepare(batch: batch, overrides: .init())

        let manager = FileManager.default
        XCTAssertTrue(manager.fileExists(atPath: handle.folder.appendingPathComponent("request.md").path))
        XCTAssertTrue(manager.fileExists(atPath: handle.folder.appendingPathComponent("request.json").path))
        for issue in handle.request.issues {
            let evidence = handle.folder.appendingPathComponent(issue.evidencePath)
            XCTAssertTrue(manager.fileExists(atPath: evidence.appendingPathComponent("issue.json").path))
            XCTAssertTrue(manager.fileExists(atPath: evidence.appendingPathComponent("issue.md").path))
            XCTAssertTrue(manager.fileExists(atPath: evidence.appendingPathComponent("images.json").path))
        }
        let decoded = try JSONDecoder().decode(
            PreparedRequest.self,
            from: Data(contentsOf: handle.folder.appendingPathComponent("request.json")))
        XCTAssertEqual(decoded.id, handle.request.id)
        XCTAssertEqual(decoded.ruleVersion, BatchEngine.ruleVersion)
        XCTAssertEqual(decoded.templateVersion, PreparedRequest.templateVersion)
        XCTAssertEqual(decoded.issues.map(\.revisionID), batch.members.map(\.revisionID))
        XCTAssertFalse(decoded.groupingReasons.isEmpty)
    }

    func testRequestMarkdownReproducesAuthoredTextExactly() throws {
        let long = String(repeating: "The save button does nothing at all. ", count: 40)
        try importSpecs([spec(1) { $0.description = long; $0.expectedBehavior = "" }])
        let batch = try XCTUnwrap(currentBatches().first)
        let handle = try assembler.prepare(batch: batch, overrides: .init())
        let markdown = try String(contentsOf: handle.markdownURL, encoding: .utf8)

        XCTAssertTrue(markdown.contains(long), "complete source text is preserved")
        XCTAssertTrue(markdown.contains(batch.members[0].key.issueID.uuidString))
        XCTAssertTrue(markdown.contains("_Not supplied by the reporter._"))
        XCTAssertTrue(markdown.contains("observations recorded before capture, not inferred reproduction steps"))
        XCTAssertTrue(markdown.contains("does not override repository policy"))
        XCTAssertFalse(markdown.lowercased().contains("run the test"),
                       "no blanket instruction to run tests")
    }

    func testDragExposesTheMarkdownAndTheChosenImages() throws {
        try importSpecs([spec(1)])
        let handle = try assembler.prepare(batch: try XCTUnwrap(currentBatches().first), overrides: .init())
        XCTAssertEqual(handle.dragURLs.count, 2)
        XCTAssertEqual(handle.dragURLs.first?.lastPathComponent, "request.md")
        for url in handle.dragURLs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "\(url.path) is a real file")
        }
        XCTAssertFalse(assembler.promptText(for: handle).isEmpty)
    }

    // MARK: - Attachment policy

    func testAnnotatedImageIsTheDefaultAndTheCaptureStaysInTheBundle() throws {
        try importSpecs([spec(1) {
            $0.annotations = [IssueAnnotation(kind: .arrow, points: [IssuePoint(x: 0.2, y: 0.3)])]
            $0.images = ["screenshot": ("screenshot-original.png", Data("plain".utf8)),
                         "annotation": ("screenshot-annotated.png", Data("marked".utf8))]
        }])
        let handle = try assembler.prepare(batch: try XCTUnwrap(currentBatches().first), overrides: .init())
        let issue = try XCTUnwrap(handle.request.issues.first)

        XCTAssertEqual(Set(handle.request.attachments.flatMap { $0.links.map(\.kind) }), [.annotation])
        let screenshot = try XCTUnwrap(issue.attachmentDecisions.first { $0.kind == .screenshot })
        XCTAssertFalse(screenshot.isAttached)
        XCTAssertTrue(screenshot.reason.contains("evidence bundle"))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: handle.folder.appendingPathComponent(issue.evidencePath)
                .appendingPathComponent("screenshot-original.png").path))
    }

    func testBothImagesCanBeAttachedExplicitly() throws {
        try importSpecs([spec(1) {
            $0.annotations = [IssueAnnotation(kind: .pen, points: [IssuePoint(x: 0.1, y: 0.1)])]
            $0.images = ["screenshot": ("screenshot-original.png", Data("plain".utf8)),
                         "annotation": ("screenshot-annotated.png", Data("marked".utf8))]
        }])
        let handle = try assembler.prepare(batch: try XCTUnwrap(currentBatches().first), overrides: .init(),
                                           options: .init(includeUnannotatedWithAnnotated: true))
        XCTAssertEqual(handle.request.attachmentCount, 2)
    }

    func testIssueCardsAreOmittedByDefault() throws {
        try importSpecs([spec(1) {
            $0.images = ["screenshot": ("screenshot-original.png", Data("plain".utf8)),
                         "card": ("issue-card.png", Data("card".utf8))]
        }])
        let handle = try assembler.prepare(batch: try XCTUnwrap(currentBatches().first), overrides: .init())
        let card = try XCTUnwrap(handle.request.issues.first?.attachmentDecisions.first { $0.kind == .card })
        XCTAssertFalse(card.isAttached)
        XCTAssertTrue(card.reason.contains("repeat the report text"))
        XCTAssertEqual(handle.request.attachmentCount, 1)
    }

    func testManualAttachmentMatchingAnIncludedImageIsDeduplicated() throws {
        let shared = Data("identical-bytes".utf8)
        try importSpecs([spec(1) {
            $0.hasAttachment = true
            $0.images = ["screenshot": ("screenshot-original.png", shared),
                         "attachment": ("attachment.png", shared)]
        }])
        let handle = try assembler.prepare(batch: try XCTUnwrap(currentBatches().first), overrides: .init())
        XCTAssertEqual(handle.request.attachmentCount, 1)
        let attachment = try XCTUnwrap(handle.request.issues.first?
            .attachmentDecisions.first { $0.kind == .attachment })
        XCTAssertFalse(attachment.isAttached)
        XCTAssertTrue(attachment.reason.contains("Identical bytes"))
    }

    func testIdenticalBytesAcrossIssuesShareOneFileButKeepEveryLink() throws {
        let shared = Data("same-screen-same-bug".utf8)
        try importSpecs([spec(1) {
            $0.screens = [ExportFixture.screen(name: "Profile", stableID: "profile")]
            $0.images = ["screenshot": ("screenshot-original.png", shared)]
        }, spec(2) {
            $0.screens = [ExportFixture.screen(name: "Profile", stableID: "profile")]
            $0.images = ["screenshot": ("screenshot-original.png", shared)]
        }])
        let handle = try assembler.prepare(batch: try XCTUnwrap(currentBatches().first), overrides: .init())
        XCTAssertEqual(handle.request.issues.count, 2)
        XCTAssertEqual(handle.request.attachmentCount, 1, "identical bytes are attached once")
        XCTAssertEqual(handle.request.attachments[0].links.count, 2, "both issue links are retained")
        XCTAssertEqual(Set(handle.request.attachments[0].links.map(\.issueID)),
                       Set(handle.request.issues.map(\.issueID)))
    }

    func testExcludingAnImageChangesAttachmentsWithoutRemovingEvidence() throws {
        try importSpecs([spec(1)])
        let revision = try XCTUnwrap(store.currentRevisions().first)
        var overrides = BatchOverrides()
        overrides.setExcluded(true, key: revision.issueKey, revisionID: revision.id, kind: .screenshot)
        let handle = try assembler.prepare(batch: try XCTUnwrap(currentBatches(overrides: overrides).first),
                                           overrides: overrides)
        XCTAssertEqual(handle.request.attachmentCount, 0)
        let evidence = handle.folder.appendingPathComponent(handle.request.issues[0].evidencePath)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: evidence.appendingPathComponent("screenshot-original.png").path))
    }

    func testAttachmentCountAndBytesAreExact() throws {
        let first = Data(repeating: 0x41, count: 120)
        let second = Data(repeating: 0x42, count: 340)
        try importSpecs([spec(1) {
            $0.screens = [ExportFixture.screen(name: "Profile", stableID: "profile")]
            $0.images = ["screenshot": ("screenshot-original.png", first)]
        }, spec(2) {
            $0.screens = [ExportFixture.screen(name: "Profile", stableID: "profile")]
            $0.images = ["screenshot": ("screenshot-original.png", second)]
        }])
        let handle = try assembler.prepare(batch: try XCTUnwrap(currentBatches().first), overrides: .init())
        XCTAssertEqual(handle.request.attachmentCount, 2)
        XCTAssertEqual(handle.request.attachmentByteCount, 460)
        for attachment in handle.request.attachments {
            let data = try Data(contentsOf: handle.folder.appendingPathComponent(attachment.path))
            XCTAssertEqual(data.count, attachment.byteCount)
            XCTAssertEqual(Digest.sha256(data), attachment.sha256)
        }
    }

    func testWarningsTravelIntoThePreparedRequest() throws {
        try importSpecs([spec(1) {
            $0.hasAttachment = true
            $0.images = ["screenshot": ("screenshot-original.png", Data("plain".utf8)),
                         "attachment": ("attachment.png", Data("missing".utf8))]
            $0.omittedFiles = ["attachment.png"]
        }])
        let handle = try assembler.prepare(batch: try XCTUnwrap(currentBatches().first), overrides: .init())
        XCTAssertTrue(handle.request.issues[0].warnings.contains { $0.code == .missingDeclaredImage })
        let markdown = try String(contentsOf: handle.markdownURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("Evidence warnings"))
    }

    // MARK: - Stability

    func testPreparedRequestIsUnchangedAfterNewerEvidenceArrives() throws {
        var target = spec(1)
        try importSpecs([target], name: "first.zip")
        let handle = try assembler.prepare(batch: try XCTUnwrap(currentBatches().first), overrides: .init())
        let markdownBefore = try String(contentsOf: handle.markdownURL, encoding: .utf8)
        let jsonBefore = try Data(contentsOf: handle.folder.appendingPathComponent("request.json"))
        let evidenceBefore = try Data(contentsOf: handle.folder
            .appendingPathComponent(handle.request.issues[0].evidencePath)
            .appendingPathComponent("screenshot-original.png"))

        target.description = "Rewritten after more testing"
        target.images = ["screenshot": ("screenshot-original.png", Data("new-shot".utf8))]
        let second = try importSpecs([target], name: "second-export.zip")
        XCTAssertEqual(second.newRevisions.count, 1, "newer evidence is a new revision")

        XCTAssertEqual(try String(contentsOf: handle.markdownURL, encoding: .utf8), markdownBefore)
        XCTAssertEqual(try Data(contentsOf: handle.folder.appendingPathComponent("request.json")), jsonBefore)
        XCTAssertEqual(try Data(contentsOf: handle.folder
            .appendingPathComponent(handle.request.issues[0].evidencePath)
            .appendingPathComponent("screenshot-original.png")), evidenceBefore)
        XCTAssertEqual(assembler.storedRequests().count, 1)
    }

    func testPreparingTwiceCreatesSeparateVersionedFolders() throws {
        try importSpecs([spec(1)])
        let batch = try XCTUnwrap(currentBatches().first)
        let first = try assembler.prepare(batch: batch, overrides: .init())
        let second = try assembler.prepare(batch: batch, overrides: .init())
        XCTAssertNotEqual(first.folder, second.folder)
        XCTAssertEqual(assembler.storedRequests().count, 2)
    }

    func testMissingEvidenceForAMemberFailsRatherThanSilentlySkipping() throws {
        try importSpecs([spec(1)])
        let batch = try XCTUnwrap(currentBatches().first)
        let broken = CandidateBatch(id: batch.id, ruleVersion: batch.ruleVersion,
                                    projectID: batch.projectID, environmentKey: batch.environmentKey,
                                    members: [BatchMember(key: batch.members[0].key,
                                                          revisionID: "not-in-store",
                                                          capturedAt: Date(), displayID: "ISSUE-X")],
                                    reasons: batch.reasons, relatedNotes: [], origin: .rule,
                                    title: batch.title)
        XCTAssertThrowsError(try assembler.prepare(batch: broken, overrides: .init())) { error in
            XCTAssertEqual((error as? ImportFailure)?.code, .storageFailure)
        }
    }

    func testUserInstructionsAreKeptSeparateFromReportContent() throws {
        try importSpecs([spec(1)])
        let batch = try XCTUnwrap(currentBatches().first)
        var overrides = BatchOverrides()
        overrides.instructions[batch.id] = "Check the analytics wrapper first."
        let handle = try assembler.prepare(batch: batch, overrides: overrides)
        let markdown = try String(contentsOf: handle.markdownURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("Additional instructions from the person preparing this request"))
        XCTAssertTrue(markdown.contains("Check the analytics wrapper first."))
        XCTAssertEqual(handle.request.issues[0].revisionID, batch.members[0].revisionID,
                       "instructions do not alter captured evidence")
    }
}
