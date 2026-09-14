import SwiftUI

struct IssueAnnotationEditor: View {
    let image: UIImage
    @Binding var annotations: [IssueAnnotation]
    @Environment(\.dismiss) private var dismiss
    @State private var tool: IssueAnnotation.Kind = .arrow

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Drawing tool", selection: $tool) {
                        ForEach(IssueAnnotation.Kind.allCases, id: \.self) { kind in
                            Text(kind.rawValue.capitalized).tag(kind)
                        }
                    }.pickerStyle(.segmented)
                    Text("Draw on the image to highlight the problem.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    AnnotationCanvas(image: image, annotations: $annotations, tool: tool)
                    HStack {
                        Button("Undo", systemImage: "arrow.uturn.backward") { _ = annotations.popLast() }
                        Spacer()
                        Button("Clear all", role: .destructive) { annotations = [] }
                    }.disabled(annotations.isEmpty)
                }.padding()
            }
            .navigationTitle("Annotate image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
