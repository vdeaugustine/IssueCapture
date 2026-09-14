import XCTest
import IssueCaptureSchema
@testable import CompanionCore

/// Acceptance scenarios for the deterministic rule engine.
final class BatchingTests: XCTestCase {
    private func input(_ spec: ExportFixture.IssueSpec, revision: String = "rev") -> BatchEngine.Input {
        BatchEngine.Input(key: IssueKey(projectID: spec.projectID, issueID: spec.id),
                          revisionID: revision + "-" + spec.id.uuidString, report: spec.report)
    }

    private func spec(_ index: Int, mutate: (inout ExportFixture.IssueSpec) -> Void = { _ in })
        -> ExportFixture.IssueSpec {
        var spec = ExportFixture.IssueSpec()
        spec.id = UUID(uuidString: String(format: "%08X-0000-4000-8000-000000000000", index))!
        spec.capturedAt = Date(timeIntervalSinceReferenceDate: 700_000 + Double(index))
        mutate(&spec)
        return spec
    }

    // MARK: - Determinism

    func testSameInputsProduceIdenticalMembershipsAndOrdering() throws {
        let specs = (1...7).map { index in
            spec(index) { $0.screens = [ExportFixture.screen(name: index.isMultiple(of: 2) ? "Profile" : "Home")] }
        }
        let inputs = specs.map { input($0) }
        let first = BatchEngine.propose(inputs: inputs)
        let second = BatchEngine.propose(inputs: inputs.shuffled())
        XCTAssertEqual(first.batches.map(\.id), second.batches.map(\.id))
        XCTAssertEqual(first.batches.map { $0.members.map(\.id) },
                       second.batches.map { $0.members.map(\.id) })
    }

    func testEveryBatchCarriesItsRuleVersionAndReasons() throws {
        let proposal = BatchEngine.propose(inputs: [input(spec(1))])
        let batch = try XCTUnwrap(proposal.batches.first)
        XCTAssertEqual(batch.ruleVersion, BatchEngine.ruleVersion)
        XCTAssertFalse(batch.reasons.isEmpty)
    }

    // MARK: - Partitioning

    func testProjectsAreNeverMixedAutomatically() throws {
        let alpha = spec(1) { $0.projectID = "alpha" }
        let beta = spec(2) { $0.projectID = "beta" }
        let proposal = BatchEngine.propose(inputs: [input(alpha), input(beta)])
        XCTAssertEqual(proposal.batches.count, 2)
        for batch in proposal.batches { XCTAssertEqual(batch.members.count, 1) }
    }

    func testDifferentBuildsArePartitionedApart() throws {
        let old = spec(1) { $0.environment["build"] = "44" }
        let new = spec(2) { $0.environment["build"] = "45" }
        let proposal = BatchEngine.propose(inputs: [input(old), input(new)])
        XCTAssertEqual(proposal.batches.count, 2)
        XCTAssertEqual(Set(proposal.batches.map(\.environmentKey.build)), ["44", "45"])
    }

    func testMissingBuildMetadataStaysInItsOwnPartition() throws {
        let known = spec(1)
        let unavailable = spec(2) { $0.environment["build"] = "unavailable" }
        let absent = spec(3) { $0.environment.removeValue(forKey: "build") }
        let proposal = BatchEngine.propose(inputs: [known, unavailable, absent].map { input($0) })
        let partitions = Set(proposal.batches.map(\.environmentKey))
        XCTAssertEqual(partitions.count, 2, "the two missing-build issues share one partition")
        XCTAssertTrue(partitions.contains { !$0.isComplete })
        let incomplete = try XCTUnwrap(proposal.batches.first { !$0.environmentKey.isComplete })
        XCTAssertEqual(incomplete.members.count, 2)
        XCTAssertEqual(incomplete.environmentKey.label, "1.2.0 (build not recorded)")
    }

    // MARK: - Explicit batch tags

    func testExplicitBatchTagGroupsWithinAPartition() throws {
        let specs = (1...3).map { index in
            spec(index) {
                $0.tags = ["batch:checkout", "ui"]
                $0.screens = [ExportFixture.screen(name: "Screen\(index)")]
            }
        }
        let proposal = BatchEngine.propose(inputs: specs.map { input($0) })
        XCTAssertEqual(proposal.batches.count, 1)
        let batch = try XCTUnwrap(proposal.batches.first)
        XCTAssertEqual(batch.members.count, 3)
        XCTAssertEqual(batch.title, "checkout")
        XCTAssertTrue(batch.reasons.contains { $0.code == .explicitBatchTag })
    }

