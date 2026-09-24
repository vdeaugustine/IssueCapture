import SwiftUI

struct IssueAnnotationEditor: View {
    let image: UIImage
    @Binding var annotations: [IssueAnnotation]
    @Environment(\.dismiss) private var dismiss
    @State private var tool: IssueAnnotation.Kind = .rectangle
    @State private var ink: IssueAnnotation.Ink = .red
    @State private var undoHistory: [[IssueAnnotation]] = []
    @State private var redoHistory: [[IssueAnnotation]] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                annotationToolbar
                ScrollView {
                    VStack(spacing: 16) {
                        Text("Draw on the image to highlight the problem.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        AnnotationCanvas(image: image, annotations: $annotations, tool: tool, ink: ink) {
                            recordChange(from: $0)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Annotate image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var annotationToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Menu {
                    ForEach(IssueAnnotation.Kind.allCases, id: \.self) { option in
                        Button {
                            tool = option
                        } label: {
                            Label(option.rawValue.capitalized, systemImage: toolSymbol(for: option))
                        }
                    }
                } label: {
                    Label(tool.rawValue.capitalized, systemImage: toolSymbol(for: tool))
                }
                .accessibilityLabel("Drawing tool: \(tool.rawValue)")

                Button(action: undo) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .accessibilityLabel("Undo")
                .disabled(undoHistory.isEmpty)
                Button(action: redo) {
                    Image(systemName: "arrow.uturn.forward")
                }
                .accessibilityLabel("Redo")
                .disabled(redoHistory.isEmpty)
                Menu {
                    ForEach(IssueAnnotation.Ink.allCases, id: \.self) { option in
                        Button {
                            ink = option
                        } label: {
                            Label(option.rawValue.capitalized, systemImage: option == ink ? "checkmark.circle.fill" : "circle.fill")
                                .tint(AnnotationDrawing.color(option))
                        }
                    }
                } label: {
                    Label("Color", systemImage: "paintpalette.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(AnnotationDrawing.color(ink))
                }
                .accessibilityLabel("Annotation color: \(ink.rawValue)")
                Button(role: .destructive, action: clear) {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Clear all annotations")
                .disabled(annotations.isEmpty)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    private func recordChange(from previous: [IssueAnnotation]) {
        undoHistory.append(previous)
        redoHistory.removeAll()
    }

    private func undo() {
        guard let previous = undoHistory.popLast() else { return }
        redoHistory.append(annotations)
        annotations = previous
    }

    private func redo() {
        guard let next = redoHistory.popLast() else { return }
        undoHistory.append(annotations)
        annotations = next
    }

    private func clear() {
        guard !annotations.isEmpty else { return }
        recordChange(from: annotations)
        annotations = []
    }

    private func toolSymbol(for tool: IssueAnnotation.Kind) -> String {
        switch tool {
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .pen: "pencil.tip"
        }
    }
}
