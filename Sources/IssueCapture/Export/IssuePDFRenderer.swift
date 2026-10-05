import CoreText
import ImageIO
import UIKit

@MainActor
enum IssuePDFRenderer {
    struct Evidence {
        let report: IssueReport
        let screenshot: Data?
        let attachment: Data?
    }

    private static let page = CGRect(x: 0, y: 0, width: 612, height: 792)
    private static let content = CGRect(x: 36, y: 48, width: 540, height: 696)

    static func write(_ evidence: [Evidence], to url: URL, quality: ExportImageQuality) throws {
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        // Encode before rendering so serialization failures never produce partial handoffs.
        let text = try evidence.map { try IssueHandoff.reportText($0.report) }
        let images = try evidence.map { item -> [(String, CGImage)] in
            var pages: [(String, CGImage)] = []
            if let data = item.screenshot {
                pages.append(("\(item.report.displayID) · Captured screenshot", try preparedImage(data, quality: quality)))
            }
            if let data = item.attachment {
                pages.append(("\(item.report.displayID) · Attached image", try preparedImage(data, quality: quality)))
            }
            if !item.report.annotations.isEmpty,
               let data = item.screenshot ?? item.attachment, let image = UIImage(data: data) {
                let resized = ExportImageEncoding.resized(image, quality: quality)
                let annotated = AnnotationDrawing.render(resized, annotations: item.report.annotations)
                guard let bytes = annotated.pngData() else { throw CocoaError(.fileWriteUnknown) }
                pages.append(("\(item.report.displayID) · Annotated evidence", try preparedImage(bytes, quality: quality)))
            }
            return pages
        }
        try renderer.writePDF(to: url) { context in
            let introduction = """
                IssueCapture issues

                This PDF contains \(evidence.count) saved issue \(evidence.count == 1 ? "report" : "reports") and their available image evidence. Please investigate each issue in the host repository, implement the appropriate fixes or requested features, and report the outcome for each issue ID.

                \(IssueMarkdown.agentPrompt)
                """
            drawText(introduction, context: context)
            for (index, item) in evidence.enumerated() {
                drawText(text[index], context: context)
                for (title, image) in images[index] {
                    drawImage(image, title: title, context: context)
                }
            }
        }
    }

    private static func drawText(_ text: String, context: UIGraphicsPDFRendererContext) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        paragraph.paragraphSpacing = 4
        let attributed = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.black,
            .paragraphStyle: paragraph
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var offset = 0
        while offset < attributed.length {
            context.beginPage()
            let graphics = context.cgContext
            graphics.saveGState()
            graphics.textMatrix = .identity
            graphics.translateBy(x: 0, y: page.height)
            graphics.scaleBy(x: 1, y: -1)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0),
                                                 CGPath(rect: content, transform: nil), nil)
            CTFrameDraw(frame, graphics)
            graphics.restoreGState()
            let visible = CTFrameGetVisibleStringRange(frame)
            // Fixed page bounds and a 10-point font guarantee at least one character fits.
            precondition(visible.length > 0, "PDF text pagination made no progress")
            offset += visible.length
        }
    }

    private static func preparedImage(_ data: Data, quality: ExportImageQuality) throws -> CGImage {
        let encoded = try ExportImageEncoding.encode(data, quality: quality)
        guard let source = CGImageSourceCreateWithData(encoded.data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return image
    }

    private static func drawImage(_ image: CGImage, title: String, context: UIGraphicsPDFRendererContext) {
        context.beginPage()
        (title as NSString).draw(in: CGRect(x: 36, y: 24, width: 540, height: 22),
                                withAttributes: [.font: UIFont.boldSystemFont(ofSize: 12),
                                                 .foregroundColor: UIColor.black])
        let scale = min(content.width / CGFloat(image.width), content.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let rectangle = CGRect(x: content.midX - size.width / 2, y: content.midY - size.height / 2,
                               width: size.width, height: size.height)
        let graphics = context.cgContext
        graphics.saveGState()
        graphics.translateBy(x: 0, y: page.height)
        graphics.scaleBy(x: 1, y: -1)
        graphics.draw(image, in: CGRect(x: rectangle.minX, y: page.height - rectangle.maxY,
                                       width: rectangle.width, height: rectangle.height))
        graphics.restoreGState()
    }
}