    func testMultipleBatchTagsLeaveTheIssueUnbatchedWithAConflictExplanation() throws {
        let conflicted = spec(1) { $0.tags = ["batch:one", "batch:two"] }
        let partner = spec(2) { $0.tags = ["batch:one"] }
        let proposal = BatchEngine.propose(inputs: [conflicted, partner].map { input($0) })
        let solo = try XCTUnwrap(proposal.batches.first { $0.members.count == 1 })
        XCTAssertEqual(solo.members.first?.key.issueID, conflicted.id)
        let reason = try XCTUnwrap(solo.reasons.first { $0.code == .batchTagConflict })
        XCTAssertTrue(reason.detail.contains("batch:one"))
        XCTAssertTrue(reason.detail.contains("batch:two"))
    }

    // MARK: - Screen rules

    func testSharedStableScreenIDGroupsIssues() throws {
        let specs = (1...2).map { index in
            spec(index) { $0.screens = [ExportFixture.screen(name: "Profile", stableID: "profile-root")] }
        }
        let proposal = BatchEngine.propose(inputs: specs.map { input($0) })
        XCTAssertEqual(proposal.batches.count, 1)
        let reason = try XCTUnwrap(proposal.batches.first?.reasons.first)
        XCTAssertEqual(reason.code, .sharedScreen)
        XCTAssertTrue(reason.detail.contains("profile-root"))
    }

    func testMountedScreenUUIDsAreNotUsedForGrouping() throws {
        // Same stable screen, different mounted instance identities.
        let specs = (1...2).map { index in
            spec(index) {
                $0.screens = [ExportFixture.screen(name: "Profile", stableID: "profile-root", id: UUID())]
            }
        }
        XCTAssertEqual(BatchEngine.propose(inputs: specs.map { input($0) }).batches.count, 1)
    }

    func testSameTypeInDifferentSourceFilesDoesNotGroup() throws {
        let first = spec(1) { $0.screens = [ExportFixture.screen(name: "Profile", file: "A/Profile.swift")] }
        let second = spec(2) { $0.screens = [ExportFixture.screen(name: "Profile", file: "B/Profile.swift")] }
        let proposal = BatchEngine.propose(inputs: [first, second].map { input($0) })
        XCTAssertEqual(proposal.batches.count, 2)
    }

    func testAmbiguousScreensStayIndividual() throws {
        let specs = (1...2).map { index in
            spec(index) {
                $0.contextStatus = IssueContextStatus.ambiguous
                $0.screens = [ExportFixture.screen(name: "Profile", stableID: "profile-root"),
                              ExportFixture.screen(name: "Sheet", stableID: "sheet-root")]
            }
        }
        let proposal = BatchEngine.propose(inputs: specs.map { input($0) })
        XCTAssertEqual(proposal.batches.count, 2)
        for batch in proposal.batches {
            XCTAssertTrue(batch.reasons.contains { $0.code == .ambiguousScreen })
        }
    }

    func testUnregisteredScreensStayIndividual() throws {
        let specs = (1...2).map { index in
            spec(index) {
                $0.contextStatus = IssueContextStatus.missing
                $0.screens = []
            }
        }
        let proposal = BatchEngine.propose(inputs: specs.map { input($0) })
        XCTAssertEqual(proposal.batches.count, 2)
        for batch in proposal.batches {
            XCTAssertTrue(batch.reasons.contains { $0.code == .unregisteredScreen })
        }
    }

    func testNestedScreensUseTheLeafCandidate() throws {
        let parent = ExportFixture.screen(name: "Tabs", stableID: "tabs")
        let specs = (1...2).map { index in
            spec(index) {
                $0.screens = [parent,
                              ExportFixture.screen(name: "Profile", stableID: "profile-root",
                                                   parentID: parent.id)]
            }
        }
        let proposal = BatchEngine.propose(inputs: specs.map { input($0) })
        XCTAssertEqual(proposal.batches.count, 1)
        XCTAssertTrue(proposal.batches[0].reasons[0].detail.contains("profile-root"))
    }

