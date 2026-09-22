import CoreText
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

    static func write(_ evidence: [Evidence], to url: URL) throws {
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        // Encode before rendering so serialization failures never produce partial handoffs.
        let text = try evidence.map { try IssueHandoff.text([$0.report]) }
        try renderer.writePDF(to: url) { context in
            for (index, item) in evidence.enumerated() {
                drawText(text[index], context: context)
                drawImage(item.screenshot, title: "\(item.report.displayID) · Original screenshot", context: context)
                drawImage(item.attachment, title: "\(item.report.displayID) · Attached image", context: context)
                if !item.report.annotations.isEmpty,
                   let data = item.screenshot ?? item.attachment,
                   let image = UIImage(data: data) {
                    drawImage(AnnotationDrawing.render(image, annotations: item.report.annotations),
                              title: "\(item.report.displayID) · Annotated evidence", context: context)
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

    private static func drawImage(_ data: Data?, title: String, context: UIGraphicsPDFRendererContext) {
        guard let data, let image = UIImage(data: data) else { return }
        drawImage(image, title: title, context: context)
    }

    private static func drawImage(_ image: UIImage, title: String, context: UIGraphicsPDFRendererContext) {
        context.beginPage()
        (title as NSString).draw(in: CGRect(x: 36, y: 24, width: 540, height: 22),
                                withAttributes: [.font: UIFont.boldSystemFont(ofSize: 12),
                                                 .foregroundColor: UIColor.black])
        let scale = min(content.width / image.size.width, content.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(x: content.midX - size.width / 2, y: content.midY - size.height / 2,
                              width: size.width, height: size.height))
    }
}
