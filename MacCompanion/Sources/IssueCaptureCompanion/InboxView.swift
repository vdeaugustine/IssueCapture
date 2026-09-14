import CompanionCore
import SwiftUI
import UniformTypeIdentifiers

/// Three panes: candidate requests, their issues, and the prepared request.
struct InboxView: View {
    @Bindable var model: AppModel
    @State private var showsPreferences = false

    var body: some View {
        NavigationSplitView {
            BatchListView(model: model)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } content: {
            BatchDetailView(model: model)
                .navigationSplitViewColumnWidth(min: 360, ideal: 440)
        } detail: {
            RequestPanelView(model: model)
                .navigationSplitViewColumnWidth(min: 360, ideal: 420)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    showsPreferences = true
                } label: {
                    Label("Preferences", systemImage: "slider.horizontal.3")
                }
            }
        }
        .safeAreaInset(edge: .top) { banners }
        .sheet(isPresented: $showsPreferences) { PreferencesView(model: model) }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            load(providers)
            return true
        }
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
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            actions()
        }
    }
}