    func testUnrecognizedContextStatusStaysIndividual() throws {
        let specs = (1...2).map { index in
            spec(index) {
                $0.contextStatus = "something a future build wrote"
                $0.screens = [ExportFixture.screen(name: "Profile", stableID: "profile-root")]
            }
        }
        let proposal = BatchEngine.propose(inputs: specs.map { input($0) })
        XCTAssertEqual(proposal.batches.count, 2)
        for batch in proposal.batches {
            XCTAssertTrue(batch.reasons.contains { $0.code == .unrecognizedContextStatus })
        }
    }

    // MARK: - Related items

    func testOrdinaryTagsExplainButDoNotMerge() throws {
        let first = spec(1) {
            $0.tags = ["ui"]
            $0.screens = [ExportFixture.screen(name: "Home", stableID: "home")]
        }
        let second = spec(2) {
            $0.tags = ["ui"]
            $0.screens = [ExportFixture.screen(name: "Profile", stableID: "profile")]
        }
        let proposal = BatchEngine.propose(inputs: [first, second].map { input($0) })
        XCTAssertEqual(proposal.batches.count, 2)
        let batch = try XCTUnwrap(proposal.batches.first { $0.members.first?.key.issueID == first.id })
        XCTAssertEqual(batch.relatedNotes.map(\.kind), [.sharedTag])
        XCTAssertEqual(batch.relatedNotes.first?.issueID, second.id)
    }

    func testSharedEventIDsExplainButDoNotMerge() throws {
        let shared = UUID()
        let first = spec(1) {
            $0.events = [ExportFixture.event(id: shared)]
            $0.screens = [ExportFixture.screen(name: "Home", stableID: "home")]
        }
        let second = spec(2) {
            $0.events = [ExportFixture.event(id: shared)]
            $0.screens = [ExportFixture.screen(name: "Profile", stableID: "profile")]
        }
        let proposal = BatchEngine.propose(inputs: [first, second].map { input($0) })
        XCTAssertEqual(proposal.batches.count, 2)
        let batch = try XCTUnwrap(proposal.batches.first { $0.members.first?.key.issueID == first.id })
        XCTAssertEqual(batch.relatedNotes.map(\.kind), [.sharedEventID])
    }

    func testTagsDoNotChainTransitively() throws {
        let a = spec(1) { $0.tags = ["x"]; $0.screens = [ExportFixture.screen(name: "A", stableID: "a")] }
        let b = spec(2) { $0.tags = ["x", "y"]; $0.screens = [ExportFixture.screen(name: "B", stableID: "b")] }
        let c = spec(3) { $0.tags = ["y"]; $0.screens = [ExportFixture.screen(name: "C", stableID: "c")] }
        let proposal = BatchEngine.propose(inputs: [a, b, c].map { input($0) })
        XCTAssertEqual(proposal.batches.count, 3)
        let batchA = try XCTUnwrap(proposal.batches.first { $0.members.first?.key.issueID == a.id })
        XCTAssertEqual(Set(batchA.relatedNotes.map(\.issueID)), [b.id], "no note reaches C through B")
    }

    // MARK: - Ordering and cap

    func testIssuesSortByCaptureTimestampThenUUID() throws {
        let shared = Date(timeIntervalSinceReferenceDate: 800_000)
        let later = spec(2) {
            $0.id = UUID(uuidString: "FFFFFFFF-0000-4000-8000-000000000000")!
            $0.capturedAt = shared
            $0.screens = [ExportFixture.screen(name: "Profile", stableID: "profile")]
        }
        let earlier = spec(1) {
            $0.id = UUID(uuidString: "00000001-0000-4000-8000-000000000000")!
            $0.capturedAt = shared
            $0.screens = [ExportFixture.screen(name: "Profile", stableID: "profile")]
        }
        let proposal = BatchEngine.propose(inputs: [later, earlier].map { input($0) })
        XCTAssertEqual(proposal.batches.first?.members.map(\.key.issueID), [earlier.id, later.id])
    }

    func testLargeGroupSplitsAtTheConfiguredCap() throws {
        let specs = (1...12).map { index in
            spec(index) { $0.screens = [ExportFixture.screen(name: "Profile", stableID: "profile")] }
        }
        let proposal = BatchEngine.propose(inputs: specs.map { input($0) })
        XCTAssertEqual(proposal.batches.map(\.members.count), [5, 5, 2])
        XCTAssertTrue(proposal.batches[0].reasons.contains { $0.code == .capSplit })
        let ordered = proposal.batches.flatMap { $0.members.map(\.key.issueID) }
        XCTAssertEqual(ordered, specs.map(\.id), "split follows capture order")
    }

