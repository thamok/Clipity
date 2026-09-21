import SwiftUI

enum ClipTheme {
    /// Requested brand blue: #0042A9. White button labels retain strong contrast.
    static let accent = Color(red: 0, green: 66.0 / 255, blue: 169.0 / 255)
    /// A lighter companion keeps small labels legible on dark surfaces.
    static let foreground = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.48, green: 0.68, blue: 1, alpha: 1)
                : UIColor(red: 0, green: 66.0 / 255, blue: 169.0 / 255, alpha: 1)
        })
}
