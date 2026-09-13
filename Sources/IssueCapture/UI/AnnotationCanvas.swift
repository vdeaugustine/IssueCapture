import SwiftUI

struct AnnotationCanvas: View {
    let image: UIImage
    @Binding var annotations: [IssueAnnotation]
    let tool: IssueAnnotation.Kind
    @State private var current: IssueAnnotation?

    var body: some View {
        Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    Canvas { context, size in
                        for annotation in annotations + [current].compactMap({ $0 }) {
                            context.stroke(Path(AnnotationDrawing.path(annotation, size: size)),
                                           with: .color(.red), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let point = IssuePoint(x: min(1, max(0, value.location.x / max(1, geometry.size.width))),
                                                   y: min(1, max(0, value.location.y / max(1, geometry.size.height))))
                            if current == nil { current = IssueAnnotation(kind: tool, points: [point]) }
                            if tool != .pen && (current?.points.count ?? 0) > 1 { current?.points.removeLast() }
                            if (current?.points.count ?? 0) < 4_000 { current?.points.append(point) }
                        }
                        .onEnded { _ in
                            if let current, annotations.count < 200 { annotations.append(current) }
                            current = nil
                        })
                }
            }
            .accessibilityLabel("Screenshot annotation canvas")
            .accessibilityHint("Draw with the selected tool. Annotation is optional.")
    }
}

@MainActor
enum AnnotationDrawing {
    static func path(_ annotation: IssueAnnotation, size: CGSize) -> CGPath {
        let path = CGMutablePath()
        let points = annotation.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        guard let first = points.first, let last = points.last else { return path }
        switch annotation.kind {
        case .rectangle:
            path.addRect(CGRect(x: min(first.x, last.x), y: min(first.y, last.y),
                                width: abs(last.x - first.x), height: abs(last.y - first.y)))
        case .pen:
            path.addLines(between: points)
        case .arrow:
            path.move(to: first)
            path.addLine(to: last)
            let angle = atan2(last.y - first.y, last.x - first.x)
            let length = min(20, hypot(last.x - first.x, last.y - first.y) * 0.4)
            for offset in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                path.move(to: last)
                path.addLine(to: CGPoint(x: last.x - length * cos(angle + offset),
                                        y: last.y - length * sin(angle + offset)))
            }
        }
        return path
    }

    static func render(_ image: UIImage, annotations: [IssueAnnotation]) -> UIImage {
        UIGraphicsImageRenderer(size: image.size).image { renderer in
            image.draw(at: .zero)
            renderer.cgContext.setStrokeColor(UIColor.systemRed.cgColor)
            renderer.cgContext.setLineWidth(max(3, image.size.width / 150))
            renderer.cgContext.setLineCap(.round)
            for annotation in annotations {
                renderer.cgContext.addPath(path(annotation, size: image.size))
                renderer.cgContext.strokePath()
            }
        }
    }
}
