import Foundation
import IssueCaptureSchema

/// Preferences that shape proposals and attachments.
public struct CompanionPreferences: Codable, Sendable, Hashable {
    /// Rule engine inputs.
    public var batching: BatchingPreferences
    /// Attachment policy inputs.
    public var attachments: AttachmentOptions
    /// Security-scoped bookmark for the user-selected import folder.
    ///
    /// Watching is opt-in and the folder is chosen through a system picker.
    /// The companion never claims ZIP file associations.
    public var watchedFolderBookmark: Data?
    /// Whether watching is currently enabled.
    public var isWatchingEnabled: Bool

    /// Creates preferences.
    public init(batching: BatchingPreferences = .standard,
                attachments: AttachmentOptions = .standard,
                watchedFolderBookmark: Data? = nil,
                isWatchingEnabled: Bool = false) {
        self.batching = batching
        self.attachments = attachments
        self.watchedFolderBookmark = watchedFolderBookmark
        self.isWatchingEnabled = isWatchingEnabled
    }
}

/// Everything the companion remembers between launches, apart from evidence.
public struct CompanionState: Codable, Sendable {
    /// User preferences.
    public var preferences: CompanionPreferences
    /// Persistent manual batching decisions.
    public var overrides: BatchOverrides
    /// Local issue workflow states, keyed by project and UUID.
    public var issueStates: [String: IssueLocalState]
    /// Local request workflow states.
    public var requestStates: [String: RequestLocalState]

    /// Creates an empty state.
    public init(preferences: CompanionPreferences = .init(), overrides: BatchOverrides = .init(),
                issueStates: [String: IssueLocalState] = [:],
                requestStates: [String: RequestLocalState] = [:]) {
        self.preferences = preferences
        self.overrides = overrides
        self.issueStates = issueStates
        self.requestStates = requestStates
    }

    /// Storage key for one issue.
    public static func key(_ key: IssueKey) -> String { "\(key.projectID)|\(key.issueID.uuidString)" }

    /// Local state for an issue; issues default to the inbox.
    public func state(for key: IssueKey) -> IssueLocalState {
        issueStates[Self.key(key)] ?? .inbox
    }

    /// Records a local state for an issue.
    ///
    /// These states describe local bookkeeping only. Nothing here asserts that
    /// a transport delivered anything.
    public mutating func setState(_ state: IssueLocalState, for key: IssueKey) {
        issueStates[Self.key(key)] = state
    }

    /// Local state for a prepared request.
    public func state(for requestID: UUID) -> RequestLocalState {
        requestStates[requestID.uuidString] ?? .prepared
    }

    /// Records a local state for a prepared request.
    public mutating func setState(_ state: RequestLocalState, for requestID: UUID) {
        requestStates[requestID.uuidString] = state
    }
}

/// Reads and writes ``CompanionState`` next to the evidence store.
public final class CompanionStateStore {
    private let url: URL

    /// Creates a state store inside `root`.
    public init(root: URL) {
        url = root.appendingPathComponent("state.json")
    }

    /// Loads persisted state, returning defaults when nothing is stored yet.
    public func load() -> CompanionState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(CompanionState.self, from: data) else {
            return CompanionState()
        }
        return state
    }

    /// Persists state atomically.
    public func save(_ state: CompanionState) throws {
        let data = try IssueExportSchema.encoder().encode(state)
        try data.write(to: url, options: .atomic)
    }
}
