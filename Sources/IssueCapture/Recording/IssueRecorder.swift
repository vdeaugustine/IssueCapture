import Foundation

final class IssueRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let sessionID = UUID()
    private let configuration: IssueCaptureConfiguration
    private var entries: [(event: IssueEvent, bytes: Int)] = []
    private var byteCount = 0
    private var sequence: UInt64 = 0
    private var suspended = false
    private var invalidated = false
    private var sceneID = "pending"

    func setSceneID(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        sceneID = value
    }

    init(configuration: IssueCaptureConfiguration) { self.configuration = configuration }

    func setSuspended(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        suspended = value
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        invalidated = true
    }

    func record(_ action: IssueAction, screen: IssueScreenContext?, file: String, line: UInt) {
        lock.lock()
        defer { lock.unlock() }
        guard !suspended, !invalidated else { return }
        sequence += 1
        var metadata: [String: String] = [:]
        for (key, value) in action.metadata.sorted(by: { $0.key < $1.key }).prefix(16) {
            metadata[String(key.prefix(100))] = String(value.prefix(512))
        }
        let event = IssueEvent(id: UUID(), sessionID: sessionID, sceneID: sceneID,
            timestamp: Date(), sequence: sequence, category: String(action.category.prefix(80)),
            name: String(action.name.prefix(200)), metadata: metadata, screen: screen,
            file: file, line: line)
        let bytes = (try? JSONEncoder().encode(event).count) ?? 0
        guard bytes <= configuration.eventByteLimit else { return }
        entries.append((event, bytes))
        byteCount += bytes
        while entries.count > configuration.eventLimit || byteCount > configuration.eventByteLimit {
            byteCount -= entries.removeFirst().bytes
        }
    }

    func snapshot() -> [IssueEvent] {
        lock.lock()
        defer { lock.unlock() }
        return entries.map(\.event)
    }
}

/// A lightweight scoped event sink; safe to retain for asynchronous outcomes.
public struct IssueReporter: Sendable {
    let recorder: IssueRecorder?
    let screen: IssueScreenContext?

    /// Records an event without disk or network I/O. Disabled reporters do nothing.
    public func record(_ action: IssueAction, file: String = #fileID, line: UInt = #line) {
        recorder?.record(action, screen: screen, file: file, line: line)
    }
}
