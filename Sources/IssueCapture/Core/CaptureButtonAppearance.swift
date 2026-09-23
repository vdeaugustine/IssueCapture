import UIKit

/// Appearance of the draggable capture button. Defaults to an adaptive neutral surface.
public struct CaptureButtonAppearance {
    /// Background color, including adaptive UIKit colors.
    public var backgroundColor: UIColor
    /// Icon color. Choose a color with sufficient contrast against the background.
    public var foregroundColor: UIColor
    /// Diameter in points, constrained to an accessible 44–80 point range when displayed.
    public var diameter: CGFloat

    /// Creates a capture button style with an accessible touch target.
    public init(backgroundColor: UIColor = .secondarySystemBackground,
                foregroundColor: UIColor = .label, diameter: CGFloat = 48) {
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.diameter = diameter
    }

    var resolvedDiameter: CGFloat { diameter.isFinite ? min(80, max(44, diameter)) : 48 }
}
