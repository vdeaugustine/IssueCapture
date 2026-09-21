import SwiftUI
import PhotosUI

/// Compact issue form. Opens focused on the description so reporting starts
/// with typing; the screenshot and secondary fields stay collapsed until asked for.
struct IssueEditor: View {
    let session: CaptureSession
    let onFinish: () -> Void
    @State var report: IssueReport
    @State var attachment: UIImage?
    @State private var photo: PhotosPickerItem?
    @State private var annotating = false
    @State private var loadingPhoto = false
    @State private var confirmDiscard = false
    @State private var confirmReporterCapture = false
    @State private var showDetails = false
    @State private var showContext = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case description, expected, steps }

    private var image: UIImage? { session.draftImage ?? attachment }

    private var canSave: Bool {
        !report.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !session.isBusy && !loadingPhoto
    }

    var body: some View {
        Form {
            descriptionSection
            IssueScreenshotSection(screenshot: session.draftImage,
                                   attachment: attachment,
                                   annotations: report.annotations,
                                   captureStatus: report.captureStatus,
                                   photo: $photo,
                                   loadingPhoto: loadingPhoto,
                                   onAnnotate: { annotating = true })
            IssueTagPicker(tags: $report.tags)
            detailsSection
            contextSection
        }
        .listSectionSpacing(.compact)
        .navigationTitle(report.description.isEmpty ? "Report an issue" : report.displayID)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar { toolbarContent }
        .interactiveDismissDisabled()
        .task {
            guard focus == nil, report.description.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(450))
            focus = .description
        }
        .sheet(isPresented: $annotating) {
            if let image {
                IssueAnnotationEditor(image: image, annotations: $report.annotations)
            }
        }
        .confirmationDialog("Discard changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive, action: onFinish)
        }
        .confirmationDialog("Capture the IssueCapture screen?", isPresented: $confirmReporterCapture,
                            titleVisibility: .visible) {
            Button("Capture IssueCapture screen") { session.captureReporter() }
        } message: {
            Text("This starts a new report and replaces the current draft. Save it first if you want to keep it.")
        }
        .onChange(of: photo) { _, selection in loadPhoto(selection) }
    }

    private var descriptionSection: some View {
        Section {
            TextField("What went wrong?", text: $report.description, axis: .vertical)
                .lineLimit(3...10)
                .font(.body)
                .focused($focus, equals: .description)
                .submitLabel(.return)
                .accessibilityLabel("Issue description")
        } footer: {
            Text("Required. Everything else is optional.")
        }
    }

    private var detailsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showDetails) {
                TextField("Expected behavior", text: $report.expectedBehavior, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($focus, equals: .expected)
                TextField("Steps to reproduce", text: $report.reproductionNotes, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($focus, equals: .steps)
            } label: {
                IssueRowLabel(title: "More detail",
                              subtitle: detailSummary,
                              systemImage: "text.alignleft")
            }
        }
    }

    private var detailSummary: String {
        let filled = [report.expectedBehavior, report.reproductionNotes]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return filled.isEmpty ? "Expected behavior, steps" : "\(filled.count) added"
    }

    private var contextSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showContext) {
                Text(report.contextStatus).font(.caption).foregroundStyle(.secondary)
                ForEach(report.screens) { screen in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(screen.name)
                        Text("\(screen.file):\(screen.line)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("\(report.events.count) recent events attached")
                    .font(.caption).foregroundStyle(.secondary)
            } label: {
                IssueRowLabel(title: "Captured context",
                              subtitle: "\(report.screens.count) screens · \(report.events.count) events",
                              systemImage: "scope")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                if hasChanges { confirmDiscard = true } else { onFinish() }
            }.disabled(session.isBusy || loadingPhoto)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(session.isBusy ? "Saving…" : "Save") { save() }
                .fontWeight(.semibold)
                .disabled(!canSave)
        }
        ToolbarItem(placement: .topBarLeading) {
            NavigationLink {
                IssueInbox(session: session, onClose: onFinish)
            } label: {
                Label("Issue box", systemImage: "tray.full")
            }
            .accessibilityHint("Opens saved issue reports")
        }
        ToolbarItem(placement: .secondaryAction) {
            Button("Capture IssueCapture screen", systemImage: "ladybug") {
                confirmReporterCapture = true
            }
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focus = nil }
        }
    }

    private func save() {
        focus = nil
        Task { if await session.save(report, attachment: attachment) { onFinish() } }
    }

    private func loadPhoto(_ selection: PhotosPickerItem?) {
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

    private var hasChanges: Bool {
        guard let original = session.draft else { return true }
        return report.description != original.description || report.expectedBehavior != original.expectedBehavior
            || report.reproductionNotes != original.reproductionNotes
            || report.tags != original.tags
            || (try? JSONEncoder().encode(report.annotations)) != (try? JSONEncoder().encode(original.annotations))
            || attachment !== session.draftAttachment
    }
}

/// Two-line row label used by the editor's collapsed disclosure groups.
struct IssueRowLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
