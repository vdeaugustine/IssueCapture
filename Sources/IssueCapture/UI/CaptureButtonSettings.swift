import SwiftUI

struct CaptureButtonSettings: View {
    @ObservedObject var session: CaptureSession
    let onClose: () -> Void

    var body: some View {
        Form {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "ladybug.fill")
                        .font(.title3)
                        .foregroundStyle(Color(uiColor: session.buttonAppearance.foregroundColor))
                        .frame(width: session.buttonAppearance.resolvedDiameter,
                               height: session.buttonAppearance.resolvedDiameter)
                        .background(Color(uiColor: session.buttonAppearance.backgroundColor), in: Circle())
                        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
                        .accessibilityLabel("Capture button preview")
                    Text("Your capture shortcut") .font(.headline)
                    Text("Tap to report. Hold for tools. Drag to either edge.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 20)
            }
            Section {
                ColorPicker("Button color", selection: colorBinding(\.backgroundColor), supportsOpacity: false)
                ColorPicker("Icon color", selection: colorBinding(\.foregroundColor), supportsOpacity: false)
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("Size"); Spacer(); Text("\(Int(session.buttonAppearance.resolvedDiameter)) pt") }
                    Slider(value: Binding(get: { Double(session.buttonAppearance.resolvedDiameter) }, set: {
                        session.buttonAppearance.diameter = CGFloat($0)
                        session.overlay?.updateButtonAppearance()
                    }), in: 44...80, step: 4)
                    .accessibilityLabel("Capture button size")
                }
                Button("Restore host defaults") {
                    session.buttonAppearance = session.configuration.captureButtonAppearance
                    session.overlay?.updateButtonAppearance()
                }
            } header: { Text("Appearance") } footer: {
                Text("Changes apply to this session. App developers can set permanent defaults in IssueCaptureConfiguration. Keep the icon easy to see against its background.")
            }
        }
        .navigationTitle("Capture button")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onClose) } }
    }

    private func colorBinding(_ keyPath: WritableKeyPath<CaptureButtonAppearance, UIColor>) -> Binding<Color> {
        Binding(get: { Color(uiColor: session.buttonAppearance[keyPath: keyPath]) }, set: {
            session.buttonAppearance[keyPath: keyPath] = UIColor($0)
            session.overlay?.updateButtonAppearance()
        })
    }
}
