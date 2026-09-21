import CompanionCore
import IssueCaptureSchema
import SwiftUI

/// Middle pane: the issues in the selected candidate request, why they are
/// together, and the adjustments the user can make without touching evidence.
struct BatchDetailView: View {
    @Bindable var model: AppModel
    @State private var groupName = ""
    @State private var instructions = ""
    @State private var showsRelatedNotes = false

    var body: some View {
        Group {
            if let batch = model.selectedBatch {
                content(batch)
            } else {
                ContentUnavailableView("No candidate request selected", systemImage: "square.stack.3d.up")
            }
        }
        .navigationTitle(model.selectedBatch?.title ?? "Issues")
    }

    private func content(_ batch: CandidateBatch) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                reasons(batch)
                adjustments(batch)
                ForEach(batch.members) { member in
                    if let revision = model.revision(for: member) {
                        IssueCardView(model: model, revision: revision, batch: batch)
                    } else {
                        Label("Evidence for \(member.key.issueID) is missing from the store.",
                              systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.orange)
                    }
                }
                relatedNotes(batch)
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) { prepareBar(batch) }
        .onChange(of: batch.id, initial: true) { _, _ in
            instructions = model.instructions(for: batch)
            groupName = batch.origin == .manual ? batch.title : ""
            showsRelatedNotes = false
        }
    }

    private func reasons(_ batch: CandidateBatch) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(batch.reasons) { reason in
                    Label(reason.detail, systemImage: "info.circle")
                        .font(.callout).labelStyle(.titleAndIcon)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Grouping is a mechanical proposal from recorded metadata. It is not a claim that these issues share a root cause.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Rule version \(batch.ruleVersion)").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Why these are together", systemImage: "questionmark.circle")
        }
    }

    @ViewBuilder private func relatedNotes(_ batch: CandidateBatch) -> some View {
        if !batch.relatedNotes.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(batch.relatedNotes.count) metadata connection\(batch.relatedNotes.count == 1 ? "" : "s") found. These do not merge issues automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    DisclosureGroup("Show connections", isExpanded: $showsRelatedNotes) {
                        LazyVStack(alignment: .leading, spacing: 5) {
                            ForEach(batch.relatedNotes) { note in
                                RelatedNoteRow(note: note)
                            }
                        }
                        .padding(.top, 6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Related, not merged", systemImage: "link")
            }
        }
    }

    private func adjustments(_ batch: CandidateBatch) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Split or merge by pinning issues to a named group. Decisions are remembered against the exact revision you reviewed.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("Group name", text: $groupName)
                    Button("Pin all to group") {
                        for member in batch.members {
                            guard let revision = model.revision(for: member) else { continue }
                            model.assign(revision: revision, to: groupName)
                        }
                    }
                    .disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Divider()
                Text("Request instructions (kept separate from report content)").font(.caption)
                TextEditor(text: $instructions)
                    .font(.callout)
                    .frame(minHeight: 60)
                    .border(.separator)
                    .onChange(of: instructions) { _, value in model.setInstructions(value, for: batch) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Adjust", systemImage: "slider.horizontal.below.rectangle")
        }
    }

    private func prepareBar(_ batch: CandidateBatch) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(batch.members.count) issue\(batch.members.count == 1 ? "" : "s") selected")
                    .font(.callout.weight(.medium))
                Text("Creates a request with chosen evidence files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Prepare Request") { model.prepare(batch: batch) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(batch.members.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// One optional metadata connection shown only when the user expands the list.
private struct RelatedNoteRow: View {
    let note: RelatedNote

    var body: some View {
        let label = note.kind == .sharedTag
            ? "Shared tag: \(note.value)" : "Shared event: \(note.value)"
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption.weight(.medium))
            Text(note.issueID.uuidString)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One issue: authored text, context, warnings and evidence previews.
struct IssueCardView: View {
    @Bindable var model: AppModel
    let revision: IssueRevision
    let batch: CandidateBatch
    @State private var isExpanded = false
    @State private var confirmsDeletion = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                header
                Text(revision.report.description.isEmpty
                     ? "No description was authored." : revision.report.description)
                    .font(.callout)
                    .lineLimit(isExpanded ? nil : 3)
                    .textSelection(.enabled)
                if isExpanded { expanded }
                warnings
                EvidenceStripView(model: model, revision: revision)
                controls
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(revision.report.displayID).font(.headline)
                Spacer()
                Text(model.state.state(for: revision.issueKey).title)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(revision.issueKey.issueID.uuidString)
                .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(revision.issueKey.issueID.uuidString)
            Text("Revision \(revision.revisionIndex) · captured \(revision.report.capturedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var expanded: some View {
        labelled("Expected behavior", revision.report.expectedBehavior)
        labelled("Reproduction notes", revision.report.reproductionNotes)
        labelled("Screen context", revision.report.contextStatus)
        ForEach(revision.report.screens, id: \.id) { screen in
            Text("\(screen.name) — \(screen.typeName) — \(screen.file):\(screen.line)")
                .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
        }
        if !revision.report.events.isEmpty {
            Text("Observed events (observations, not reproduction steps)")
                .font(.caption.weight(.semibold))
            ForEach(revision.report.events.prefix(8), id: \.id) { event in
                Text("#\(event.sequence) [\(event.category)] \(event.name) — \(event.screen?.name ?? "UNSCOPED")")
                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
            if revision.report.events.count > 8 {
                Text("\(revision.report.events.count - 8) more in the prepared request. Complete text is never truncated there.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func labelled(_ title: String, _ value: String) -> some View {
        Text(title).font(.caption.weight(.semibold))
        Text(value.isEmpty ? "Not supplied" : value)
            .font(.caption).foregroundStyle(value.isEmpty ? .secondary : .primary)
            .textSelection(.enabled)
    }

    @ViewBuilder private var warnings: some View {
        if !revision.warnings.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(revision.warnings) { warning in
                    Label(warning.detail, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var controls: some View {
        HStack {
            Button(isExpanded ? "Show less" : "Show full report") { isExpanded.toggle() }
                .buttonStyle(.borderless)
                .contentShape(Rectangle())
                .padding(.vertical, 4)
            Spacer()
            if batch.origin == .manual {
                Button("Return to rules") { model.unassign(revision: revision) }
                    .buttonStyle(.borderless)
                    .contentShape(Rectangle())
                    .padding(.vertical, 4)
            }
            Button("Delete Issue…", role: .destructive) { confirmsDeletion = true }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .contentShape(Rectangle())
                .padding(.vertical, 4)
        }
        .font(.caption)
        .confirmationDialog("Delete this issue?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("Delete Permanently", role: .destructive) {
                model.delete(issue: revision.issueKey)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes \(revision.report.displayID) and all its evidence from this Mac. It cannot be undone.")
        }
    }
}
