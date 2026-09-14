import AppKit
import CompanionCore
import IssueCaptureSchema
import SwiftUI

/// Previews for a revision's received images, with the attachment decision and
/// its reason shown next to each one.
struct EvidenceStripView: View {
    @Bindable var model: AppModel
    let revision: IssueRevision

    var body: some View {
        let decisions = model.decisions(for: revision)
        if decisions.isEmpty {
            Text("No image files were received for this issue.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(decisions) { decision in
                        tile(decision)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func tile(_ decision: AttachmentDecision) -> some View {
        let fact = revision.fact(for: decision.kind)
        return VStack(alignment: .leading, spacing: 4) {
            preview(decision.kind)
            Text(decision.kind.title).font(.caption.weight(.medium))
            if let fact {
                Text("\(fact.filename) · \(ByteCountFormatter.string(fromByteCount: Int64(fact.byteCount), countStyle: .file))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Toggle("Attach", isOn: Binding(
                get: { decision.isAttached },
                set: { model.setExcluded(!$0, revision: revision, kind: decision.kind) }))
                .toggleStyle(.checkbox)
                .font(.caption2)
            Text(decision.reason)
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 180, alignment: .leading)
    }

    @ViewBuilder private func preview(_ kind: IssueExportImageKind) -> some View {
        if let url = model.store.url(in: revision, kind: kind), let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable().scaledToFit()
                .frame(width: 180, height: 120)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onTapGesture { NSWorkspace.shared.open(url) }
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.1))
                .frame(width: 180, height: 120)
                .overlay {
                    Label("Not previewable", systemImage: "photo").font(.caption2)
                        .foregroundStyle(.secondary)
                }
        }
    }
}
