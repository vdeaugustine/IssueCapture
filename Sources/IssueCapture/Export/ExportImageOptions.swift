import UIKit

/// Image representations available in an issue export.
///
/// Defined in `IssueCaptureSchema` so companion readers share the exact keys.
typealias ExportImageKind = IssueExportImageKind

/// Compression changes export copies only; original evidence remains in storage.
enum ExportImageQuality: String, CaseIterable, Codable, Sendable {
    case original, detailed, balanced, small

    static let defaultQuality: Self = .small

    var maximumPixelDimension: CGFloat? {
        switch self {
        case .original: return nil
        case .detailed: return 2400
        case .balanced: return 1600
        case .small: return 1200
        }
    }

    var title: String {
        switch self {
        case .original: return "Full detail · PNG"
        case .detailed: return "Light · JPEG 90%"
        case .balanced: return "Balanced · JPEG 65%"
        case .small: return "Compact (default) · JPEG 35%"
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
        qualities[ExportImageKey(reportID: report.id, kind: kind)] ?? .defaultQuality
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
        guard let image = UIImage(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let resized = resized(image, quality: quality)
        guard let compressed = resized.jpegData(compressionQuality: quality.quality) else {
            throw CocoaError(.fileWriteUnknown)
        }
        // Keep the smaller encoding at the selected pixel dimensions.
        let lossless = resized.pngData() ?? data
        return compressed.count < lossless.count ? (compressed, "jpg") : (lossless, "png")
    }
    @MainActor static func resized(_ image: UIImage, quality: ExportImageQuality) -> UIImage {
        guard let maximum = quality.maximumPixelDimension else { return image }
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let scale = min(1, maximum / max(pixelWidth, pixelHeight))
        let size = CGSize(width: pixelWidth * scale, height: pixelHeight * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
