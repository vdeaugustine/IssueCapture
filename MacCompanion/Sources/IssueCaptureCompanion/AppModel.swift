import AppKit
import CompanionCore
import Foundation
import IssueCaptureSchema
import Observation

/// Owns the companion's stores and derives everything the UI shows.
@MainActor @Observable
final class AppModel {
    /// A failed import the user can retry or dismiss.
    struct ImportProblem: Identifiable {
        let id = UUID()
        let source: String
        let failure: ImportFailure
        let occurredAt = Date()
    }

    /// Outcome banner for the most recent successful import.
    struct ImportSummary: Identifiable {
        let id = UUID()
        let message: String
    }

    private(set) var store: EvidenceStore
    private(set) var assembler: RequestAssembler
    private var service: ImportService
    private let stateStore: CompanionStateStore
    private var watcher: FolderWatcher?
    private var watchedFolder: URL?

    var state: CompanionState { didSet { persist() } }
    private(set) var batches: [CandidateBatch] = []
    private(set) var staleDecisions: [BatchReason] = []
    private(set) var requests: [PreparedRequestHandle] = []
    private(set) var problems: [ImportProblem] = []
    private(set) var summaries: [ImportSummary] = []
    var selectedBatchID: String?
    var selectedIssueID: IssueKey?
    var selectedRequestID: UUID?
    var isImporting = false

    /// Opens the companion's storage under Application Support.
    init() throws {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
            .appendingPathComponent("IssueCaptureCompanion", isDirectory: true)
        let evidence = try EvidenceStore(root: root)
        store = evidence
        service = ImportService(store: evidence)
        assembler = RequestAssembler(store: evidence)
        let states = CompanionStateStore(root: root)
        stateStore = states
        state = states.load()
        refresh()
        startWatchingIfEnabled()
    }

    // MARK: - Derived data

    /// Newest revision of every issue, in deterministic order.
    var currentRevisions: [IssueRevision] { store.currentRevisions() }

    /// Revisions in the selected batch, in batch order.
    var selectedBatch: CandidateBatch? { batches.first { $0.id == selectedBatchID } }

    /// The revision behind a batch member.
    func revision(for member: BatchMember) -> IssueRevision? { store.revision(id: member.revisionID) }

    /// Every warning attached to the current revisions.
    var warningCount: Int { currentRevisions.reduce(0) { $0 + $1.warnings.count } }

    /// Attachment decisions for one revision under the current preferences.
    func decisions(for revision: IssueRevision) -> [AttachmentDecision] {
        AttachmentPolicy.decisions(for: revision, overrides: state.overrides,
                                   options: state.preferences.attachments)
    }

    /// Recomputes proposals and reloads request folders.
    func refresh() {
        let inputs = store.currentRevisions().map {
            BatchEngine.Input(key: $0.issueKey, revisionID: $0.id, report: $0.report)
        }
        let proposal = BatchEngine.propose(inputs: inputs, overrides: state.overrides,
                                           preferences: state.preferences.batching)
        batches = proposal.batches
        staleDecisions = proposal.staleAssignments
        requests = assembler.storedRequests()
        if selectedBatchID == nil || !batches.contains(where: { $0.id == selectedBatchID }) {
            selectedBatchID = batches.first?.id
        }
    }

    // MARK: - Import

