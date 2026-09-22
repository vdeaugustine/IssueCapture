import UIKit
import UniformTypeIdentifiers

/// Standalone handoffs retain the full serialized report alongside readable evidence.
enum IssueHandoff {
    static func text(_ reports: [IssueReport]) throws -> String {
        try ([IssueMarkdown.agentPrompt] + reports.map { report in
            let json = String(decoding: try ReportStore.encoder().encode(report), as: UTF8.self)
            return IssueMarkdown.render(report, images: [:])
                + "\nImages are included in PDF/ZIP exports; clipboard text contains metadata only.\n"
                + "\n## Complete report metadata (JSON)\n\n```json\n\(json)\n```\n"
        }).joined(separator: "\n\n---\n\n")
    }

    @MainActor static func copyText(_ reports: [IssueReport]) async throws {
        UIPasteboard.general.string = try text(reports)
        try await ReportStore.shared.markExportPrepared(reports, at: Date())
    }

    @MainActor static func copyPDF(_ url: URL) throws {
        UIPasteboard.general.setItems([[UTType.pdf.identifier: try Data(contentsOf: url)]])
    }
}
