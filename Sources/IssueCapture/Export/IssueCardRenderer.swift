import UIKit

@MainActor
enum IssueCardRenderer {
    static func render(report: IssueReport, image: UIImage?) throws -> Data {
        let width: CGFloat = 900
        let inset: CGFloat = 36
        let title = "\(report.displayID)\n\(report.screens.last?.name ?? "Screen unavailable")"
        let body = "\(report.description)\n\nExpected: \(report.expectedBehavior.isEmpty ? "Not supplied" : report.expectedBehavior)\n\nSteps: \(report.reproductionNotes.isEmpty ? "Not supplied" : report.reproductionNotes)"
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 28), .foregroundColor: UIColor.black]
        let bodyAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 23), .foregroundColor: UIColor.darkGray]
        let textWidth = width - inset * 2
        let titleHeight = height(title, width: textWidth, attributes: titleAttributes)
        let bodyHeight = height(body, width: textWidth, attributes: bodyAttributes)
        let imageHeight = image.map { textWidth * $0.size.height / max(1, $0.size.width) } ?? 0
        let totalHeight = inset * 4 + titleHeight + bodyHeight + imageHeight
        guard totalHeight < 24_000 else {
            throw NSError(domain: "IssueCapture", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Description is too long for one image card. Turn off image cards and export Markdown instead; text will not be truncated."])
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: width, height: totalHeight), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: totalHeight))
            (title as NSString).draw(in: CGRect(x: inset, y: inset, width: textWidth, height: titleHeight), withAttributes: titleAttributes)
            (body as NSString).draw(in: CGRect(x: inset, y: inset * 2 + titleHeight, width: textWidth, height: bodyHeight), withAttributes: bodyAttributes)
            image?.draw(in: CGRect(x: inset, y: inset * 3 + titleHeight + bodyHeight, width: textWidth, height: imageHeight))
        }
        guard let data = rendered.pngData() else { throw CocoaError(.fileWriteUnknown) }
        return data
    }

    private static func height(_ text: String, width: CGFloat, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        ceil((text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil).height) + 4
    }
}
