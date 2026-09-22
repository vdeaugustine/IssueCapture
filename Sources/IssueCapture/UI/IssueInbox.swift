import SwiftUI

struct IssueInbox: View {
    let session: CaptureSession
    let onClose: () -> Void
    @State private var selected: Set<UUID> = []
    @State private var search = ""
    @State private var todayOnly = false
    @State private var newOnly = false
    @State private var tagFilter = ""
    @State private var exportOptions: ExportRoute?
    @State private var pendingExport: (reports: [IssueReport], options: ExportImageOptions)?
    @State private var confirmDelete = false
    @State private var editor: EditorRoute?
    @State private var share: ShareRoute?
    @State private var exporting = false
    @State private var loadingEditor = false
    @State private var copyNotice: String?

    private var filtered: [IssueReport] {
        session.reports.filter {
            (!todayOnly || Calendar.current.isDateInToday($0.capturedAt)) &&
            (!newOnly || $0.exportPreparedAt.isEmpty) &&
            (tagFilter.isEmpty || ($0.tags ?? []).contains(tagFilter)) &&
            (search.isEmpty || $0.description.localizedCaseInsensitiveContains(search) ||
                $0.displayID.localizedCaseInsensitiveContains(search) ||
                ($0.tags ?? []).contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }

    var body: some View {
        List {
            Section("\(selected.count) selected · \(filtered.count) visible") {
                if filtered.isEmpty { ContentUnavailableView("No issues", systemImage: "tray", description: Text("Capture an issue using the floating tab.")) }
                ForEach(filtered) { report in
                    HStack(alignment: .top, spacing: 12) {
                        Button { toggle(report.id) } label: {
                            Image(systemName: selected.contains(report.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title2).frame(minWidth: 44, minHeight: 44)
                        }.buttonStyle(.borderless).accessibilityLabel("Select \(report.displayID)")
                        Button { open(report) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(report.displayID).font(.caption.monospaced()).foregroundStyle(.secondary)
                                Text(report.description).lineLimit(3).foregroundStyle(.primary)
                                if let tags = report.tags, !tags.isEmpty {
                                    Text(tags.joined(separator: " · ")).font(.caption).foregroundStyle(.tint)
                                }
                                Text(report.capturedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain).disabled(loadingEditor)
                        Menu {
                            handoffActions([report])
                        } label: {
                            Image(systemName: "square.and.arrow.up").frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Share \(report.displayID)")
                    }
                }
            }
            Section {
                Text("Export preparation is tracked; delivery and fixes are not. Saved reports remain until deleted. Removing this app can remove its reports.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Issue inbox")
        .searchable(text: $search, prompt: "Description, issue ID, or tag")
        .interactiveDismissDisabled(exporting)
        .disabled(exporting)
        .overlay { if exporting { ProgressView("Preparing export…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        .toolbar { toolbarContent }
        .task { await session.refresh() }
        .sheet(item: $editor) { route in
            NavigationStack {
                IssueEditor(session: session, onFinish: { editor = nil }, report: route.report, attachment: session.draftAttachment)
            }
            .alert("Could not save", isPresented: Binding(get: { session.errorMessage != nil },
                                                          set: { if !$0 { session.errorMessage = nil } })) {
                Button("OK") { session.errorMessage = nil }
            } message: { Text(session.errorMessage ?? "") }
        }
        .sheet(item: $exportOptions, onDismiss: {
            if let pendingExport {
                self.pendingExport = nil
                export(pendingExport.reports, options: pendingExport.options)
            }
        }) { route in
            IssueExportSheet(reports: route.reports) { options in
                pendingExport = (route.reports, options)
                exportOptions = nil
            }
        }
        .sheet(item: $share) { route in ShareSheet(url: route.url) }
        .alert("Copied", isPresented: Binding(get: { copyNotice != nil },
                                             set: { if !$0 { copyNotice = nil } })) {
            Button("OK") { copyNotice = nil }
        } message: { Text(copyNotice ?? "") }
        .confirmationDialog("Permanently delete \(selected.count) reports?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete reports", role: .destructive) { deleteSelected() }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { filterMenu }
        ToolbarItem(placement: .confirmationAction) { Button("Done", action: onClose).disabled(exporting) }
        ToolbarItem(placement: .secondaryAction) {
            Button("Capture IssueCapture screen", systemImage: "ladybug") {
                session.captureReporter()
            }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Menu {
                handoffActions(session.reports.filter { selected.contains($0.id) })
            } label: {
                Label("Export (\(selected.count))", systemImage: "square.and.arrow.up")
            }
            .disabled(selected.isEmpty || exporting)
            Spacer()
            Button("Copy agent prompt", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = IssueMarkdown.agentPrompt
            }
            .labelStyle(.iconOnly)
            Spacer()
            Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                .labelStyle(.iconOnly)
                .disabled(selected.isEmpty || exporting)
        }
    }

    @ViewBuilder
    private func handoffActions(_ reports: [IssueReport]) -> some View {
        Button("Copy for Codex", systemImage: "doc.on.doc") { handoff(reports, action: .text) }
        Button("Share PDF", systemImage: "doc.richtext") { handoff(reports, action: .sharePDF) }
        Button("Copy PDF", systemImage: "doc.on.clipboard") { handoff(reports, action: .copyPDF) }
        Button("Export ZIP…", systemImage: "archivebox") { exportOptions = ExportRoute(reports: reports) }
    }

    private enum HandoffAction { case text, sharePDF, copyPDF }

    private func handoff(_ reports: [IssueReport], action: HandoffAction) {
        exporting = true
        Task {
            defer { exporting = false }
            do {
                switch action {
                case .text:
                    try await IssueHandoff.copyText(reports)
                    copyNotice = "Issue text and complete metadata copied. Paste into Codex. Images are available through PDF or ZIP."
                case .sharePDF:
                    share = ShareRoute(url: try await IssueExporter.shared.exportPDF(reports))
                case .copyPDF:
                    let url = try await IssueExporter.shared.exportPDF(reports)
                    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
                    try IssueHandoff.copyPDF(url)
                    copyNotice = "PDF copied with text, metadata, and images. If the destination does not accept PDF paste, use Share PDF to save or attach it."
                }
                await session.refresh()
            } catch { session.errorMessage = error.localizedDescription }
        }
    }

    private var filterMenu: some View {
        Menu {
            Toggle("Today only", isOn: $todayOnly)
            Toggle("Not previously exported", isOn: $newOnly)
            Picker("Tag", selection: $tagFilter) {
                Text("All tags").tag("")
                ForEach(Array(Set(session.reports.flatMap { $0.tags ?? [] })).sorted(), id: \.self) { tag in
                    Text(tag).tag(tag)
                }
            }
            Divider()
            Button("Select visible (\(filtered.count))") { selected.formUnion(filtered.map(\.id)) }
            Button("Clear selection") { selected = [] }.disabled(selected.isEmpty)
        } label: {
            Label("Filter", systemImage: filtersActive ? "line.3.horizontal.decrease.circle.fill"
                                                       : "line.3.horizontal.decrease.circle")
        }
    }

    private var filtersActive: Bool { todayOnly || newOnly || !tagFilter.isEmpty }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func open(_ report: IssueReport) {
        loadingEditor = true
        Task {
            await session.edit(report)
            if session.draft?.id == report.id { editor = EditorRoute(report: report) }
            loadingEditor = false
        }
    }

    private func export(_ reports: [IssueReport], options: ExportImageOptions) {
        exporting = true
        Task {
            do {
                let url = try await IssueExporter.shared.export(reports, options: options)
                share = ShareRoute(url: url)
                await session.refresh()
            } catch { session.errorMessage = error.localizedDescription }
            exporting = false
        }
    }

    private func deleteSelected() {
        Task {
            do {
                for id in selected { try await ReportStore.shared.delete(id) }
                selected = []
                await session.refresh()
            } catch { session.errorMessage = error.localizedDescription }
        }
    }
}

private struct EditorRoute: Identifiable { let report: IssueReport; var id: UUID { report.id } }
private struct ShareRoute: Identifiable { let id = UUID(); let url: URL }

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct ExportRoute: Identifiable { let id = UUID(); let reports: [IssueReport] }
