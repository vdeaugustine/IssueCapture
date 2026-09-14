import XCTest
@testable import CompanionCore

/// Acceptance scenarios for the optional watched import folder.
final class FolderWatchTests: XCTestCase {
    private var workspace: URL!

    override func setUpWithError() throws {
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("companion-watch-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workspace)
    }

    func testAFileStillBeingCopiedIsNotOfferedUntilItSettles() throws {
        let settled = expectation(description: "settled")
        let observed = OSAllocatedUnfairLockBox<[URL]>([])
        let watcher = FolderWatcher(folder: workspace,
                                    settling: .init(interval: 0.1, requiredStableChecks: 3)) { url in
            observed.mutate { $0.append(url) }
            settled.fulfill()
        }
        watcher.start()

        let target = workspace.appendingPathComponent("export.zip")
        FileManager.default.createFile(atPath: target.path, contents: Data())
        let handle = try FileHandle(forWritingTo: target)

        // Grow the file across several polling intervals, as an in-flight copy does.
        for chunk in 0..<5 {
            try handle.write(contentsOf: Data(repeating: UInt8(chunk), count: 4096))
            try handle.synchronize()
            XCTAssertTrue(observed.value.isEmpty, "an unfinished copy must never be imported")
            Thread.sleep(forTimeInterval: 0.12)
        }
        try handle.close()

        wait(for: [settled], timeout: 5)
        watcher.stop()
        XCTAssertEqual(observed.value.map(\.lastPathComponent), ["export.zip"])
        XCTAssertEqual(try Data(contentsOf: target).count, 5 * 4096,
                       "the settled file is the complete copy")
    }

    func testFilesAlreadyPresentAreNotImportedAutomatically() throws {
        let existing = workspace.appendingPathComponent("old.zip")
        try Data("already here".utf8).write(to: existing)
        let observed = OSAllocatedUnfairLockBox<[URL]>([])
        let watcher = FolderWatcher(folder: workspace,
                                    settling: .init(interval: 0.05, requiredStableChecks: 2)) { url in
            observed.mutate { $0.append(url) }
        }
        watcher.start()
        Thread.sleep(forTimeInterval: 0.4)
        watcher.stop()
        XCTAssertTrue(observed.value.isEmpty)
    }

    func testNonArchiveFilesAreIgnored() throws {
        let observed = OSAllocatedUnfairLockBox<[URL]>([])
        let watcher = FolderWatcher(folder: workspace,
                                    settling: .init(interval: 0.05, requiredStableChecks: 2)) { url in
            observed.mutate { $0.append(url) }
        }
        watcher.start()
        try Data("notes".utf8).write(to: workspace.appendingPathComponent("notes.txt"))
        Thread.sleep(forTimeInterval: 0.4)
        watcher.stop()
        XCTAssertTrue(observed.value.isEmpty)
    }
}

/// Minimal thread-safe box so test callbacks can record results from the
/// watcher's background queue.
final class OSAllocatedUnfairLockBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) { storage = value }

    var value: Value {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func mutate(_ body: (inout Value) -> Void) {
        lock.lock(); defer { lock.unlock() }
        body(&storage)
    }
}
