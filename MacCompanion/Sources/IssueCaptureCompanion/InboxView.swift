import AppKit
import CompanionCore
import SwiftUI
import UniformTypeIdentifiers

/// Three panes: candidate requests, their issues, and the prepared request.
struct InboxView: View {
    @Bindable var model: AppModel
    @State private var showsPreferences = false
    @State private var confirmsWipe = false

    var body: some View {
        VStack(spacing: 0) {
            banners
            NavigationSplitView {
                BatchListView(model: model)
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
            } content: {
                BatchDetailView(model: model)
                    .navigationSplitViewColumnWidth(min: 480, ideal: 620)
            } detail: {
                RequestPanelView(model: model)
                    .navigationSplitViewColumnWidth(min: 320, ideal: 400, max: 480)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: openExport) {
                    Label("Import Export", systemImage: "tray.and.arrow.down")
                }
            }
            ToolbarItem(placement: .navigation) {
                Button {
                    showsPreferences = true
                } label: {
                    Label("Preferences", systemImage: "slider.horizontal.3")
                }
            }
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    confirmsWipe = true
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
                .disabled(model.batches.isEmpty && model.requests.isEmpty)
            }
        }
        .sheet(isPresented: $showsPreferences) { PreferencesView(model: model) }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            load(providers)
            return true
        }
        .confirmationDialog("Delete everything imported into this companion?", isPresented: $confirmsWipe,
                            titleVisibility: .visible) {
            Button("Delete Everything Permanently", role: .destructive) { model.deleteEverything() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes every imported issue, its evidence, and every prepared request from this Mac. It cannot be undone.")
        }
    }

    private func openExport() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.zip, .folder]
        panel.message = "Choose an IssueCapture export ZIP or expanded folder."
        panel.prompt = "Import"
        guard panel.runModal() == .OK else { return }
        model.importSources(panel.urls)
    }

    @ViewBuilder private var banners: some View {
        if !model.problems.isEmpty || !model.summaries.isEmpty || !model.staleDecisions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.problems) { problem in
                    BannerRow(icon: "exclamationmark.triangle.fill", tint: .orange,
                              title: "Import failed: \(problem.source)",
                              detail: problem.failure.detail) {
                        HStack(spacing: 8) {
                            if problem.failure.isRetryable {
                                Button("Retry") { model.retry(problem) }
                            }
                            Button("Dismiss") { model.dismiss(problem) }
                        }
                    }
                }
                ForEach(model.staleDecisions) { reason in
                    BannerRow(icon: "clock.arrow.circlepath", tint: .yellow,
                              title: "Manual decision needs review", detail: reason.detail) { EmptyView() }
                }
                ForEach(model.summaries) { summary in
                    BannerRow(icon: "tray.and.arrow.down.fill", tint: .secondary,
                              title: "Imported", detail: summary.message) {
                        Button("Dismiss") { model.dismiss(summary) }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
            Divider()
        }
    }

    private func load(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        let box = URLBox()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { box.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) { model.importSources(box.urls) }
    }

    /// Collects dropped URLs from the provider callbacks.
    private final class URLBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [URL] = []
        var urls: [URL] { lock.lock(); defer { lock.unlock() }; return storage }
        func append(_ url: URL) { lock.lock(); storage.append(url); lock.unlock() }
    }
}

/// One banner line with an icon, a message and trailing controls.
struct BannerRow<Actions: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            actions()
        }
    }
}
