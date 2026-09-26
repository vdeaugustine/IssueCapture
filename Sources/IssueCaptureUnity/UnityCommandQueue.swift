import Foundation

/// Caps pending background commands separately from the recorder's retained-event budget.
final class UnityCommandQueue: @unchecked Sendable {
    static let shared = UnityCommandQueue()
    private let lock = NSLock()
    private var pending = 0

    func enqueue(_ command: UnityCommand) {
        lock.lock()
        guard pending < 128 else { lock.unlock(); return }
        pending += 1
        lock.unlock()
        DispatchQueue.main.async { [self] in
            UnityRuntime.shared.apply(command)
            lock.lock()
            pending -= 1
            lock.unlock()
        }
    }
}
