import SwiftUI
import PhotosUI

/// Collapsed-by-default image row for the issue editor.
///
/// The preview never receives touches, so scrolling past it cannot draw on the
/// image; annotating is an explicit action that opens the full editor.
struct IssueScreenshotSection: View {
    let screenshot: UIImage?
    let attachment: UIImage?
    let annotations: [IssueAnnotation]
    let captureStatus: String
    @Binding var photo: PhotosPickerItem?
    let loadingPhoto: Bool
    let onAnnotate: () -> Void
    @State private var expanded = false

    private var preview: UIImage? { screenshot ?? attachment }
    private var annotationCount: Int { annotations.count }

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $expanded) {
                if let preview {
                    imagePreview(preview, annotated: true)
                    Button(annotationCount == 0 ? "Annotate image" : "Edit annotations",
                           systemImage: "pencil.tip.crop.circle",
                           action: onAnnotate)
                }
                if let attachment, screenshot != nil {
                    imagePreview(attachment, annotated: false)
                }
                PhotosPicker(selection: $photo, matching: .images) {
                    Label(attachment == nil ? "Attach image" : "Replace attachment",
                          systemImage: "photo.badge.plus")
                }
                .disabled(loadingPhoto)
                if !captureStatus.isEmpty {
                    Text(captureStatus).font(.caption).foregroundStyle(.secondary)
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
                Text(preview == nil ? "No image" : "Screenshot")
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            if loadingPhoto { Spacer(); ProgressView() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Image. \(subtitle)")
    }

    private var subtitle: String {
        if loadingPhoto { return "Loading image…" }
        if preview == nil { return "Tap to attach one" }
        return annotationCount == 0 ? "Tap to preview or annotate" : "\(annotationCount) annotations"
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
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 260)
            .overlay { if annotated { annotationOverlay } }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityLabel("Issue image preview")
    }

    private var annotationOverlay: some View {
        Canvas { context, size in
            for annotation in annotations {
                context.stroke(Path(AnnotationDrawing.path(annotation, size: size)),
                               with: .color(.red),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
    }
}
