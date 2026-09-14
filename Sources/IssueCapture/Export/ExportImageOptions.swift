import UIKit

/// Image representations available in an issue export.
///
/// Defined in `IssueCaptureSchema` so companion readers share the exact keys.
typealias ExportImageKind = IssueExportImageKind

/// Compression changes export copies only; original evidence remains in storage.
enum ExportImageQuality: String, CaseIterable, Codable, Sendable {
    case original, detailed, balanced, small

    var title: String {
        switch self {
        case .original: return "Full detail · PNG"
        case .detailed: return "Light · JPEG 90%"
        case .balanced: return "Balanced · JPEG 65%"
        case .small: return "Small · JPEG 35%"
        }
    }

    var quality: CGFloat {
        switch self {
        case .original: return 1
        case .detailed: return 0.9
        case .balanced: return 0.65
        case .small: return 0.35
        }
    }
}

struct ExportImageKey: Hashable, Sendable {
    let reportID: UUID
    let kind: ExportImageKind
}

struct ExportImageOptions: Sendable {
    var includeCards = true
    var qualities: [ExportImageKey: ExportImageQuality] = [:]

    func quality(for report: IssueReport, kind: ExportImageKind) -> ExportImageQuality {
        qualities[ExportImageKey(reportID: report.id, kind: kind)] ?? .original
    }

    func kinds(for report: IssueReport) -> [ExportImageKind] {
        var kinds: [ExportImageKind] = []
        if report.hasScreenshot { kinds.append(.screenshot) }
        if report.hasAttachment { kinds.append(.attachment) }
        if !report.annotations.isEmpty && (report.hasScreenshot || report.hasAttachment) { kinds.append(.annotation) }
        if includeCards { kinds.append(.card) }
        return kinds
    }
}

enum ExportImageEncoding {
    @MainActor static func encode(_ data: Data, quality: ExportImageQuality) throws -> (data: Data, extensionName: String) {
        guard quality != .original else { return (data, "png") }
        guard let image = UIImage(data: data), let compressed = image.jpegData(compressionQuality: quality.quality) else {
            throw CocoaError(.fileWriteUnknown)
        }
        // Keep lossless bytes when JPEG would increase file size.
        return compressed.count < data.count ? (compressed, "jpg") : (data, "png")
    }
}
