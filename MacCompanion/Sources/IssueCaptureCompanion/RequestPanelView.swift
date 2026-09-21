import CompanionCore
import SwiftUI

/// Right pane: the prepared request, its attachments, and the handoff actions.
struct RequestPanelView: View {
    @Bindable var model: AppModel
    @State private var confirmsDeletion = false

    var body: some View {
        Group {
            if model.requests.isEmpty {
                ContentUnavailableView("No prepared requests", systemImage: "doc.badge.gearshape",
                                       description: Text("Choose a candidate request and select Prepare request."))
            } else {
                content
            }
        }
        .navigationTitle("Prepared request")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Request", selection: Binding(
                get: { model.selectedRequest?.request.id ?? model.requests[0].request.id },
                set: { model.selectedRequestID = $0 })) {
                    ForEach(model.requests) { handle in
                        Text("\(handle.request.title) · \(handle.request.preparedAt.formatted(date: .abbreviated, time: .shortened))")
                            .tag(handle.request.id)
                    }
                }
                .labelsHidden()
                .padding(12)
            Divider()
            if let handle = model.selectedRequest {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        summary(handle)
                        actions(handle)
                        attachments(handle)
                        issues(handle)
                        stateControls(handle)
                    }
                    .padding(16)
                }
            }
        }
    }

    private func summary(_ handle: PreparedRequestHandle) -> some View {
        let request = handle.request
        return GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Text(request.id.uuidString).font(.caption.monospaced()).textSelection(.enabled)
                Text("Project \(request.projectID) · \(request.environmentKey.label)")
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(request.issues.count) issue\(request.issues.count == 1 ? "" : "s") · "
                     + "\(request.attachmentCount) attachment\(request.attachmentCount == 1 ? "" : "s") · "
                     + ByteCountFormatter.string(fromByteCount: Int64(request.attachmentByteCount), countStyle: .file))
                    .font(.callout)
                Text("Rule \(request.ruleVersion) · Template \(request.templateVersion)")
                    .font(.caption2).foregroundStyle(.secondary)
                if request.attachmentCount > model.state.preferences.attachments.advisoryAttachmentCount {
                    Label("This request carries more attachments than your advisory threshold. Consider splitting it or changing the attachment choices. Nothing is truncated or recompressed automatically.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(request.title, systemImage: "doc.text")
        }
    }

    private func actions(_ handle: PreparedRequestHandle) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button("Copy prompt") { model.copyPrompt(handle) }
                    Button("Reveal folder") { model.revealFolder(handle) }
                    Spacer()
                    Button("Delete…", role: .destructive) { confirmsDeletion = true }
                }
                .confirmationDialog("Delete this prepared request?", isPresented: $confirmsDeletion,
                                    titleVisibility: .visible) {
                    Button("Delete Permanently", role: .destructive) { model.delete(request: handle) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This deletes the request folder from this Mac. The original issue evidence is not affected.")
                }
                FileDragView(urls: handle.dragURLs, label: AnyView(dragLabel(handle)))
                    .frame(height: 64)
                Text("Drag exposes \(handle.dragURLs.count) real file URL(s): request.md plus the chosen images. Copy places prompt text on the clipboard only — Markdown links alone do not attach images in chat tools.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Destination behavior is not verified by this build. Whether a given coding tool accepts a multi-file drop, and what it does with the folder, has to be checked in that tool.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Prepared, copied or dragged does not mean delivered, fixed or verified.")
                    .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Hand off", systemImage: "square.and.arrow.up")
        }
    }

    private func dragLabel(_ handle: PreparedRequestHandle) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.doc.fill").font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Drag files").font(.callout.weight(.medium))
                Text("\(handle.dragURLs.count) file(s)").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func attachments(_ handle: PreparedRequestHandle) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                if handle.request.attachments.isEmpty {
                    Text("No images are attached. request.md and the evidence folder still travel with the drag.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(handle.request.attachments) { attachment in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.path).font(.caption.monospaced()).textSelection(.enabled)
                        Text("\(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file)) · sha256 \(attachment.sha256.prefix(16))…")
                            .font(.caption2).foregroundStyle(.secondary)
                        ForEach(attachment.links, id: \.self) { link in
                            Text("\(link.kind.title) for \(link.issueID.uuidString)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Attachments", systemImage: "paperclip")
        }
    }

    private func issues(_ handle: PreparedRequestHandle) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(handle.request.issues) { issue in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(issue.order). \(issue.displayID)").font(.callout.weight(.medium))
                        Text(issue.issueID.uuidString).font(.caption2.monospaced())
                            .foregroundStyle(.secondary).textSelection(.enabled)
                        Text("Revision \(issue.revisionIndex) — snapshotted, so later imports do not change this request.")
                            .font(.caption2).foregroundStyle(.secondary)
                        ForEach(issue.warnings) { warning in
                            Label(warning.detail, systemImage: "exclamationmark.triangle")
                                .font(.caption2).foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Issues", systemImage: "list.bullet")
        }
    }

    private func stateControls(_ handle: PreparedRequestHandle) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Picker("Local state", selection: Binding(
                    get: { model.state.state(for: handle.request.id) },
                    set: { model.setState($0, for: handle) })) {
                        ForEach(RequestLocalState.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                Text("These states are your own bookkeeping. Automatic delivery would require a supported integration and an explicit action; this build has none.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Status", systemImage: "flag")
        }
    }
}
