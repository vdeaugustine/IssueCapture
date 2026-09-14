import SwiftUI
import PhotosUI

struct IssueEditor: View {
    let session: CaptureSession
    let onFinish: () -> Void
    @State var report: IssueReport
    @State var attachment: UIImage?
    @State private var photo: PhotosPickerItem?
    @State private var annotating = false
    @State private var loadingPhoto = false
    @State private var confirmDiscard = false

    var body: some View {
        Form {
            Section("What went wrong?") {
                TextField("Describe what happened…", text: $report.description, axis: .vertical)
                    .lineLimit(3...8)
            }
            Section("Additional details (optional)") {
                TextField("Expected behavior (optional)", text: $report.expectedBehavior, axis: .vertical)
                TextField("Steps to reproduce (optional)", text: $report.reproductionNotes, axis: .vertical)
            }
            Section("Screenshot") {
                if let image = session.draftImage ?? attachment {
                    AnnotationCanvas(image: image, annotations: $report.annotations, tool: .arrow)
                        .allowsHitTesting(false).frame(maxHeight: 240)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Issue image preview")
                    Button(report.annotations.isEmpty ? "Annotate image" : "Edit annotations", systemImage: "pencil.tip.crop.circle") {
                        annotating = true
                    }

                }
                Text(report.captureStatus).font(.caption).foregroundStyle(.secondary)
                PhotosPicker(selection: $photo, matching: .images) {
                    Label(attachment == nil ? "Attach image" : "Replace attachment", systemImage: "photo.badge.plus")
                }
                .disabled(loadingPhoto)
                if loadingPhoto { ProgressView("Loading image…") }
                if let attachment, session.draftImage != nil {
                    Image(uiImage: attachment).resizable().scaledToFit()
                }
            }
            IssueTagPicker(tags: $report.tags)
            Section {
                DisclosureGroup("Captured context") {
                    Text(report.contextStatus).font(.caption)
                    ForEach(report.screens) { screen in
                        VStack(alignment: .leading) {
                            Text(screen.name)
                            Text("\(screen.file):\(screen.line)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("\(report.events.count) recent events attached").font(.caption)
                }
            }
        }
        .navigationTitle(report.description.isEmpty ? "Report an issue" : report.displayID)
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $annotating) {
            if let image = session.draftImage ?? attachment {
                IssueAnnotationEditor(image: image, annotations: $report.annotations)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if hasChanges { confirmDiscard = true } else { onFinish() }
                }.disabled(session.isBusy || loadingPhoto)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(session.isBusy ? "Saving…" : "Save issue") {
                    Task { if await session.save(report, attachment: attachment) { onFinish() } }
                }.disabled(report.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isBusy || loadingPhoto)
            }
        }
        .interactiveDismissDisabled()
        .confirmationDialog("Discard changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive, action: onFinish)
        }
        .onChange(of: photo) { _, selection in
            loadingPhoto = true
            Task {
                defer { loadingPhoto = false }
                do {
                    guard let data = try await selection?.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { return }
                    if session.draftImage == nil { report.annotations = [] }
                    attachment = image
                } catch { session.errorMessage = error.localizedDescription }
            }
        }
    }

    private var hasChanges: Bool {
        guard let original = session.draft else { return true }
        return report.description != original.description || report.expectedBehavior != original.expectedBehavior
            || report.reproductionNotes != original.reproductionNotes
            || report.tags != original.tags
            || (try? JSONEncoder().encode(report.annotations)) != (try? JSONEncoder().encode(original.annotations))
            || attachment !== session.draftAttachment
    }
}
