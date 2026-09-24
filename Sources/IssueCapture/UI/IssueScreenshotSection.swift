import SwiftUI
import PhotosUI

/// Expanded evidence preview for the issue editor.
///
/// The preview never receives touches, so scrolling past it cannot draw on the
/// image; annotating is an explicit action that opens the full editor.
struct IssueScreenshotSection: View {
    let screenshot: UIImage?
    @Binding var includeScreenshot: Bool
    let attachment: UIImage?
    let annotations: [IssueAnnotation]
    let captureStatus: String
    @Binding var photo: PhotosPickerItem?
    let loadingPhoto: Bool
    let onAnnotate: () -> Void
    @State private var expanded = true

    private var preview: UIImage? { (includeScreenshot ? screenshot : nil) ?? attachment }
    private var annotationCount: Int { annotations.count }

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $expanded) {
                if screenshot != nil {
                    Toggle("Attach captured screenshot", isOn: $includeScreenshot)
                }
                if let preview {
                    imagePreview(preview, annotated: true)
                    Button(annotationCount == 0 ? "Annotate image" : "Edit annotations",
                           systemImage: "pencil.tip.crop.circle",
                           action: onAnnotate)
                }
                if let attachment, includeScreenshot && screenshot != nil {
                    imagePreview(attachment, annotated: false)
                }
                PhotosPicker(selection: $photo, matching: .images) {
                    Label(attachment == nil ? "Attach image" : "Replace attachment",
                          systemImage: "photo.badge.plus")
                }
                .disabled(loadingPhoto)
                if !captureStatus.isEmpty {
                    DisclosureGroup("Capture details") {
                        Text(captureStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } label: {
                header
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 1) {
                Text(preview == nil ? "No image attached" : "Image attached")
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            if loadingPhoto { Spacer(); ProgressView() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Image. \(subtitle)")
    }

    private var subtitle: String {
        if loadingPhoto { return "Loading image…" }
        if preview == nil { return screenshot == nil ? "Add an image if helpful" : "Screenshot available · toggle to attach" }
        return annotationCount == 0 ? "Ready to annotate" : "\(annotationCount) annotations"
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let preview {
            Image(uiImage: preview)
                .resizable()
                .scaledToFill()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.quaternary))
                .accessibilityHidden(true)
        } else {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
        }
    }

    private func imagePreview(_ image: UIImage, annotated: Bool) -> some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / image.size.width, geometry.size.height / image.size.height)
            Image(uiImage: image)
                .resizable()
                .frame(width: image.size.width * scale, height: image.size.height * scale)
                .overlay { if annotated { annotationOverlay } }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 180)
        .allowsHitTesting(false)
        .accessibilityLabel("Issue image preview")
    }

    private var annotationOverlay: some View {
        Canvas { context, size in
            for annotation in annotations {
                context.stroke(Path(AnnotationDrawing.path(annotation, size: size)),
                               with: .color(AnnotationDrawing.color(annotation.ink ?? .red)),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
    }
}
