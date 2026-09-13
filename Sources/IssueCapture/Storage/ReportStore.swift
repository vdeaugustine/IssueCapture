import Foundation

actor ReportStore {
    static let shared = ReportStore()
    private let fileManager = FileManager.default

    private var root: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IssueCapture", isDirectory: true)
    }

    func save(_ report: IssueReport, screenshot: Data?, attachment: Data?) throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(report.id.uuidString, isDirectory: true)
        let staging = root.appendingPathComponent(".draft-" + UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        try persistAsset("screenshot-original.png", bytes: screenshot, existing: destination,
                         staging: staging, required: report.hasScreenshot)
        try persistAsset("attachment.png", bytes: attachment, existing: destination,
                         staging: staging, required: report.hasAttachment)
        try Self.encoder().encode(report).write(to: staging.appendingPathComponent("issue.json"), options: .atomic)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: destination)
        }
    }

    private func persistAsset(_ name: String, bytes: Data?, existing: URL,
                              staging: URL, required: Bool) throws {
        guard required else { return }
        let target = staging.appendingPathComponent(name)
        if let bytes { try bytes.write(to: target, options: .atomic) }
        else { try fileManager.copyItem(at: existing.appendingPathComponent(name), to: target) }
    }

    func list(projectID: String) throws -> [IssueReport] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        let folders = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                         options: .skipsHiddenFiles)
        return try folders.map { folder in
            try JSONDecoder().decode(IssueReport.self, from: Data(contentsOf: folder.appendingPathComponent("issue.json")))
        }.filter { $0.projectID == projectID }.sorted { $0.capturedAt > $1.capturedAt }
    }

    func image(_ report: IssueReport, attachment: Bool = false) throws -> Data? {
        guard attachment ? report.hasAttachment : report.hasScreenshot else { return nil }
        return try Data(contentsOf: root.appendingPathComponent(report.id.uuidString)
            .appendingPathComponent(attachment ? "attachment.png" : "screenshot-original.png"))
    }

    func delete(_ id: UUID) throws {
        try fileManager.removeItem(at: root.appendingPathComponent(id.uuidString))
    }

    func markExportPrepared(_ reports: [IssueReport], at date: Date) throws {
        for report in reports {
            let url = root.appendingPathComponent(report.id.uuidString).appendingPathComponent("issue.json")
            var current = try JSONDecoder().decode(IssueReport.self, from: Data(contentsOf: url))
            current.exportPreparedAt.append(date)
            try Self.encoder().encode(current).write(to: url, options: .atomic)
        }
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
