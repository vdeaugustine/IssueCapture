import SwiftUI

struct IssueInbox: View {
    let session: CaptureSession
    let onClose: () -> Void
    @State private var selected: Set<UUID> = []
    @State private var search = ""
    @State private var todayOnly = false
    @State private var newOnly = false
    @State private var includeCards = true
    @State private var confirmDelete = false
    @State private var editor: EditorRoute?
    @State private var share: ShareRoute?
    @State private var exporting = false
    @State private var loadingEditor = false

    private var filtered: [IssueReport] {
        session.reports.filter {
            (!todayOnly || Calendar.current.isDateInToday($0.capturedAt)) &&
            (!newOnly || $0.exportPreparedAt.isEmpty) &&
            (search.isEmpty || $0.description.localizedCaseInsensitiveContains(search) ||
                $0.displayID.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        List {
            Section {
                Toggle("Today only", isOn: $todayOnly)
                Toggle("Not previously exported", isOn: $newOnly)
                Toggle("Include image cards", isOn: $includeCards)
                Button("Select visible (\(filtered.count))") { selected = Set(filtered.map(\.id)) }
            }
            Section("\(selected.count) selected") {
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
                                Text(report.capturedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain).disabled(loadingEditor)
                    }
                }
            }
            Section {
                Button(exporting ? "Preparing export…" : "Export selected", systemImage: "square.and.arrow.up", action: export)
                    .disabled(selected.isEmpty || exporting)
                Button("Copy agent prompt", systemImage: "doc.on.doc") { UIPasteboard.general.string = IssueMarkdown.agentPrompt }
                Button("Delete selected", role: .destructive) { confirmDelete = true }
                    .disabled(selected.isEmpty || exporting)
                Text("Export preparation is tracked; delivery and fixes are not. Saved reports remain until deleted. Removing this app can remove its reports.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Issue inbox")
        .searchable(text: $search, prompt: "Description or issue ID")
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

    private func export() {
        exporting = true
        let reports = session.reports.filter { selected.contains($0.id) }
        Task {
            do {
                let url = try await IssueExporter.shared.export(reports, includeCards: includeCards)
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
