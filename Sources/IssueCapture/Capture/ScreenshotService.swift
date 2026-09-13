import UIKit

@MainActor
enum ScreenshotService {
    static func capture(window: UIWindow?) -> (UIImage?, String) {
        guard let window, window.bounds.width > 0, window.bounds.height > 0 else {
            return (nil, "failed: app window unavailable; attach an image manually")
        }
        var rendered = false
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        let status = rendered
            ? "rendered, fidelity unverified: system keyboard/windows and protected content may be absent"
            : "partial: UIKit reported missing image data; attach a screenshot if needed"
        return (image, status)
    }

    static func environment(window: UIWindow?, configuration: IssueCaptureConfiguration) -> [String: String] {
        let bundle = Bundle.main
        let device = UIDevice.current
        var result = [
            "appVersion": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unavailable",
            "build": bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unavailable",
            "systemVersion": device.systemVersion,
            "deviceModel": device.model,
            "locale": Locale.current.identifier,
            "timezone": TimeZone.current.identifier,
            "orientation": window?.windowScene?.interfaceOrientation.isLandscape == true ? "landscape" : "portrait",
            "appearance": window?.traitCollection.userInterfaceStyle == .dark ? "dark" : "light",
            "dynamicType": window?.traitCollection.preferredContentSizeCategory.rawValue ?? "unavailable"
        ]
        if let revision = configuration.sourceRevision { result["sourceRevision"] = revision }
        return result
    }
}
