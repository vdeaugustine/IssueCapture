import IssueCapture
import UIKit

@MainActor
final class UnityRuntime {
    static let shared = UnityRuntime()
    private var host: IssueCaptureNativeHost?
    private var sessionID: String?
    private var surfaces: [UUID: (context: IssueScreenContext, active: Bool)] = [:]
    private var visible: Set<UUID> = []

    func initialize(window: UIWindow, command: UnityCommand) -> Bool {
        guard command.operation == "initialize", UUID(uuidString: command.session) != nil else { return false }
        if host != nil { return sessionID == command.session }
        let configuration = IssueCaptureConfiguration(isEnabled: true,
            projectID: String((command.projectID ?? "unity").prefix(200)),
            eventLimit: command.eventLimit ?? 50, eventByteLimit: command.eventByteLimit ?? 262_144,
            sourceRevision: command.sourceRevision.map { String($0.prefix(200)) }, showsCaptureTab: false)
        guard let host = IssueCaptureNativeHost(window: window, configuration: configuration) else { return false }
        self.host = host
        sessionID = command.session
        return true
    }

    func apply(_ command: UnityCommand) {
        guard command.session == sessionID, let host else { return }
        switch command.operation {
        case "shutdown":
            host.shutdown()
            self.host = nil
            sessionID = nil
            surfaces.removeAll()
            visible.removeAll()
        case "register":
            guard let context = command.screen?.context, surfaces.count < 256,
                  surfaces[context.id] == nil else { return }
            if let parent = context.parentID, surfaces[parent] == nil { return }
            surfaces[context.id] = (context, command.active ?? true)
            reconcile()
        case "active":
            guard let id = command.screen?.id, surfaces[id] != nil else { return }
            surfaces[id]?.active = command.active ?? false
            reconcile()
        case "dispose":
            guard let id = command.screen?.id else { return }
            var removed: Set<UUID> = [id]
            while true {
                let children = Set(surfaces.values.filter { surface in
                    surface.context.parentID.map { removed.contains($0) } ?? false
                }.map { $0.context.id })
                let expanded = removed.union(children)
                if expanded == removed { break }
                removed = expanded
            }
            for removedID in removed { surfaces.removeValue(forKey: removedID) }
            reconcile()
        case "record":
            record(command, host: host)
        case "inbox": host.openInbox()
        case "diagnostics": host.openDiagnostics()
        case "cancel": host.cancelFrameCapture()
        default: break
        }
    }

    var isPresenting: Bool { host?.isPresenting ?? false }
    func beginCapture() -> Bool { host?.beginFrameCapture() ?? false }

    func finishCapture(_ image: UIImage?) {
        host?.finishFrameCapture(image: image, status: image == nil
            ? "failed: Unity frame unavailable or exceeded 32 MiB / 16 megapixels; attach an image manually"
            : "Unity end-of-frame image; native/system overlays absent; device fidelity unverified")
    }

    private func record(_ command: UnityCommand, host: IssueCaptureNativeHost) {
        guard let screen = command.screen?.context,
              let category = command.category, ["action", "navigation", "outcome"].contains(category),
              let name = command.name else { return }
        var metadata: [String: String] = [:]
        if let result = command.result, ["success", "failure", "cancelled"].contains(result) {
            metadata["result"] = result
        }
        host.reporter(for: screen).record(.init(category: category, name: name, metadata: metadata),
            file: String((command.file ?? screen.file).prefix(300)), line: command.line ?? screen.line)
    }

    private func isActive(_ id: UUID, visited: Set<UUID> = []) -> Bool {
        guard !visited.contains(id), let surface = surfaces[id], surface.active else { return false }
        guard let parent = surface.context.parentID else { return true }
        return isActive(parent, visited: visited.union([id]))
    }

    private func reconcile() {
        guard let host else { return }
        let next = Set(surfaces.keys.filter { isActive($0) })
        for id in visible.subtracting(next).sorted(by: { $0.uuidString < $1.uuidString }) { host.deactivate(id) }
        // Registration order does not select a winner; multiple active leaves remain ambiguous.
        for id in next.subtracting(visible).sorted(by: { $0.uuidString < $1.uuidString }) {
            if let context = surfaces[id]?.context { host.activate(context) }
        }
        visible = next
    }
}
