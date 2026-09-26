import SwiftUI

struct ReporterLabelButton: View {
    let title: String
    let systemImage: String
    let role: ButtonRole?
    let action: () -> Void

    init(_ title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) { Label(title, systemImage: systemImage) }
    }
}

struct ReporterEmptyState: View {
    let title: String
    let systemImage: String
    let description: Text

    init(_ title: String, systemImage: String, description: Text) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        if #available(iOS 17, *) {
            ContentUnavailableView(title, systemImage: systemImage, description: description)
        } else {
            VStack(spacing: 12) {
                Label(title, systemImage: systemImage).font(.headline)
                description.foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).padding().accessibilityElement(children: .combine)
        }
    }
}

struct ReporterTextInput: View {
    let title: String
    @Binding var text: String
    let lines: ClosedRange<Int>

    init(_ title: String, text: Binding<String>, lines: ClosedRange<Int>) {
        self.title = title
        _text = text
        self.lines = lines
    }

    var body: some View {
        if #available(iOS 16, *) {
            TextField(title, text: $text, axis: .vertical).lineLimit(lines)
        } else {
            VStack(alignment: .leading) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $text).frame(minHeight: CGFloat(lines.lowerBound) * 24)
                    .accessibilityLabel(title)
            }
        }
    }
}
