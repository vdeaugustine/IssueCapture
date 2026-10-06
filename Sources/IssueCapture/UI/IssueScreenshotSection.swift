import SwiftUI

/// Image attachment controls with a direct path from each preview to annotation.
struct IssueScreenshotSection: View {
    let screenshot: UIImage?
    @Binding var includeScreenshot: Bool
    let attachment: UIImage?
    let annotations: [IssueAnnotation]
    let captureStatus: String
    let onAttach: () -> Void
    let loadingPhoto: Bool
    let onAnnotate: (UIImage) -> Void

    private var preview: UIImage? { (includeScreenshot ? screenshot : nil) ?? attachment }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                heading

                if screenshot != nil {
                    Toggle("Attach captured screenshot", isOn: $includeScreenshot)
                        .font(.subheadline)
                }

                if let preview {
                    previewCard(preview, title: screenshot === preview && includeScreenshot
                                ? "Captured screenshot" : "Attached image")
                } else {
                    emptyCard
                }

                if let attachment, includeScreenshot && screenshot != nil {
                    previewCard(attachment, title: "Additional image")
                }

                HStack {
                    Button(action: onAttach) {
                        Label(attachment == nil ? "Attach image" : "Replace image",
                              systemImage: "photo.badge.plus")
                    }
                    .disabled(loadingPhoto)
                    Spacer()
                    if loadingPhoto { ProgressView() }
                }

                if !captureStatus.isEmpty {
                    DisclosureGroup("Capture details") {
                        Text(captureStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                         in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            Text("Images")
        }
    }

    private var heading: some View {
        HStack(spacing: 12) {
            Image(systemName: preview == nil ? "photo" : "photo.on.rectangle.angled")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(preview == nil ? "Add an image" : "Image evidence")
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        if loadingPhoto { return "Loading image…" }
        guard preview != nil else {
            return screenshot == nil ? "Optional · add a screenshot for context" : "Screenshot is ready to attach"
        }
        return annotations.isEmpty ? "Tap an image to annotate" : "\(annotations.count) annotations · tap to edit"
    }

    private var emptyCard: some View {
        Label("Images help explain the issue", systemImage: "viewfinder")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 112)
            .background(Color(uiColor: .tertiarySystemGroupedBackground),
                         in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func previewCard(_ image: UIImage, title: String) -> some View {
        Button { onAnnotate(image) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title).font(.subheadline.weight(.medium))
                    Spacer()
                    Label("Annotate", systemImage: "pencil.tip.crop.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                GeometryReader { geometry in
                    let scale = min(geometry.size.width / image.size.width,
                                    geometry.size.height / image.size.height)
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: image.size.width * scale, height: image.size.height * scale)
                        .overlay { annotationOverlay(size: CGSize(width: image.size.width * scale,
                                                                  height: image.size.height * scale)) }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: 190)
            }
            .padding(12)
            .background(Color(uiColor: .tertiarySystemGroupedBackground),
                         in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), tap to annotate")
    }

    private func annotationOverlay(size: CGSize) -> some View {
        Canvas { context, _ in
            for annotation in annotations {
                context.stroke(Path(AnnotationDrawing.path(annotation, size: size)),
                               with: .color(AnnotationDrawing.color(annotation.ink ?? .red)),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }
}
