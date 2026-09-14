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
            Section {
                Toggle("Today only", isOn: $todayOnly)
                Toggle("Not previously exported", isOn: $newOnly)
                Picker("Tag", selection: $tagFilter) {
                    Text("All tags").tag("")
                    ForEach(Array(Set(session.reports.flatMap { $0.tags ?? [] })).sorted(), id: \.self) { tag in
                        Text(tag).tag(tag)
                    }
                }
                Button("Select visible (\(filtered.count))") { selected.formUnion(filtered.map(\.id)) }
            }
            Section("\(selected.count) selected · \(filtered.count) visible") {
                if filtered.isEmpty { ContentUnavailableView("No issues", systemImage: "tray", description: Text("Capture an issue using the floating tab.")) }
                if !selected.isEmpty { Button("Clear selection") { selected = [] } }
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
                    }
                }
            }
            Section {
                Button(exporting ? "Preparing export…" : "Export selected (\(selected.count))…", systemImage: "square.and.arrow.up") {
                    exportOptions = ExportRoute(reports: session.reports.filter { selected.contains($0.id) })
                }
                    .disabled(selected.isEmpty || exporting)
                Button("Copy agent prompt", systemImage: "doc.on.doc") { UIPasteboard.general.string = IssueMarkdown.agentPrompt }
                Button("Delete selected", role: .destructive) { confirmDelete = true }
                    .disabled(selected.isEmpty || exporting)
                Text("Export preparation is tracked; delivery and fixes are not. Saved reports remain until deleted. Removing this app can remove its reports.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Issue inbox")
        .searchable(text: $search, prompt: "Description, issue ID, or tag")
        .interactiveDismissDisabled(exporting)
        .disabled(exporting)
        .overlay { if exporting { ProgressView("Preparing export…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onClose).disabled(exporting) } }
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
        .confirmationDialog("Permanently delete \(selected.count) reports?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete reports", role: .destructive) { deleteSelected() }
        }
    }

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