    /// Imports each URL, recording actionable failures instead of throwing away
    /// the batch.
    func importSources(_ urls: [URL]) {
        isImporting = true
        defer { isImporting = false }
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let result = try service.import(contentsOf: url)
                summaries.append(.init(message: describe(result, source: url.lastPathComponent)))
            } catch let failure as ImportFailure {
                problems.append(.init(source: url.lastPathComponent, failure: failure))
            } catch {
                problems.append(.init(source: url.lastPathComponent,
                                      failure: .init(code: .storageFailure,
                                                     detail: error.localizedDescription,
                                                     isRetryable: true)))
            }
        }
        refresh()
    }

    private func describe(_ result: ImportResult, source: String) -> String {
        if result.wasExactRepeat {
            return "\(source): identical archive already imported on "
                + result.provenance.receivedAt.formatted(date: .abbreviated, time: .shortened)
                + ". Nothing changed."
        }
        var parts: [String] = []
        if !result.newRevisions.isEmpty { parts.append("\(result.newRevisions.count) new revision(s)") }
        if !result.unchangedRevisions.isEmpty {
            parts.append("\(result.unchangedRevisions.count) unchanged issue(s), receipt retained")
        }
        let warnings = result.warnings.count
        if warnings > 0 { parts.append("\(warnings) evidence warning(s)") }
        return "\(source): " + (parts.isEmpty ? "no issues declared" : parts.joined(separator: ", "))
    }

    /// Dismisses a recorded failure.
    func dismiss(_ problem: ImportProblem) { problems.removeAll { $0.id == problem.id } }

    /// Dismisses a recorded summary.
    func dismiss(_ summary: ImportSummary) { summaries.removeAll { $0.id == summary.id } }

    /// Retries a failed import from its original path.
    func retry(_ problem: ImportProblem) {
        dismiss(problem)
        importSources([URL(fileURLWithPath: problem.source)])
    }

    // MARK: - Watched folder

    /// Resolved watched folder, if one is configured.
    var watchedFolderURL: URL? { watchedFolder }

    /// Stores a user-selected import folder as a security-scoped bookmark.
    func setWatchedFolder(_ url: URL) {
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope,
                                                includingResourceValuesForKeys: nil, relativeTo: nil)
            state.preferences.watchedFolderBookmark = bookmark
            state.preferences.isWatchingEnabled = true
            startWatchingIfEnabled()
        } catch {
            problems.append(.init(source: url.lastPathComponent,
                                  failure: .init(code: .storageFailure,
                                                 detail: "Could not keep access to this folder: \(error.localizedDescription)")))
        }
    }

    /// Turns folder watching on or off without forgetting the chosen folder.
    func setWatching(_ enabled: Bool) {
        state.preferences.isWatchingEnabled = enabled
        if enabled { startWatchingIfEnabled() } else { stopWatching() }
    }

    /// Forgets the watched folder entirely.
    func clearWatchedFolder() {
        stopWatching()
        state.preferences.watchedFolderBookmark = nil
        state.preferences.isWatchingEnabled = false
    }

    private func startWatchingIfEnabled() {
        stopWatching()
        guard state.preferences.isWatchingEnabled,
              let bookmark = state.preferences.watchedFolderBookmark else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            problems.append(.init(source: "watched folder",
                                 failure: .init(code: .storageFailure,
                                                detail: "Access to the watched folder was lost. Choose it again.")))
            return
        }
        _ = url.startAccessingSecurityScopedResource()
        watchedFolder = url
        let watcher = FolderWatcher(folder: url) { [weak self] settled in
            Task { @MainActor in self?.importSources([settled]) }
        }
        watcher.start()
        self.watcher = watcher
    }

    private func stopWatching() {
        watcher?.stop()
        watcher = nil
        watchedFolder?.stopAccessingSecurityScopedResource()
        watchedFolder = nil
    }

    // MARK: - Manual decisions

    /// Pins an issue revision to a named group.
    func assign(revision: IssueRevision, to groupID: String) {
        state.overrides.assign(key: revision.issueKey, revisionID: revision.id, groupID: groupID)
        refresh()
        selectedBatchID = "manual:" + groupID
    }

    /// Returns an issue revision to the deterministic rules.
    func unassign(revision: IssueRevision) {
        state.overrides.unassign(key: revision.issueKey, revisionID: revision.id)
        refresh()
    }

    /// Includes or excludes one image kind for a revision's attachments.
    func setExcluded(_ excluded: Bool, revision: IssueRevision, kind: IssueExportImageKind) {
        state.overrides.setExcluded(excluded, key: revision.issueKey, revisionID: revision.id, kind: kind)
        refresh()
    }

    /// Instructions the user attached to a batch.
    func instructions(for batch: CandidateBatch) -> String { state.overrides.instructions[batch.id] ?? "" }

    /// Records request instructions for a batch.
    func setInstructions(_ text: String, for batch: CandidateBatch) {
        state.overrides.instructions[batch.id] = text.isEmpty ? nil : text
    }

    // MARK: - Requests

    /// Prepares a request folder for the selected batch.
    func prepare(batch: CandidateBatch) {
        do {
            let handle = try assembler.prepare(batch: batch, overrides: state.overrides,
                                               options: state.preferences.attachments)
            for member in batch.members where state.state(for: member.key) == .inbox {
                state.setState(.prepared, for: member.key)
            }
            refresh()
            selectedRequestID = handle.request.id
        } catch let failure as ImportFailure {
            problems.append(.init(source: batch.title, failure: failure))
        } catch {
            problems.append(.init(source: batch.title,
                                  failure: .init(code: .storageFailure, detail: error.localizedDescription)))
        }
    }

    /// The currently selected prepared request.
    var selectedRequest: PreparedRequestHandle? {
        requests.first { $0.request.id == selectedRequestID } ?? requests.first
    }

    /// Copies the request prompt text to the clipboard.
    func copyPrompt(_ handle: PreparedRequestHandle) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(assembler.promptText(for: handle), forType: .string)
    }

    /// Reveals the request folder in Finder.
    func revealFolder(_ handle: PreparedRequestHandle) {
        NSWorkspace.shared.activateFileViewerSelecting([handle.folder])
    }

    /// Records a local request state. Marking is bookkeeping, not delivery.
    func setState(_ value: RequestLocalState, for handle: PreparedRequestHandle) {
        state.setState(value, for: handle.request.id)
        let issueState: IssueLocalState = value == .resolved ? .resolved : (value == .sent ? .sent : .prepared)
        for issue in handle.request.issues {
            state.setState(issueState, for: IssueKey(projectID: handle.request.projectID,
                                                     issueID: issue.issueID))
        }
    }

    private func persist() {
        try? stateStore.save(state)
    }
}
