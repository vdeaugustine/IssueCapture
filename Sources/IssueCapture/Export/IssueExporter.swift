import UIKit

actor IssueExporter {
    static let shared = IssueExporter()

    func export(_ reports: [IssueReport], includeCards: Bool) async throws -> URL {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("IssueCapture-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let archive = root.appendingPathExtension("zip")
        defer { try? manager.removeItem(at: root) }
        do {
            for report in reports { try await write(report, root: root, includeCards: includeCards) }
            let date = Date()
            let manifest = Manifest(schemaVersion: 1, exportedAt: date,
                issues: reports.map { .init(id: $0.id, report: "issues/\($0.id.uuidString)/issue.json") })
            try ReportStore.encoder().encode(manifest).write(to: root.appendingPathComponent("manifest.json"))
            let links = reports.map { "- [\($0.displayID)](issues/\($0.id.uuidString)/issue.md)" }.joined(separator: "\n")
            try ("# IssueCapture export\n\n\(IssueMarkdown.agentPrompt)\n\n\(links)\n").write(
                to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
            try StoredZIPWriter.archive(directory: root, destination: archive)
            try await ReportStore.shared.markExportPrepared(reports, at: date)
            return archive
        } catch {
            try? manager.removeItem(at: archive)
            throw error
        }
    }

    private func write(_ report: IssueReport, root: URL, includeCards: Bool) async throws {
        let folder = root.appendingPathComponent("issues").appendingPathComponent(report.id.uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let original = try await ReportStore.shared.image(report)
        let attachment = try await ReportStore.shared.image(report, attachment: true)
        try original?.write(to: folder.appendingPathComponent("screenshot-original.png"))
        try attachment?.write(to: folder.appendingPathComponent("attachment.png"))
        let derivatives = try await render(report, imageData: original ?? attachment, includeCard: includeCards)
        try derivatives.annotation?.write(to: folder.appendingPathComponent("screenshot-annotated.png"))
        try derivatives.card?.write(to: folder.appendingPathComponent("issue-card.png"))
        try ReportStore.encoder().encode(report).write(to: folder.appendingPathComponent("issue.json"))
        try IssueMarkdown.render(report, hasCard: includeCards).write(to: folder.appendingPathComponent("issue.md"),
                                                                     atomically: true, encoding: .utf8)
    }

    @MainActor private func render(_ report: IssueReport, imageData: Data?, includeCard: Bool) throws -> (annotation: Data?, card: Data?) {
        let image = imageData.flatMap(UIImage.init(data:))
        let annotated = image.map { AnnotationDrawing.render($0, annotations: report.annotations) }
        let annotationData = report.annotations.isEmpty ? nil : annotated?.pngData()
        let card = try includeCard ? IssueCardRenderer.render(report: report, image: annotated) : nil
        return (annotationData, card)
    }

    private struct Manifest: Codable {
        let schemaVersion: Int
        let exportedAt: Date
        let issues: [Item]
        struct Item: Codable { let id: UUID; let report: String }
    }
}
