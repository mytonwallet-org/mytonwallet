import UIKit

public extension UIColor {
    /// A tinted surface with fixed white content. The monochrome palette stays black in dark mode.
    var backgroundForWhiteContent: UIColor {
        UIColor { traits in
            let tint = self.resolvedColor(with: traits)
            return tint.isWhiteTint ? .black : tint
        }
    }

    /// Content on a tinted surface. Colored palettes keep white content.
    var foregroundForTintedBackground: UIColor {
        UIColor { traits in
            self.resolvedColor(with: traits).isWhiteTint ? .black : .white
        }
    }

    private var isWhiteTint: Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        return getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            && abs(red - 1) < 0.0001 && abs(green - 1) < 0.0001
            && abs(blue - 1) < 0.0001 && abs(alpha - 1) < 0.0001
    }
}
