import SwiftUI
import UIKit

/// Orange and red for words. On a white row the standard system orange is about 2.2:1 and the red about 3.6:1, which
/// footnote-sized text cannot use (4.5:1). These are the system's own higher-contrast variants in light appearance
/// and the standard colours in dark, where they already pass; `TextColorTests` measures them on the surfaces they sit
/// on. Fills, rings and pins keep the standard colours.
extension UIColor {
    /// Something to check or decide: a pin that could not be placed, sync that did not start.
    static let cautionText = legible(.systemOrange)
    /// Something failed: a save that did not happen.
    static let problemText = legible(.systemRed)
    /// A red that white words can sit on in either appearance.
    static let problemFill = UIColor.systemRed.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)
        .modifyingTraits { $0.accessibilityContrast = .high })

    private static func legible(_ color: UIColor) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? color.resolvedColor(with: traits)
                : color.resolvedColor(with: traits.modifyingTraits { $0.accessibilityContrast = .high })
        }
    }
}

extension Color {
    static let cautionText = Color(uiColor: .cautionText)
    static let problemText = Color(uiColor: .problemText)
    static let problemFill = Color(uiColor: .problemFill)
}
