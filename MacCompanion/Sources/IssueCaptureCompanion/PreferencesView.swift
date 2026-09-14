import CompanionCore
import SwiftUI

/// Preferences for batching, attachments and the optional watched folder.
struct PreferencesView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Batching") {
                    Stepper("Maximum issues per candidate request: \(model.state.preferences.batching.maximumIssuesPerRequest)",
                            value: Binding(
                                get: { model.state.preferences.batching.maximumIssuesPerRequest },
                                set: { model.state.preferences.batching.maximumIssuesPerRequest = $0
                                       model.refresh() }),
                            in: 1...50)
                    Text("Larger rule-derived groups are split in capture order. Manual groups are never split automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Attachments") {
                    Toggle("Attach the unannotated capture alongside the annotated one",
                           isOn: binding(\.attachments.includeUnannotatedWithAnnotated))
                    Toggle("Attach rendered issue cards", isOn: binding(\.attachments.includeIssueCards))
                    Stepper("Advisory attachment count: \(model.state.preferences.attachments.advisoryAttachmentCount)",
                            value: binding(\.attachments.advisoryAttachmentCount), in: 1...200)
                    Text("The advisory threshold is a local readability hint, not a verified limit of any destination tool.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Watched folder") {
                    if let url = model.watchedFolderURL {
                        Text(url.path).font(.caption.monospaced()).textSelection(.enabled)
                    } else {
                        Text("No folder chosen. Use File ▸ Choose Watched Folder…")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Watch this folder for finished export archives",
                           isOn: Binding(get: { model.state.preferences.isWatchingEnabled },
                                         set: { model.setWatching($0) }))
                        .disabled(model.state.preferences.watchedFolderBookmark == nil)
                    Button("Forget watched folder") { model.clearWatchedFolder() }
                        .disabled(model.state.preferences.watchedFolderBookmark == nil)
                    Text("Archives are imported only after their size stops changing, so a copy still in flight is never read. Source files are never moved. The companion does not take over ZIP file associations.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 520, height: 520)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<CompanionPreferences, Value>) -> Binding<Value> {
        Binding(get: { model.state.preferences[keyPath: keyPath] },
                set: { model.state.preferences[keyPath: keyPath] = $0 })
    }
}
