import CompanionCore
import SwiftUI

/// Sidebar listing candidate requests, grouped by project and build partition.
struct BatchListView: View {
    @Bindable var model: AppModel

    private var partitions: [(key: String, title: String, batches: [CandidateBatch])] {
        var order: [String] = []
        var grouped: [String: [CandidateBatch]] = [:]
        for batch in model.batches {
            let key = "\(batch.projectID)\u{1F}\(batch.environmentKey.token)"
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(batch)
        }
        return order.map { key in
            let batches = grouped[key] ?? []
            let title = "\(batches.first?.projectID ?? "") · \(batches.first?.environmentKey.label ?? "")"
            return (key, title, batches)
        }
    }

    var body: some View {
        List(selection: $model.selectedBatchID) {
            if model.batches.isEmpty {
                ContentUnavailableView("Nothing imported yet", systemImage: "tray",
                                       description: Text("Open an export ZIP or expanded folder, or drop one here."))
            }
            ForEach(partitions, id: \.key) { partition in
                Section {
                    ForEach(partition.batches) { batch in
                        row(batch).tag(batch.id)
                    }
                } header: {
                    Text(partition.title).font(.caption)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Candidate requests")
        .overlay(alignment: .bottom) { footer }
    }

    private func row(_ batch: CandidateBatch) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: batch.origin == .manual ? "hand.point.up.left.fill" : "square.stack.3d.up")
                    .foregroundStyle(batch.origin == .manual ? Color.accentColor : .secondary)
                Text(batch.title).font(.body.weight(.medium)).lineLimit(1)
            }
            Text("\(batch.members.count) issue\(batch.members.count == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.secondary)
            if let reason = batch.reasons.first {
                Text(reason.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var footer: some View {
        if model.warningCount > 0 {
            Label("\(model.warningCount) evidence warning\(model.warningCount == 1 ? "" : "s")",
                  systemImage: "exclamationmark.triangle")
                .font(.caption)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
        }
    }
}
