import SwiftUI

struct IssueInbox: View {
    @ObservedObject var session: CaptureSession
    let onClose: () -> Void
    @State private var selected: Set<UUID> = []
    @State private var search = ""
    @State private var todayOnly = false
    @State private var newOnly = false
    @State private var tagFilter = ""
    @State private var exportOptions: ExportRoute?
    @State private var pendingExport: (reports: [IssueReport], options: ExportImageOptions)?
    @State private var confirmDelete = false
    @State private var confirmExportDeletion = false
    @State private var exportedReportIDs: Set<UUID> = []
    @State private var sharedReportIDs: Set<UUID> = []
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
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Ready for your next fix", systemImage: "tray.full.fill")
                        .font(.title3.weight(.semibold))
                    Text("Review evidence, select reports, then send everything your coding agent needs.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("\(session.reports.count) saved · \(session.reports.filter { $0.exportPreparedAt.isEmpty }.count) not yet exported")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
                if !filtered.isEmpty {
                    Button(selected.isSuperset(of: Set(filtered.map(\.id))) ? "Clear visible selection" : "Select all visible") {
                        let visible = Set(filtered.map(\.id))
                        if selected.isSuperset(of: visible) { selected.subtract(visible) }
                        else { selected.formUnion(visible) }
                    }
                }
            }
            Section("\(selected.count) selected · \(filtered.count) visible") {
                if filtered.isEmpty {
                    ReporterEmptyState(session.reports.isEmpty ? "Your next fix starts here" : "No matching reports",
                        systemImage: session.reports.isEmpty ? "viewfinder" : "magnifyingglass",
                        description: Text(session.reports.isEmpty ? "Return to your app and tap the floating capture button." : "Try another search or clear your filters."))
                    if filtersActive || !search.isEmpty {
                        Button("Clear search and filters") { search = ""; todayOnly = false; newOnly = false; tagFilter = "" }
                    }
                }
                ForEach(filtered) { report in
                    HStack(alignment: .top, spacing: 12) {
                        Button { toggle(report.id) } label: {
                            Image(systemName: selected.contains(report.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title2).frame(minWidth: 44, minHeight: 44)
                        }.buttonStyle(.borderless).accessibilityLabel("Select \(report.displayID)")
                        .accessibilityValue(selected.contains(report.id) ? "Selected" : "Not selected")
                        Button { open(report) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    Text(report.displayID).font(.caption.monospaced()).foregroundStyle(.secondary)
                                    Image(systemName: report.hasScreenshot || report.hasAttachment ? "photo.fill" : "photo")
                                        .font(.caption)
                                        .foregroundStyle(report.hasScreenshot || report.hasAttachment ? Color.accentColor : Color.secondary)
                                        .accessibilityLabel(report.hasScreenshot || report.hasAttachment
                                                            ? "Image attached" : "No image attached")
                                }
                                Text("\(report.effectiveKind.title) · \(report.effectiveTarget.title)")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(report.description).font(.headline).lineLimit(3).foregroundStyle(.primary)
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
                    .swipeActions(edge: .trailing) {
                        ReporterLabelButton("Delete", systemImage: "trash", role: .destructive) {
                            delete([report.id])
                        }
                    }
                }
            }
            Section {
                Text("Export preparation is tracked; delivery and fixes are not. Saved reports remain until deleted. Removing this app can remove its reports.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Saved issues")
        .reporterSectionSpacing()
        .onChange(of: session.reports.map(\.id)) { identifiers in
            selected.formIntersection(identifiers)
        }
        .searchable(text: $search, prompt: "Description, issue ID, or tag")
        .interactiveDismissDisabled(exporting)
        .disabled(exporting)
        .overlay { if exporting { ProgressView("Preparing export…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        .toolbar { toolbarContent }
        .task { await session.refresh() }
        .sheet(item: $editor) { route in
            ReporterNavigation {
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
        .sheet(item: $share, onDismiss: {
            offerDeletion(for: sharedReportIDs)
            sharedReportIDs = []
        }) { route in ShareSheet(url: route.url) }
        .alert("Copied", isPresented: Binding(get: { copyNotice != nil },
                                             set: { if !$0 { copyNotice = nil } })) {
            Button("OK") { copyNotice = nil }
        } message: { Text(copyNotice ?? "") }
        .confirmationDialog("Permanently delete \(selected.count) reports?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete reports", role: .destructive) { deleteSelected() }
        }
        .confirmationDialog("Delete the \(exportedReportIDs.count) exported \(exportedReportIDs.count == 1 ? "issue" : "issues")?",
                            isPresented: $confirmExportDeletion, titleVisibility: .visible) {
            Button("Delete exported issues", role: .destructive) { delete(exportedReportIDs) }
            Button("Keep issues", role: .cancel) {}
        } message: {
            Text("The export was prepared. Delete these saved issues if you're finished with them.")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) { filterMenu }
        ToolbarItem(placement: .confirmationAction) { Button("Done", action: onClose).disabled(exporting) }
        ToolbarItem(placement: .reporterSecondaryAction) {
            NavigationLink {
                CaptureButtonSettings(session: session, onClose: onClose)
            } label: {
                Label("Button appearance", systemImage: "slider.horizontal.3")
            }
            ReporterLabelButton("Capture IssueCapture screen", systemImage: "ladybug") {
                session.captureReporter()
            }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            ReporterLabelButton("Copy for Codex", systemImage: "doc.on.doc") {
                handoff(session.reports.filter { selected.contains($0.id) }, action: .text)
            }
            .disabled(selected.isEmpty || exporting)
            Spacer()
            Menu {
                handoffActions(session.reports.filter { selected.contains($0.id) })
            } label: {
                Label("Share (\(selected.count))", systemImage: "square.and.arrow.up")
            }
            .disabled(selected.isEmpty || exporting)
            Spacer()
            ReporterLabelButton("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                .labelStyle(.iconOnly)
                .disabled(selected.isEmpty || exporting)
        }
    }

    @ViewBuilder
    private func handoffActions(_ reports: [IssueReport]) -> some View {
        ReporterLabelButton("Copy for Codex", systemImage: "doc.on.doc") { handoff(reports, action: .text) }
        ReporterLabelButton("Share PDF", systemImage: "doc.richtext") { handoff(reports, action: .sharePDF) }
        ReporterLabelButton("Copy PDF", systemImage: "doc.on.clipboard") { handoff(reports, action: .copyPDF) }
        ReporterLabelButton("Export ZIP…", systemImage: "archivebox") { exportOptions = ExportRoute(reports: reports) }
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
                    offerDeletion(for: Set(reports.map(\.id)))
                case .sharePDF:
                    let url = try await IssueExporter.shared.exportPDF(reports)
                    sharedReportIDs = Set(reports.map(\.id))
                    share = ShareRoute(url: url)
                case .copyPDF:
                    let url = try await IssueExporter.shared.exportPDF(reports)
                    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
                    try IssueHandoff.copyPDF(url)
                    offerDeletion(for: Set(reports.map(\.id)))
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
            ReporterLabelButton("Copy agent instructions", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = IssueMarkdown.agentPrompt
                copyNotice = "Agent instructions copied."
            }
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
                sharedReportIDs = Set(reports.map(\.id))
                share = ShareRoute(url: url)
                await session.refresh()
            } catch { session.errorMessage = error.localizedDescription }
            exporting = false
        }
    }

    private func deleteSelected() {
        delete(selected)
    }

    private func offerDeletion(for identifiers: Set<UUID>) {
        guard !identifiers.isEmpty else { return }
        exportedReportIDs = identifiers
        confirmExportDeletion = true
    }

    private func delete(_ identifiers: Set<UUID>) {
        Task {
            do {
                for id in identifiers { try await ReportStore.shared.delete(id) }
                selected.subtract(identifiers)
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
