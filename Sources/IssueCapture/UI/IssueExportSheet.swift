import SwiftUI

struct IssueExportSheet: View {
    let reports: [IssueReport]
    let onExport: (ExportImageOptions) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var options = ExportImageOptions()
    @State private var showPerImageOptions = false
    @State private var bulkQuality = ExportImageQuality.original

    var body: some View {
        ReporterNavigation {
            Form {
                Section {
                    Label("\(reports.count) issues ready to export", systemImage: "archivebox")
                        .font(.headline)
                    Text("Includes complete descriptions, tags, screen context, and event history.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Toggle("Include issue cards", isOn: $options.includeCards)
                } footer: {
                    Text("Cards combine each issue with its image. Text also stays available in full in Markdown and JSON.")
                }
                Section {
                    Picker("Image quality", selection: $bulkQuality) {
                        ForEach(ExportImageQuality.allCases, id: \.self) { quality in
                            Text(quality.title).tag(quality)
                        }
                    }
                    .onChange(of: bulkQuality) { quality in
                        for report in reports {
                            for kind in ExportImageKind.allCases {
                                options.qualities[ExportImageKey(reportID: report.id, kind: kind)] = quality
                            }
                        }
                    }
                    Toggle("Customize individual images", isOn: $showPerImageOptions)
                } header: { Text("Quick settings") } footer: {
                    Text("Full detail is the default. JPEG compression reduces fine detail; keep text and subtle rendering bugs at full detail. Pixel dimensions stay unchanged. Smaller PNGs are kept when JPEG would be larger. Originals on this device stay untouched.")
                }
                if showPerImageOptions {
                    ForEach(reports) { report in
                        Section {
                            Text(report.description).font(.subheadline).lineLimit(3)
                            ForEach(options.kinds(for: report), id: \.self) { kind in
                                Picker(kind.title, selection: qualityBinding(report, kind: kind)) {
                                    ForEach(ExportImageQuality.allCases, id: \.self) { quality in
                                        Text(quality.title).tag(quality)
                                    }
                                }
                            }
                        } header: { Text(report.displayID) }
                    }
                }
            }
            .navigationTitle("Export evidence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Prepare ZIP") { onExport(options) }
                }
            }
        }
    }

    private func qualityBinding(_ report: IssueReport, kind: ExportImageKind) -> Binding<ExportImageQuality> {
        Binding(get: { options.quality(for: report, kind: kind) },
                set: { options.qualities[ExportImageKey(reportID: report.id, kind: kind)] = $0 })
    }
}
