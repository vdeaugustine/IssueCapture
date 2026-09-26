import SwiftUI

/// Compact one-row tag chooser. Selected tags sort first so the current
/// selection is readable without expanding anything.
struct IssueTagPicker: View {
    @Binding var tags: [String]?
    @State private var customTag = ""
    @State private var addingCustom = false
    @FocusState private var customFocused: Bool
    private let suggestions = ["z fighting", "bad placement", "clipping", "visual glitch",
                               "layout", "performance", "interaction", "accessibility"]

    private var selected: [String] { tags ?? [] }

    private var choices: [String] {
        let all = Array(Set(suggestions + selected)).sorted()
        return all.filter { selected.contains($0) } + all.filter { !selected.contains($0) }
    }

    var body: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(choices, id: \.self) { tag in
                        chip(tag)
                    }
                    Button {
                        addingCustom = true
                        customFocused = true
                    } label: {
                        Label("New", systemImage: "plus")
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().strokeBorder(.tint.opacity(0.5)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Add custom tag")
                }
                .padding(.vertical, 2)
            }
            .reporterScrollClip()
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            if addingCustom {
                HStack {
                    TextField("Custom tag", text: $customTag)
                        .focused($customFocused)
                        .submitLabel(.done)
                        .onSubmit(addTag)
                    Button("Add", action: addTag)
                        .disabled(cleanTag.isEmpty)
                        .buttonStyle(.borderless)
                }
            }
        } header: {
            Text("Tags")
        }
    }

    private func chip(_ tag: String) -> some View {
        let isOn = selected.contains(tag)
        return Button {
            var updated = selected
            if isOn { updated.removeAll { $0 == tag } } else { updated.append(tag) }
            tags = updated
        } label: {
            Text(tag)
                .font(.subheadline)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary)))
                .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var cleanTag: String { customTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    private func addTag() {
        guard !cleanTag.isEmpty else { return }
        if !selected.contains(cleanTag) { tags = selected + [cleanTag] }
        customTag = ""
        addingCustom = false
    }
}
