import SwiftUI
import PhotosUI

struct IssueEditor: View {
    let session: CaptureSession
    let onFinish: () -> Void
    @State var report: IssueReport
    @State var attachment: UIImage?
    @State private var photo: PhotosPickerItem?
    @State private var tool: IssueAnnotation.Kind = .arrow
    @State private var confirmDiscard = false
    @FocusState private var descriptionFocused: Bool

    var body: some View {
        Form {
            Section("What went wrong?") {
                TextField("Describe what happened…", text: $report.description, axis: .vertical)
                    .lineLimit(3...8).focused($descriptionFocused)
                TextField("Expected behavior (optional)", text: $report.expectedBehavior, axis: .vertical)
                TextField("Steps to reproduce (optional)", text: $report.reproductionNotes, axis: .vertical)
            }
            Section("Screenshot") {
                if let image = session.draftImage ?? attachment {
                    Picker("Annotation tool", selection: $tool) {
                        ForEach(IssueAnnotation.Kind.allCases, id: \.self) { kind in
                            Text(kind.rawValue.capitalized).tag(kind)
                        }
                    }.pickerStyle(.segmented)
                    AnnotationCanvas(image: image, annotations: $report.annotations, tool: tool)
                    HStack {
                        Button("Undo") { _ = report.annotations.popLast() }
                        Spacer()
                        Button("Reset", role: .destructive) { report.annotations = [] }
                    }.disabled(report.annotations.isEmpty)
                }
                Text(report.captureStatus).font(.caption).foregroundStyle(.secondary)
                PhotosPicker(selection: $photo, matching: .images) {
                    Label(attachment == nil ? "Attach image" : "Replace attachment", systemImage: "photo.badge.plus")
                }
                if let attachment, session.draftImage != nil {
                    Image(uiImage: attachment).resizable().scaledToFit()
                }
            }
            Section("Captured context") {
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
        .navigationTitle(report.displayID)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if hasChanges { confirmDiscard = true } else { onFinish() }
                }.disabled(session.isBusy)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { if await session.save(report, attachment: attachment) { onFinish() } }
                }.disabled(report.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isBusy)
            }
        }
        .interactiveDismissDisabled()
        .confirmationDialog("Discard changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive, action: onFinish)
        }
        .task { if report.description.isEmpty { descriptionFocused = true } }
        .onChange(of: photo) { _, selection in
            Task {
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
            || (try? JSONEncoder().encode(report.annotations)) != (try? JSONEncoder().encode(original.annotations))
            || attachment !== session.draftAttachment
    }
}
