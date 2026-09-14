import Foundation

/// Watches a user-selected folder for finished export drops.
///
/// A file is only offered for import once its size and modification date have
/// stopped changing, so a copy still in flight is never read as a truncated
/// archive. The watcher never moves or deletes source files.
public final class FolderWatcher {
    /// How long a candidate must stay unchanged before it is considered settled.
    public struct Settling: Sendable {
        /// Interval between stability checks.
        public var interval: TimeInterval
        /// Consecutive unchanged checks required.
        public var requiredStableChecks: Int

        /// Creates settling parameters.
        public init(interval: TimeInterval = 1.0, requiredStableChecks: Int = 2) {
            self.interval = interval
            self.requiredStableChecks = requiredStableChecks
        }

        /// Documented defaults.
        public static let standard = Settling()
    }

    private struct Observation {
        var size: Int
        var modified: Date
        var stableChecks: Int
    }

    private let folder: URL
    private let settling: Settling
    private let queue = DispatchQueue(label: "com.vinware.issuecapture.companion.watch")
    private let fileManager = FileManager.default
    private var observations: [String: Observation] = [:]
    private var handled = Set<String>()
    private var timer: DispatchSourceTimer?
    private let onSettled: (URL) -> Void

    /// Creates a watcher for `folder`.
    ///
    /// - Parameter onSettled: called on a background queue with each settled
    ///   candidate. The caller decides whether the file is actually an export.
    public init(folder: URL, settling: Settling = .standard, onSettled: @escaping (URL) -> Void) {
        self.folder = folder
        self.settling = settling
        self.onSettled = onSettled
    }

    deinit { timer?.cancel() }

    /// Starts watching. Files already present when watching begins are treated
    /// as existing content and are not imported automatically.
    /// The snapshot of existing files is taken before this call returns, so a
    /// file dropped immediately afterwards is still treated as new.
    public func start(importingExisting: Bool = false) {
        queue.sync {
            if !importingExisting { self.handled.formUnion(self.currentCandidates().map(\.path)) }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + self.settling.interval, repeating: self.settling.interval)
            timer.setEventHandler { [weak self] in self?.poll() }
            self.timer?.cancel()
            self.timer = timer
            timer.resume()
        }
    }

    /// Stops watching.
    public func stop() {
        queue.async {
            self.timer?.cancel()
            self.timer = nil
        }
    }

    /// Forgets a path so a later drop with the same name is offered again.
    public func forget(_ url: URL) {
        queue.async {
            self.handled.remove(url.path)
            self.observations[url.path] = nil
        }
    }

    private func currentCandidates() -> [URL] {
        let contents = (try? fileManager.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])) ?? []
        return contents.filter { $0.pathExtension.lowercased() == "zip" }.sorted { $0.path < $1.path }
    }

    private func poll() {
        let candidates = currentCandidates()
        let paths = Set(candidates.map(\.path))
        observations = observations.filter { paths.contains($0.key) }
        handled = handled.intersection(paths)
        for url in candidates where !handled.contains(url.path) {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize, let modified = values.contentModificationDate else { continue }
            if var observation = observations[url.path], observation.size == size,
               observation.modified == modified {
                observation.stableChecks += 1
                observations[url.path] = observation
                if observation.stableChecks >= settling.requiredStableChecks {
                    handled.insert(url.path)
                    onSettled(url)
                }
            } else {
                observations[url.path] = Observation(size: size, modified: modified, stableChecks: 1)
            }
        }
    }
}
