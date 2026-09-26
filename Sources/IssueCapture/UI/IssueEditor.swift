import SwiftUI

/// Evidence-first report form with optional context and explicit save actions.
struct IssueEditor: View {
    @ObservedObject var session: CaptureSession
    let onFinish: () -> Void
    @State var report: IssueReport
    @State var attachment: UIImage?
    @State private var pickingPhoto = false
    @State private var annotating = false
    @State private var loadingPhoto = false
    @State private var confirmDiscard = false
    @State private var confirmReporterCapture = false
    @State private var showDetails = false
    @State private var showContext = false
    @State private var savedForReview = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case description, expected, steps }

    private var image: UIImage? { (report.hasScreenshot ? session.draftImage : nil) ?? attachment }

    private var canSave: Bool {
        !report.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !session.isBusy && !loadingPhoto
    }

    var body: some View {
        Form {
            classificationSection
            descriptionSection
            IssueScreenshotSection(screenshot: session.draftImage,
                                   includeScreenshot: $report.hasScreenshot,
                                   attachment: attachment,
                                   annotations: report.annotations,
                                   captureStatus: report.captureStatus,
                                   onAttach: { pickingPhoto = true },
                                   loadingPhoto: loadingPhoto,
                                   onAnnotate: { annotating = true })
            IssueTagPicker(tags: $report.tags)
            detailsSection
            contextSection
        }
        .disabled(session.isBusy)
        .reporterSectionSpacing()
        .safeAreaInset(edge: .bottom) { saveBar }
        .reporterDestination(isPresented: $savedForReview) {
            IssueInbox(session: session, onClose: onFinish)
                .navigationBarBackButtonHidden()
        }
        .navigationTitle(report.description.isEmpty ? "Report an issue" : report.displayID)
        .navigationBarTitleDisplayMode(.inline)
        .reporterKeyboardDismissal()
        .toolbar { toolbarContent }
        .interactiveDismissDisabled()
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
        .sheet(isPresented: $pickingPhoto) {
            ReporterPhotoPicker(loading: $loadingPhoto) { image in
                if !report.hasScreenshot { report.annotations = [] }
                attachment = image
            } onError: { session.errorMessage = $0 }
        }
        .onChange(of: report.hasScreenshot) { included in
            if !included { report.annotations = [] }
        }
    }

    private var classificationSection: some View {
        Section("Report") {
            Picker("Type", selection: Binding(
                get: { report.effectiveKind }, set: { report.kind = $0 })) {
                ForEach(IssueKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            Picker("For", selection: Binding(
                get: { report.effectiveTarget }, set: { report.target = $0 })) {
                ForEach(IssueTarget.allCases, id: \.self) { target in
                    Text(target.title).tag(target)
                }
            }
        }
    }

    private var descriptionSection: some View {
        Section {
            ReporterTextInput(report.effectiveKind == .bug ? "What went wrong?" : "What would you like added?",
                      text: $report.description, lines: 3...10)
                .font(.body)
                .focused($focus, equals: .description)
                .submitLabel(.return)
                .accessibilityLabel("Issue description")
        } header: {
            Text(report.effectiveKind == .bug ? "What needs fixing?" : "What would improve it?")
        } footer: {
            Text("A short description is all you need. Images are optional.")
        }
    }

    private var detailsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showDetails) {
                ReporterTextInput("Expected behavior", text: $report.expectedBehavior, lines: 1...6)
                    .focused($focus, equals: .expected)
                ReporterTextInput("Steps to reproduce", text: $report.reproductionNotes, lines: 1...6)
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
        ToolbarItem(placement: .reporterSecondaryAction) {
            ReporterLabelButton("Capture IssueCapture screen", systemImage: "ladybug") {
                confirmReporterCapture = true
            }
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focus = nil }
        }
    }

    private var saveBar: some View {
        VStack(spacing: 10) {
            Button { save(review: true) } label: {
                Label(session.isBusy ? "Saving…" : "Save & review for handoff", systemImage: "tray.and.arrow.down")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent).disabled(!canSave)
            Button("Save & return to app") { save(review: false) }
                .frame(minHeight: 44).disabled(!canSave)
        }
        .padding(.horizontal, 20).padding(.vertical, 12).background(.bar)
    }

    private func save(review: Bool) {
        focus = nil
        Task {
            if await session.save(report, attachment: attachment) {
                session.draft = report
                session.draftAttachment = attachment
                if review { savedForReview = true } else { onFinish() }
            }
        }
    }

    private var hasChanges: Bool {
        guard let original = session.draft else { return true }
        return report.description != original.description || report.expectedBehavior != original.expectedBehavior
            || report.reproductionNotes != original.reproductionNotes
            || report.effectiveKind != original.effectiveKind || report.effectiveTarget != original.effectiveTarget
            || report.hasScreenshot != original.hasScreenshot
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