    func testCapIsConfigurable() throws {
        let specs = (1...6).map { index in
            spec(index) { $0.screens = [ExportFixture.screen(name: "Profile", stableID: "profile")] }
        }
        let proposal = BatchEngine.propose(inputs: specs.map { input($0) },
                                           preferences: .init(maximumIssuesPerRequest: 2))
        XCTAssertEqual(proposal.batches.map(\.members.count), [2, 2, 2])
    }

    // MARK: - Manual decisions

    func testManualMergeOverridesTheRules() throws {
        let first = spec(1) { $0.screens = [ExportFixture.screen(name: "Home", stableID: "home")] }
        let second = spec(2) { $0.screens = [ExportFixture.screen(name: "Profile", stableID: "profile")] }
        let inputs = [first, second].map { input($0) }
        var overrides = BatchOverrides()
        for entry in inputs {
            overrides.assign(key: entry.key, revisionID: entry.revisionID, groupID: "Checkout work")
        }
        let proposal = BatchEngine.propose(inputs: inputs, overrides: overrides)
        XCTAssertEqual(proposal.batches.count, 1)
        let batch = try XCTUnwrap(proposal.batches.first)
        XCTAssertEqual(batch.origin, .manual)
        XCTAssertEqual(batch.members.count, 2)
        XCTAssertTrue(batch.reasons.contains { $0.code == .manualAssignment })
    }

    func testManualSplitRemovesAnIssueFromItsRuleGroup() throws {
        let specs = (1...3).map { index in
            spec(index) { $0.screens = [ExportFixture.screen(name: "Profile", stableID: "profile")] }
        }
        let inputs = specs.map { input($0) }
        var overrides = BatchOverrides()
        overrides.assign(key: inputs[0].key, revisionID: inputs[0].revisionID, groupID: "Handle alone")
        let proposal = BatchEngine.propose(inputs: inputs, overrides: overrides)
        XCTAssertEqual(proposal.batches.count, 2)
        XCTAssertEqual(proposal.batches[0].origin, .manual)
        XCTAssertEqual(proposal.batches[0].members.map(\.key.issueID), [specs[0].id])
        XCTAssertEqual(proposal.batches[1].members.count, 2)
    }

    func testManualDecisionAgainstAnOlderRevisionIsReportedAsStale() throws {
        let target = spec(1)
        let current = input(target, revision: "new")
        var overrides = BatchOverrides()
        overrides.assign(key: current.key, revisionID: "old-" + target.id.uuidString, groupID: "Group")
        let proposal = BatchEngine.propose(inputs: [current], overrides: overrides)
        XCTAssertEqual(proposal.batches.count, 1)
        XCTAssertEqual(proposal.batches[0].origin, .rule, "the stale decision does not apply")
        let stale = try XCTUnwrap(proposal.staleAssignments.first)
        XCTAssertEqual(stale.code, .staleManualAssignment)
        XCTAssertTrue(stale.detail.contains("no longer the current revision"))
    }

    func testManualGroupSpanningProjectsIsNotApplied() throws {
        let alpha = spec(1) { $0.projectID = "alpha" }
        let beta = spec(2) { $0.projectID = "beta" }
        let inputs = [alpha, beta].map { input($0) }
        var overrides = BatchOverrides()
        for entry in inputs { overrides.assign(key: entry.key, revisionID: entry.revisionID, groupID: "Mixed") }
        let proposal = BatchEngine.propose(inputs: inputs, overrides: overrides)
        XCTAssertTrue(proposal.batches.allSatisfy { $0.origin == .rule })
        XCTAssertTrue(proposal.staleAssignments.contains { $0.detail.contains("never mixed") })
    }

    func testManualGroupIsNotSplitButIsFlaggedAboveTheCap() throws {
        let specs = (1...7).map { spec($0) }
        let inputs = specs.map { input($0) }
        var overrides = BatchOverrides()
        for entry in inputs { overrides.assign(key: entry.key, revisionID: entry.revisionID, groupID: "Big") }
        let proposal = BatchEngine.propose(inputs: inputs, overrides: overrides)
        XCTAssertEqual(proposal.batches.count, 1)
        XCTAssertEqual(proposal.batches[0].members.count, 7)
        XCTAssertTrue(proposal.batches[0].reasons.contains { $0.code == .capSplit })
    }
}
