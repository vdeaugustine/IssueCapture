import SwiftUI

struct IssueTagPicker: View {
    @Binding var tags: [String]?
    @State private var customTag = ""
    private let suggestions = ["z fighting", "bad placement", "clipping", "visual glitch", "layout", "performance", "interaction", "accessibility"]

    private var choices: [String] { Array(Set(suggestions + (tags ?? []))).sorted() }

    var body: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 135))], alignment: .leading) {
                ForEach(choices, id: \.self) { tag in
                    Button {
                        var updated = tags ?? []
                        if updated.contains(tag) { updated.removeAll { $0 == tag } } else { updated.append(tag) }
                        tags = updated
                    } label: {
                        Label(tag, systemImage: (tags ?? []).contains(tag) ? "checkmark.circle.fill" : "plus.circle")
                            .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityAddTraits((tags ?? []).contains(tag) ? .isSelected : [])
                }
            }
            HStack {
                TextField("Custom tag", text: $customTag).onSubmit(addTag)
                Button("Add", action: addTag).disabled(cleanTag.isEmpty).buttonStyle(.borderless)
            }
        } header: { Text("Tags") } footer: { Text("Choose any that apply. Use tags to filter issues and group exports.") }
    }

    private var cleanTag: String { customTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    private func addTag() {
        guard !cleanTag.isEmpty else { return }
        if !(tags ?? []).contains(cleanTag) { tags = (tags ?? []) + [cleanTag] }
        customTag = ""
    }
}
