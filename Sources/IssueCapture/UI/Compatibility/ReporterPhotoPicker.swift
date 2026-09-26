import PhotosUI
import SwiftUI

/// System photo selection without requesting access to the entire library.
struct ReporterPhotoPicker: UIViewControllerRepresentable {
    @Binding var loading: Bool
    let onImage: (UIImage) -> Void
    let onError: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ReporterPhotoPicker
        init(_ parent: ReporterPhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            guard let provider = results.first?.itemProvider else { return }
            parent.loading = true
            provider.loadObject(ofClass: UIImage.self) { [parent] object, error in
                DispatchQueue.main.async {
                    parent.loading = false
                    if let image = object as? UIImage { parent.onImage(image) }
                    else { parent.onError(error?.localizedDescription ?? "Unable to load the selected image.") }
                }
            }
        }
    }
}
