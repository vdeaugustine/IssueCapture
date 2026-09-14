import UIKit

actor IssueExporter {
    static let shared = IssueExporter()

    func export(_ reports: [IssueReport], options: ExportImageOptions) async throws -> URL {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("IssueCapture-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let archive = root.appendingPathExtension("zip")
        defer { try? manager.removeItem(at: root) }
        do {
            for report in reports { try await write(report, root: root, options: options) }
            let date = Date()
            let manifest = IssueExportManifest(schemaVersion: IssueExportSchema.manifestVersion, exportedAt: date,
                issues: reports.map { .init(id: $0.id, report: "issues/\($0.id.uuidString)/issue.json") })
            try ReportStore.encoder().encode(manifest).write(to: root.appendingPathComponent("manifest.json"))
            let links = reports.map { "- [\($0.displayID)](issues/\($0.id.uuidString)/issue.md)" }.joined(separator: "\n")
            try ("# IssueCapture export\n\n\(IssueMarkdown.agentPrompt)\n\n\(links)\n\n\(tagIndex(reports))\n").write(
                to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
            try StoredZIPWriter.archive(directory: root, destination: archive)
            try await ReportStore.shared.markExportPrepared(reports, at: date)
            return archive
        } catch {
            try? manager.removeItem(at: archive)
            throw error
        }
    }

    private func write(_ report: IssueReport, root: URL, options: ExportImageOptions) async throws {
        let folder = root.appendingPathComponent("issues").appendingPathComponent(report.id.uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let original = try await ReportStore.shared.image(report)
        let attachment = try await ReportStore.shared.image(report, attachment: true)
        let derivatives = try await render(report, imageData: original ?? attachment, includeCard: options.includeCards)
        let assets: [(ExportImageKind, Data?)] = [(.screenshot, original), (.attachment, attachment),
                                                 (.annotation, derivatives.annotation), (.card, derivatives.card)]
        var filenames: [String: String] = [:]
        for (kind, data) in assets {
            guard let data else { continue }
            let encoded = try await ExportImageEncoding.encode(data, quality: options.quality(for: report, kind: kind))
            let filename = kind.basename + "." + encoded.extensionName
            try encoded.data.write(to: folder.appendingPathComponent(filename))
            filenames[kind.rawValue] = filename
        }
        try ReportStore.encoder().encode(filenames).write(to: folder.appendingPathComponent("images.json"))
        try ReportStore.encoder().encode(report).write(to: folder.appendingPathComponent("issue.json"))
        try IssueMarkdown.render(report, images: filenames).write(to: folder.appendingPathComponent("issue.md"),
                                                                 atomically: true, encoding: .utf8)
    }

    @MainActor private func render(_ report: IssueReport, imageData: Data?, includeCard: Bool) throws -> (annotation: Data?, card: Data?) {
        let image = imageData.flatMap(UIImage.init(data:))
        let annotated = image.map { AnnotationDrawing.render($0, annotations: report.annotations) }
        let annotationData = report.annotations.isEmpty ? nil : annotated?.pngData()
        let card = try includeCard ? IssueCardRenderer.render(report: report, image: annotated) : nil
        return (annotationData, card)
    }

    private func tagIndex(_ reports: [IssueReport]) -> String {
        let tags = Set(reports.flatMap { $0.tags ?? [] }).sorted()
        return tags.map { tag in
            let links = reports.filter { ($0.tags ?? []).contains(tag) }.map {
                "- [\($0.displayID)](issues/\($0.id.uuidString)/issue.md)"
            }.joined(separator: "\n")
            return "## Tag: \(tag)\n\n\(links)"
        }.joined(separator: "\n\n")
    }
}
